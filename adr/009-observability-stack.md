# ADR 009: Prometheus, Grafana, Loki, and Alertmanager

## Status

Accepted

## Date

2026-08-01

## Context

The platform needs metrics, logs, dashboards, and alerting on one 8GB node whose memory
limits are already committed at roughly 150% of allocatable, with one shared disk holding
the k3s datastore, PostgreSQL, and every volume.

The dominant risk is not choosing the wrong tool. It is that a monitoring stack fails in a
way ordinary validation does not catch: a scrape job whose relabel rules match nothing
renders correctly, validates correctly, deploys correctly, and collects nothing — and the
result is indistinguishable from a healthy system with no problems to report.

So the requirements were: fit the node, and be verifiable before merge.

[ADR 004](004-log-collection-agent.md) covers the log *agent*. [ADR 011](011-distributed-tracing.md)
covers tracing. This ADR covers the storage, query, and alerting layer.

## Decision

Prometheus (chart 29.20.1, server v3.13.2) for metrics, with Alertmanager for alerting,
Grafana (chart 10.5.15, 12.3.1) for dashboards, and Loki (chart 7.2.0, 3.6.11) for logs.

Sized for the node, deliberately:

| Component | Configuration |
|---|---|
| Prometheus | 7 days **and** 2GB retention, 3Gi volume |
| Loki | single binary, filesystem store, 120h retention with the compactor on, 2Gi volume |
| Grafana | dashboards and datasources provisioned from files, 512Mi volume |
| Alertmanager | 14 rules, 256Mi volume, one receiver with no destination |

Loki runs with caches, gateway, canary, MinIO, and self-monitoring **all disabled**, and a
gate asserts they stay disabled.

## Alternatives Considered

**kube-prometheus-stack.** The default recommendation, and the strongest alternative. It
bundles Prometheus Operator, Grafana, Alertmanager, node-exporter, and kube-state-metrics
with ~30 dashboards and ~100 alert rules already written. Rejected for two reasons. Its
default resource requests do not fit alongside PostgreSQL, Redis, and Loki on 8GB without
substantial trimming — at which point the bundle's advantage is gone. More importantly, its
alert rules would be inherited rather than authored: 100 rules nobody on this platform can
explain, most of them for multi-node conditions that cannot occur here, and none of them
carrying a runbook that exists. Fourteen rules whose expressions were each evaluated against
live data is better evidence of engineering than 100 that arrived in a chart.

**Prometheus Operator with hand-written CRDs.** `ServiceMonitor` and `PrometheusRule` are
genuinely nicer than annotation-based discovery, and scoped per namespace. Rejected because
the Operator adds CRDs and a controller to manage a single Prometheus instance, and because
the annotation-based path made a real failure mode *visible*: the backend's scrape annotation
named the Service port instead of the container port, and fixing that taught more about
endpoints-role discovery than a `ServiceMonitor` would have. `serviceMonitor: false` is set
explicitly on the charts that offer it.

**Grafana Alloy for metrics as well as logs.** Alloy can scrape and remote-write, which would
mean one agent for both pillars. Rejected because Prometheus is still needed as the store and
the rule evaluator, so Alloy would sit in front of it without removing it — an extra hop, not
a saved component.

**Loki in scalable mode (read/write/backend).** The chart's default. Rejected on arithmetic:
its two memcached caches alone request more memory than the node has free, plus a gateway, a
canary, and a MinIO instance. Single binary with a filesystem store is the correct shape for
one node, and `validate-observability.sh` fails if a chart upgrade quietly reintroduces any of
the disabled parts.

**Elasticsearch or OpenSearch for logs.** Far better full-text search. Rejected on footprint —
a JVM heap plus indices on the same disk as PostgreSQL — and because Loki's label-based model
shares Grafana's query surface, so one datasource idiom covers both pillars.

**A hosted backend (Grafana Cloud, Datadog).** Removes all resource pressure and adds an
external dependency, a cost, and the loss of exactly the operational work this project is
meant to demonstrate.

**No alerting, dashboards only.** Rejected. A dashboard is only read by someone who already
suspects a problem.

## Consequences

**Easier.** The whole stack fits with headroom to spare. Dashboards and datasources are files
in Git, so they are reviewable and survive volume loss — nothing is created through the
Grafana UI. Fourteen alerts, each with a runbook the gate proves exists.

**Harder, and accepted.**

*Retention is short.* Seven days of metrics and five days of logs. Enough to investigate an
incident, not enough for capacity trends over months. Bounded by both time and size, because
on a shared disk time alone bounds nothing.

*Annotation-based discovery is coarse.* Any pod with `prometheus.io/scrape` is collected,
which is how Traefik ended up scraped twice — once by its dedicated job and once by the
chart's default `kubernetes-pods` job, because the Traefik pod carries its own annotations.
Seven duplicate series, and the edge alerts pin `job="traefik"` rather than relying on ratios
cancelling out.

*Notification routing is absent.* Alertmanager has one receiver with no destination, because
delivering to Slack or PagerDuty needs a credential this repository does not hold and a
decision about who is on call. Alerts still evaluate and are queryable as `ALERTS{}`;
[docs/observability/alerts.md](../docs/observability/alerts.md) gives the exact change.

*Observability can fill its own disk and stop reporting that it has.* Hence
`ObservabilityVolumeFilling`, the fourteenth rule and the one not in the original scope.

*Two silent configuration traps were hit.* Loki's `storageClass` versus `storageClassName`
silently provisioned from the default. Grafana's `initChownData` needs root and crash-looped
against a non-root pod security context — disabling it is the more secure fix, since `fsGroup`
already sets group ownership at mount time and no container in that pod now runs as root.

## Validation

```sh
bash scripts/validate-observability.sh --gitops-dir ../NovaShop-GitOps
```

25 checks, including `promtool check config`, `promtool check rules`, required scrape jobs
present by name, Traefik discovered by pod, Loki free of caches and gateway with compactor
retention on, every rendered kind permitted by the AppProject, every container bounded, and
every alert carrying a severity, a summary, and a runbook that resolves to a file.

On the cluster:

```sh
kubectl -n observability get pods,pvc
```

```promql
count(ALERTS)                    # queryable
up == 0                          # nothing down
```
