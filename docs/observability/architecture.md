# Observability Architecture

Sprint 5.1. This document describes what collects what, and why each choice was
made the way it was. It is written for someone who has to change this later.

## Scope of this phase

Metrics only: Prometheus, Grafana, kube-state-metrics, and node-exporter. Logs
(Loki), traces (Tempo), and alerting (Alertmanager) arrive in later phases and
are deliberately absent here — a component that has nothing to route or nothing
to query is a component nobody maintains.

## What was already emitting metrics

Nothing had to be added for these. Each endpoint was probed directly from the
node before any scrape job was written, and the series counts below are what
they actually returned:

| Source | Endpoint | Series | Discovered by |
|---|---|---|---|
| Argo CD server | `:8083/metrics` | 2371 | explicit `argocd` job |
| Argo CD application controller | `:8082/metrics` | 765 | explicit `argocd` job |
| Traefik | pod `:9100/metrics` | 728 | explicit `traefik` job |
| cert-manager | `:9402/metrics` | 302 | explicit `cert-manager` job |
| CoreDNS | `kube-dns:9153/metrics` | 266 | chart annotation job |
| Argo CD repo server | `:8084/metrics` | 100 | explicit `argocd` job |
| kubelet, cAdvisor | node `:10250` | — | chart default jobs |
| kube-apiserver | `:6443/metrics` | — | chart default job |

Argo CD and cert-manager carry no `prometheus.io` annotations, so annotation
based discovery does not find them. They have explicit jobs. CoreDNS is
annotated by k3s and is picked up by the chart's `kubernetes-service-endpoints`
job.

## Two traps worth knowing about

**Traefik publishes metrics on the pod only.** Its Service exposes `web` and
`websecure` and nothing else. An endpoints-based scrape job renders correctly,
passes schema validation, deploys without error, and collects zero series. The
`traefik` job therefore uses `role: pod`, and
`scripts/validate-observability.sh` asserts that specific fact so a future edit
cannot quietly undo it.

**The k3s Traefik manifest annotates the wrong port.** k3s sets
`prometheus.io/port: "8082"` in the chart values, but the chart emits its own
annotations afterwards and the effective value on the running pod is `9100`,
which is where metrics are actually served. Reading the k3s manifest rather than
the running pod leads to a scrape job pointed at a closed port.

## What was added

| Component | Purpose | Why not something else |
|---|---|---|
| Prometheus | Metric storage and query | — |
| kube-state-metrics | Object state: replica counts, pod phase, PVC capacity | Does **not** duplicate metrics-server, which serves the Metrics API for `kubectl top` and autoscaling and exposes no equivalent series |
| node-exporter | Linux node metrics | None existed on this host |
| Grafana | Dashboards | — |

Alertmanager, pushgateway, and the pushgateway scrape job are explicitly
disabled. The chart defines a pushgateway job whether or not the subchart is
installed; left enabled it polls a Service that does not exist and reports a
permanently down target, which teaches operators to ignore red.

## Why not kube-prometheus-stack

It ships roughly ten CRDs, a Prometheus Operator, and a default rule set written
for multi-node clusters with an external etcd. This is a single-node k3s using
SQLite, so a large share of those rules alert on conditions that cannot occur
here. The operator's memory cost is also not affordable: the node's limits are
already committed past 100%.

Scrape configuration is instead explicit in
`kubernetes/observability/prometheus/helm-values.yaml`, where it can be read and
reviewed in a pull request.

## Resource budget

The node has ~7.9Gi allocatable with requests at 31% and limits already at 119%,
and 15G of free disk shared with the host PostgreSQL. Every container declares
both a request and a limit, and `validate-observability.sh` fails the build if
any does not — an unbounded monitoring container can starve the workloads it
exists to observe.

Rendered totals for this phase:

```text
requests   cpu 260m    memory 648Mi
limits     cpu 1400m   memory 1408Mi
disk       3Gi Prometheus + 512Mi Grafana
```

Prometheus retains 7 days at a 30s scrape interval, capped additionally at 2GB
by `retentionSize` so the volume cannot fill.

## Storage and durability

`local-path` is the only StorageClass on this node. Observability data is
therefore node-local, is not replicated, and **is lost when the node is
rebuilt**. That is acceptable: dashboards and rules live in Git and are
recreated by Argo CD, and metric history is not part of the recovery objective.
It is called out in `docs/recovery/disaster-recovery.md` so nobody plans around
history surviving.

## Access

Grafana is not exposed publicly in this phase. Publishing it requires a DNS
record, a certificate, and an authentication decision, none of which belong in a
change whose purpose is to start collecting metrics.

```bash
kubectl --namespace observability port-forward svc/novashop-grafana 3000:80
```

The admin credential comes from a Secret named `novashop-grafana-admin`, created
outside Git exactly like the runtime database credentials. Dashboards are
provisioned from ConfigMaps labelled `grafana_dashboard`, so every dashboard is a
reviewable file rather than a UI artefact that disappears with the volume.

## Deployment path

Argo CD, like everything else. The Applications live in the GitOps repository
under `clusters/ubuntu-k3s/phases/tls-baseline/`, so observability is present in
both the baseline and enforced TLS phases.

**Known limitation:** the break-glass `phases/http` does not include
observability, because the platform AppProject it depends on is defined in
`tls-baseline`. Monitoring is most valuable during an incident, so moving both
into the base phase is a worthwhile follow-up.

## Datastore exporters (Phase 3)

PostgreSQL and Redis run on the node, not in the cluster. Phase 1 made them
reachable from the pod network, so both exporters run in-cluster under Argo CD
rather than as systemd units on the host, which removes host configuration drift
from the design.

| Exporter | Chart | Credential |
|---|---|---|
| postgres_exporter | `prometheus-postgres-exporter` 8.2.0 | `novashop_exporter` role, `pg_monitor` only |
| redis_exporter | `prometheus-redis-exporter` 6.28.0 | `requirepass`, no ACL user available |

The PostgreSQL exporter uses a dedicated role rather than the application
credential, so a metrics collector has no write access to production data.
Verified against the running database:

```text
exporter   stats=5 rows   write=denied(InsufficientPrivilegeError)
app        stats=5 rows   write=ALLOWED
```

Granting `pg_monitor` alone was **not** sufficient. PostgreSQL 14 grants `CREATE`
on schema `public` to `PUBLIC`, so any role that can connect can create objects;
PostgreSQL 15 removed that default. `CREATE` was revoked from `PUBLIC` and
granted back to the application role only.

Redis 6.0 here has no ACL users, so the exporter authenticates with the same
`requirepass` value the application uses. Redis offers no per-source
authorisation and no read-only role short of ACLs, so there is no least-privilege
credential to grant. An ACL user limited to `+info` and `+client|list` is a
worthwhile follow-up.

Both exporters are collected by annotation discovery rather than a dedicated
scrape job, and `validate-observability.sh` asserts the annotation is present —
a Service that loses it keeps serving metrics nobody reads.

## What is still missing after this phase

| Gap | Arrives in |
|---|---|
| Application metrics (`/metrics` returns 404 today) | Phase 6 |
| kube-scheduler, kube-controller-manager, kube-proxy | Phase 4, needs a k3s flag change and an ADR |
| Logs | Phase 5 |
| Traces | Phase 7 |
| Alerting | Phase 9 |

PostgreSQL and Redis run on the host rather than in the cluster. Phase 1 made
them reachable from the pod network, which means their exporters can now run as
ordinary in-cluster Deployments instead of as systemd units on the host. That is
a change from the original Sprint 5.1 plan and removes host configuration drift
from the design.
