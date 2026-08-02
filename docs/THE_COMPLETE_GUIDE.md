# NovaShop — The Complete Guide

One document that explains the whole platform: what it is, why every piece was chosen, how the
pieces fit, and what went wrong along the way. If you read only one file in this repository,
read this one.

It assumes no prior knowledge of Kubernetes or GitOps. It does assume you can read a command
and are willing to open a file when it is named.

**Where this sits among the other documents.** [`docs/academy/`](academy/) teaches the same
material slowly, one subsystem per module, with labs and quizzes.
[`docs/interview/`](interview/) drills it as 107 questions. This file is the single continuous
narrative that ties both together — the map, not the walking tour.

> **A note on honesty.** This platform runs on one node, has no high availability, no frontend
> tests, alerts that route nowhere, and a recovery procedure that has never been run end to
> end. All of that is stated here and in [AUDIT.md](AUDIT.md). If a section reads as though
> something is more finished than it is, that is a defect in this document.

---

## Table of contents

1. [What NovaShop is, and what it is not](#1-what-novashop-is-and-what-it-is-not)
2. [The one idea behind everything](#2-the-one-idea-behind-everything)
3. [The physical platform](#3-the-physical-platform)
4. [The application](#4-the-application)
5. [Containers and images](#5-containers-and-images)
6. [Continuous integration and release](#6-continuous-integration-and-release)
7. [Kubernetes on one node](#7-kubernetes-on-one-node)
8. [Helm and Kustomize](#8-helm-and-kustomize)
9. [GitOps and Argo CD](#9-gitops-and-argo-cd)
10. [The edge: Traefik, DNS, TLS](#10-the-edge-traefik-dns-tls)
11. [Observability](#11-observability)
12. [Alerting and runbooks](#12-alerting-and-runbooks)
13. [The guardrails](#13-the-guardrails)
14. [Security](#14-security)
15. [Infrastructure as Code](#15-infrastructure-as-code)
16. [Backup, restore, recovery](#16-backup-restore-recovery)
17. [The complete tech stack](#17-the-complete-tech-stack)
18. [Every defect, and what it taught](#18-every-defect-and-what-it-taught)
19. [What is deliberately absent](#19-what-is-deliberately-absent)
20. [Glossary](#20-glossary)

---

## 1. What NovaShop is, and what it is not

NovaShop is a **platform engineering portfolio**. There is a small e-commerce application in
it — a FastAPI backend and a Next.js frontend — but the application is a payload, not the
point. What is being demonstrated is everything around it: how code becomes a running
service, how you know it is working, how it is protected, and how you get it back.

**What it is not:** a product, a reference architecture for a company, or a tutorial. It is
also not "production" in the sense a business would mean. It serves real traffic on one node
with no redundancy.

The live platform:

| | |
|---|---|
| Production | https://novashop.smartdev.vn |
| Staging · Development | https://staging.novashop.smartdev.vn · https://dev.novashop.smartdev.vn |
| Backend, own host | https://api.novashop.smartdev.vn |
| Node | `sd-tempo-mcp`, 10.10.1.45, Ubuntu 22.04.5 LTS, single node |

> The hostname contains "tempo" for historical reasons. Grafana Tempo is **not** deployed.

### Two repositories

| Repository | Contains |
|---|---|
| **NovaShop** (this one) | Application code, the Helm chart, platform component values, scripts, Terraform, all documentation |
| **NovaShop-GitOps** | 28 files: Argo CD Applications, per-environment values, phase composition |

Why two? Because they have different lifecycles. In one repository, every code change is
potentially a deployment and every deployment is a code change. Splitting them means the
decision *"this verified image should now go live"* is a separate, deliberate act — a second
merge, made by a human. That second merge is the control. [ADR 003](../adr/003-gitops-delivery.md).

The cost is real: two pull requests for one change. That cost is the feature.

---

## 2. The one idea behind everything

Almost every design decision in this repository defends against a single failure mode:

> **Something renders, validates, deploys, and does nothing — while every dashboard stays
> green.**

This is worse than a crash. A crash is loud. Silent failure looks exactly like health.

Concrete examples, all of which actually happened here:

- A scrape annotation named the Service port instead of the container port. Six backend
  replicas exported no metrics at all. Pods `Running`, probes passing, Service serving, users
  unaffected. The metric simply did not exist, which looks identical to "no traffic yet".
- A pin to a container image that was never published. The manifest was valid YAML, valid
  Kubernetes, and referenced a real-looking SHA. `ImagePullBackOff` on every replica.
- An alert rule referencing a metric that does not exist. It never fires and never errors. It
  reports safety it cannot observe.
- A recovery script that aborted before doing anything, because it grepped for
  `^DATABASE_URL=` in a file that declares `export DATABASE_URL=`.

Every guardrail in this repository exists because one of these happened. None was added in
anticipation. That is a stated policy: [ADR 001](../adr/001-platform-guardrails.md).

**The corollary, and the single most useful idea here:** a green dashboard is evidence that
nothing is *reporting* a problem. That is not the same as nothing being wrong.

---

## 3. The physical platform

One Ubuntu 22.04.5 machine at 10.10.1.45. Everything runs on it: k3s, all workloads,
PostgreSQL, Redis.

```
Internet
   ↓
Cloudflare (DNS, proxy)
   ↓
FortiGate (NAT: 80, 443 only)
   ↓
Node 10.10.1.45
   ├── Traefik (k3s bundled) → Ingress → pods
   ├── k3s + SQLite datastore
   ├── PostgreSQL 14   ← on the host, not in the cluster
   └── Redis           ← on the host, not in the cluster
```

**Why are the datastores on the host and not in Kubernetes?** Because on a single node,
running a database in a pod adds a failure mode (the pod, the PVC, the scheduler) without
adding any of the benefits that make it worthwhile at scale (rescheduling, replica
management). They are reached over the pod network at `10.10.1.45:5432` and `:6379`.

This has consequences the rest of the platform must handle:

- `pg_hba.conf` must permit the pod CIDR, and Redis must have `requirepass` set, because both
  are now reachable from anything in the cluster.
- NetworkPolicy must allow egress to the node IP.
- Backup is a host concern, not a Kubernetes one.

### The node scripts

[`scripts/linux/`](../scripts/linux/) — every one idempotent, so rerunning during an incident
changes nothing and restarts nothing.

| Script | Does |
|---|---|
| `bootstrap.sh` | Orchestrates everything below, in order |
| `configure-node-limits.sh` | Raises inotify limits, 128 → 512 |
| `configure-datastores.sh` | PostgreSQL and Redis for pod-network access |
| `install-k3s.sh`, `install-helm.sh`, `install-argocd.sh` | The cluster and its controller |
| `verify.sh` | Asserts the platform matches its declared state |
| `recover.sh` | Rebuilds after node loss |

**Idempotence via managed blocks.** Configuration files are edited by replacing a delimited
region, not by appending:

```
# BEGIN NovaShop managed block
…
# END NovaShop managed block
```

Appending is what makes a "run it again to be safe" script unsafe: the tenth run leaves ten
copies of a directive, and the last one wins in some parsers and the first in others.

**Credentials.** `/root/.novashop-platform.env`, owned by root, mode 600. `bootstrap.sh`
refuses to run if the file is group- or world-readable. It holds `DATABASE_URL` and
`REDIS_URL`, and both scripts derive their configuration from those URLs rather than from
separate variables — one source of truth, no chance of the app and the server disagreeing
about the password.

### The inotify story — why this is a correctness problem

Linux limits how many inotify instances a user can hold; the default is 128. Kubernetes uses
them heavily to watch files. When they run out, the failures are **not** "too many watchers"
errors — they are ConfigMap updates that never arrive, log tailing that stops, and controllers
that stop noticing changes. Nothing crashes. Things quietly stop reacting.

That is why raising the limit is treated as a correctness fix rather than performance tuning,
and why it happens in bootstrap before anything else is installed.

---

## 4. The application

Deliberately small. Its job is to be *observable* and *deployable*, not featureful.

### Backend — FastAPI (Python)

[`backend/app/`](../backend/app/). The interesting parts are not the endpoints.

**Three health endpoints, and why one is not enough:**

| Endpoint | Checks | Used by |
|---|---|---|
| `/health` | Nothing. Returns service identity | Legacy callers, dashboards |
| `/live` | Nothing but the event loop | Liveness probe |
| `/ready` | **PostgreSQL and Redis, every call** | Readiness probe |

The distinction matters enormously. **Liveness answers "should Kubernetes kill this
process?"** If liveness checked the database, a database blip would restart every replica —
turning a recoverable outage into a crash loop that makes the outage worse.

**Readiness answers "should traffic go here?"** That *should* fail when a dependency is down,
because a replica that cannot reach the database should be removed from the Service.

Read [`health.py`](../backend/app/api/routes/health.py). Note that `/ready` re-checks on every
call rather than caching, so a datastore that becomes unreachable is reflected within one probe
period, and returns **503** — not 200 with a sad message in the body, because a probe reads the
status code.

**Startup does not touch the network.** In [`main.py`](../backend/app/main.py), `lifespan`
creates connection handles without connecting. So an unreachable database cannot prevent
startup: the process comes up, reports itself live, and reports itself not ready. That is
exactly the correct behaviour during recovery, when the application may well start before the
database does.

**Metrics** — [`metrics.py`](../backend/app/observability/metrics.py), written by hand rather
than pulled from an instrumentation library, because the one decision that matters is a
labelling decision and it should be visible:

- Requests are labelled with the **matched route template**, never the raw path.
  `/api/products/42` and `/api/products/43` both become `/api/products/{product_id}`. A label
  built from the request path is unbounded — a crawler probing a few thousand URLs creates a
  few thousand time series that persist for the entire retention period. This is the classic
  way to kill a Prometheus.
- Unmatched requests collapse to a single `unmatched` bucket, for the same reason.
- A **dedicated registry**, not the default, so the exposition contains only what this service
  declares.
- The scrape path is excluded from its own middleware — otherwise the application measures
  Prometheus measuring the application.
- The `except` branch records a 500 **before re-raising**. Without it, unhandled exceptions
  become 500s for the client and vanish from the error rate: the metric would look healthiest
  exactly when the service is failing.

**Tracing** — [`tracing.py`](../backend/app/observability/tracing.py) exists and is inert.
`is_enabled()` returns false unless `OTEL_EXPORTER_OTLP_ENDPOINT` is set. Nothing sets it.
See §19.

### Frontend — Next.js

Minimal. Its main contribution to this repository is its Dockerfile (§5) and the fact that it
has **no tests**, which is stated plainly rather than hidden.

---

## 5. Containers and images

Both images are multi-stage: a build stage with the toolchain, a runtime stage with only what
runs.

**Non-root, by numeric UID.** The runtime stage sets `USER 1001`, not `USER appuser`.
Kubernetes' `runAsNonRoot` check happens before the container starts and can only evaluate a
numeric UID — a username requires reading `/etc/passwd` inside an image that has not started.
A named user therefore fails the check even when it is correct.

**The frontend deletes npm from its runtime image:**

```dockerfile
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx
```

Not tidiness. Trivy reported CVEs in npm's *vendored dependencies* — code shipped inside the
npm package that the running application never invokes. The application does not need a
package manager at runtime, so removing it removes the finding and a real capability an
attacker would want.

The trade-off is recorded: this couples the Dockerfile to Node's installation layout. A base
image that moves npm silently breaks the deletion — which is why the paths are explicit and
commented rather than globbed.

**Runtime security context**, applied in the Helm chart:

- `runAsNonRoot: true`, numeric UID
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- `capabilities: drop: [ALL]`

These are not decoration — the `novashop-*` namespaces enforce Pod Security Admission
`restricted`, which **rejects** a pod that does not comply. It has been tested by applying a
non-compliant pod and watching the API server refuse it.

---

## 6. Continuous integration and release

Three workflows in [`.github/workflows/`](../.github/workflows/):

| Workflow | Trigger | Purpose |
|---|---|---|
| `validation.yml` | `workflow_call` only | **The single definition of every check** |
| `ci.yml` | Pull requests, feature branches | Calls validation |
| `release.yml` | Push to `main` | Calls validation, **then** publishes |

### Why release cannot race CI

This is the structural idea worth understanding.

A common design has CI on pull requests and a separate release workflow on merge. Those are
two workflow runs observing each other, and "wait for the other one to be green" is a race
condition dressed as a policy.

Here, `release.yml` **calls** `validation.yml` as a job dependency. They are nodes in one job
graph. Publishing cannot begin before validation completes because the graph does not allow
it. There is no polling, no `wait-for-check` action, no race.

### Why an unscanned image cannot reach the registry

Also structural. In `release.yml`, the build **loads the image locally**, Trivy scans it, and
only *then* does the workflow acquire registry credentials via `docker/login-action`.

The job literally cannot push before it has scanned, because before the scan it does not
possess the ability to push. Compare this with "scan, and fail the job if findings" — that
relies on a conditional being correct. This relies on capability ordering.

`GITHUB_TOKEN` is scoped to the repository and expires with the job. **There is no long-lived
registry credential anywhere in this project.**

### Other details worth noticing

- Actions are pinned to commit SHAs, not tags. A tag can be moved.
- The Argo CD install manifest is verified against a pinned **SHA-256** before it is applied.
- `fail-fast: false` on the image matrix: if the backend fails, you still learn whether the
  frontend would have. Otherwise a fix reveals a second failure and each round trip costs a
  full CI cycle.
- Images are tagged by commit SHA. `latest` is moved in a separate job that requires **every**
  component to have published, so it can never point at a half-released build.

---

## 7. Kubernetes on one node

k3s v1.33.13+k3s1. A full, conformant Kubernetes distribution in one binary.

**Why k3s rather than kubeadm or a managed cluster?** [ADR 002](../adr/002-kubernetes-distribution.md).
One node, no cloud account. k3s bundles Traefik, a local-path storage provisioner, and CoreDNS,
and it replaces etcd with SQLite.

That last point has consequences you must know:

- **The datastore is a SQLite file.** You cannot back it up by copying it — a copy of a live
  SQLite file is very likely corrupt. Use the online backup API: `sqlite3 .backup`.
- **`k3s etcd-snapshot` does not work.** It is etcd-only. On a SQLite-backed k3s it does not
  produce a datastore snapshot. Documents that say "take a k3s snapshot" are wrong here.
- No etcd means no etcd tuning, no etcd metrics, and no multi-master.

**Storage.** `local-path` is the only StorageClass. A PersistentVolume is a directory on this
node. There is no replication and no migration — if the node is gone, the volume is gone. This
is why backup tiering (§16) matters more than it would on a cloud cluster.

**Pod Security Admission.** `restricted` is enforced in the `novashop-*` namespaces and
genuinely rejects non-compliant pods. The `observability` namespace runs `privileged`, because
the node exporter needs host access to report on the host. That exception is namespace-scoped
and documented rather than a blanket relaxation.

---

## 8. Helm and Kustomize

Both, for different jobs — [ADR 006](../adr/006-helm-and-kustomize.md).

**Helm** packages the application: [`helm/novashop/`](../helm/novashop/), templates for
Deployments, Services, Ingress, ConfigMap, Namespace, and NetworkPolicies. One chart, three
environments, differing only in values.

**Kustomize** composes the GitOps layer: which Applications exist in which phase. Composition
of existing YAML is what Kustomize is good at, and templating a chart is what Helm is good at.
Using either for the other's job is where people get into trouble.

Worth reading in the chart:

- [`backend-service.yaml`](../helm/novashop/templates/backend-service.yaml) — five lines of
  comment above one value, explaining the scrape-port defect (§11).
- [`networkpolicy.yaml`](../helm/novashop/templates/networkpolicy.yaml) — four policies (§14).
- `secrets.existingSecret` is `required`. The chart refuses to render without it, so a missing
  Secret is a template error at build time rather than a `CreateContainerConfigError` at 3am.

---

## 9. GitOps and Argo CD

The heart of the platform. Argo CD v3.4.4.

**GitOps** means a controller inside the cluster continuously reconciles live state toward a
declared state in Git. Two properties follow, and both matter:

1. Desired state exists **outside** the cluster and can be replayed onto a new one.
2. CI never needs cluster credentials. Nothing outside the cluster can write to it.

### App-of-apps

One Application, `novashop-root`, whose job is to create other Applications. Everything
descends from it. Twelve Applications in total, all Synced and Healthy.

### Sync waves

Resources are ordered within a sync, most negative first:

| Wave | What |
|---|---|
| −30 | AppProject |
| −20 | cert-manager |
| −15 | **Prometheus** |
| −14 … −12 | Grafana, Loki, Alloy, exporters |
| 0 | Certificates |
| 10 | Applications |

Prometheus at −15 is deliberate: it comes up ahead of what it observes, so a target appearing
during a rollout is collected from its first moment rather than after things settle.

### Everything is pinned to a commit SHA

Every reference from desired state to source is a 40-character hex SHA. Not a branch, not a
tag. Two references deliberately track `main`: the root Application, and the ApplicationSet's
reference to its own repository. Pinning the root would mean **no GitOps change could ever
take effect** without editing the cluster by hand.

### `managedNamespaceMetadata` — the invisible ownership trap

The ApplicationSet reapplies namespace labels on every sync:

```yaml
managedNamespaceMetadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
```

`kubectl get namespace novashop-production -o yaml` shows **no Argo CD tracking annotation**.
The namespace looks unmanaged and is not. Anything else that declares those labels — Terraform,
for example — produces permanent drift, with the usual evidence of ownership entirely absent.
This is why [ADR 013](../adr/013-terraform-kubernetes-boundary.md) exists.

### The AppProject whitelist

`namespaceResourceWhitelist` lists the kinds Argo CD may create. A kind not on it is refused
**at sync time** — after the manifest has rendered, validated, and merged. Loki's StatefulSet
did exactly that. The lesson: a manifest passing every CI gate is *not* guaranteed to be
applied. That failure was subsequently moved earlier, into a pre-merge check.

### The expensive lesson: `ServerSideApply` diffs

An Application read `OutOfSync` while its last sync reported `Succeeded`. The obvious
diagnostic:

```sh
helm template … | kubectl diff -f -
```

reported **zero differences**.

Here is why. With `ServerSideApply`, sync status compares `predictedLiveState` — the result of
a server-side apply **dry run** — against `normalizedLiveState`. It does **not** compare the
rendered manifest against the live object. The real difference was `apiVersion` and `kind` that
Kubernetes adds inside a StatefulSet's `volumeClaimTemplate`, which the dry run does not
reproduce.

Diagnosing it properly means asking the API for both states:

```
GET /api/v1/applications/<app>/managed-resources
```

and comparing `predictedLiveState` against `normalizedLiveState`. On this platform, **41 of 42
differing fields were noise** — server defaults Argo CD already ignores.

This cost two consecutive wrong fixes, both shipped and both reverted.

### The second trap: `selfHeal` invalidates live experiments

`novashop-root` has `selfHeal: true`. If you `kubectl patch` something to test a hypothesis,
the patch is reverted — usually **before** Argo CD recomputes the comparison. You read the
status, see no change, and conclude your fix does not work.

A working fix was discarded on exactly that evidence. Re-run with self-heal paused, it reached
Synced immediately.

**The general lesson, and it applies far beyond Argo CD: an inconclusive experiment is not a
negative result.**

---

## 10. The edge: Traefik, DNS, TLS

**Traefik 3.7.4**, bundled with k3s. Host-based routing: four `Host` rules. Gateway API was
considered and rejected — [ADR 007](../adr/007-ingress-controller.md) — because four host rules
are satisfied by Ingress and Gateway API would add CRDs for capability nothing here uses.

**DNS.** Cloudflare holds the zone; A records point at the public address; FortiGate NATs 80
and 443 to the node.

**TLS.** cert-manager v1.21.0, Let's Encrypt production, HTTP-01 challenge.

### The phased edge — a genuine ordering problem

A cluster with no certificate cannot serve HTTPS. cert-manager cannot obtain a certificate for
a host that is not already reachable over HTTP. Both cannot be first.

Three phases resolve it:

| Phase | Directory | State |
|---|---|---|
| `http` | `kubernetes/ingress/http/` | Serving on port 80, no TLS |
| `tls-baseline` | `kubernetes/ingress/baseline/` | TLS available, HTTP still accepted |
| `tls-enforced` | `kubernetes/ingress/examples/` | Redirect and HSTS |

`verify.sh` **detects** the live phase from cluster state rather than being told which phase it
is in — because a script that can be told can be told the wrong thing.

### The rate limit that shapes recovery

Let's Encrypt permits **five duplicate certificates per registered domain per 168 hours**. That
is a hard weekly ceiling and it drives a recovery decision: certificate material is restored
from backup **before** Argo CD reconciles, because otherwise cert-manager immediately requests
new certificates and spends one of your five.

### HSTS is a one-way door

`Strict-Transport-Security` instructs browsers to refuse HTTP for that host for the max-age
duration. Once sent, you cannot take it back for clients that already received it. Rolling back
to HTTP does not work — the browser will not make the request. This is why HSTS is the last
phase, applied only when there is something valid to enforce.

---

## 11. Observability

**Prometheus** (metrics) · **Loki** (logs) · **Grafana** (viewing) · **Alertmanager** (alerts) ·
**Alloy** (log collection). [ADR 009](../adr/009-observability-stack.md).

`kube-prometheus-stack` was rejected: it brings the Prometheus Operator and a large CRD
surface, and this platform's scrape configuration is six jobs. Operator CRDs are worth it when
teams need self-service ServiceMonitors; here it would be a second configuration mechanism for
no capability gained.

**31 scrape targets, all up.**

### Service discovery — the concept behind the worst defect here

Prometheus **pulls**. It builds a target list from service discovery, applies `relabel_configs`
to each candidate, and scrapes what survives.

| Role | One target per | Address dialled |
|---|---|---|
| `endpoints` | Address in an Endpoints object | **Pod IP** |
| `pod` | Pod | **Pod IP**, declared container port |
| `service` | Service | Service DNS name |

Read the first row carefully. `role: endpoints` is *derived from* a Service but does **not
dial the Service** — it dials the pods behind it.

**The scrape-port defect.** The backend Service was annotated:

```yaml
prometheus.io/port: {{ .Values.backend.service.port }}   # 80 — WRONG
```

The Service listens on 80 and forwards to 8000. The pod only ever listens on 8000. Prometheus
dialled `10.42.x.y:80` and got connection refused — on all six production replicas. Nothing was
unhealthy. `novashop_http_requests_total` simply did not exist, which looks exactly like "no
requests yet".

The fix is one word: `targetPort`. The comment explaining it is five lines long, deliberately.

**The same failure from the other direction.** Traefik publishes metrics on the **pod only** —
its Service exposes `web` and `websecure` and nothing else. An endpoints-based job would match
nothing and silently collect zero series. The job therefore uses `role: pod`, and a pre-merge
check now fails any pull request that changes it.

### Targets that are down by design are removed, not tolerated

Argo CD's Dex declares ports 5556, 5557 and 5558 and listens on none of them while no SSO
connector is configured. Verified on the cluster; all three refuse connections. It is dropped
by a relabel rule. The pushgateway job, which the chart defines whether or not the subchart is
installed, is disabled for the same reason.

The reasoning is not tidiness:

> A target list that is always partly red trains operators to stop reading it.

And the target list is the *only* place the scrape-port defect was visible.

### Logs

**Loki 3.6.11**, single-binary mode. **Alloy** collects.

Alloy replaced Promtail for two reasons: Promtail is end-of-life, and Alloy reads container
logs through the Kubernetes API rather than by tailing files on disk — which means it does not
depend on the container runtime's log layout. [ADR 004](../adr/004-log-collection-agent.md).

Retention is **both** 7 days and 2 GB, whichever comes first. Time-only retention on a
fixed-size local volume is a promise the disk cannot keep.

---

## 12. Alerting and runbooks

**14 alert rules in 7 groups. 14 runbooks. Every rule carries a `runbook_url`, and a pre-merge
check fails the build if any of those URLs points at a file that does not exist.**

An alert that fires at 03:00 with no stated response is a page, not a signal.

Every expression was evaluated against **live data** before merge. An alert built on a metric
that does not exist never fires and never errors — the worst possible failure for an alert,
because it reports safety it cannot observe.

Configuration worth understanding:

| Setting | Value | Why |
|---|---|---|
| `group_by` | `[alertname, namespace]` | One notification for a fault hitting three replicas, not three |
| `repeat_interval` | 12h | Anything shorter trains people to mute the channel, which is worse than not alerting |
| `NodeDown` inhibition | Suppresses dependents | If the node is down, everything on it is down. One cause, one alert |
| `CertificateExpiring` | 21 days | Not 7. Leaves room for the Let's Encrypt weekly limit plus a working week |

**Alerts route nowhere.** They evaluate and are queryable; no receiver delivers them. That
needs a credential this repository does not hold and an on-call decision that does not exist.
Stated rather than disguised.

---

## 13. The guardrails

93 automated checks across three scripts. All run **without a cluster and without
credentials** — you can run them right now on a clean clone.

```sh
bash scripts/validate-platform.sh          --gitops-dir ../NovaShop-GitOps   # 38 checks
bash scripts/validate-gitops-revisions.sh  --gitops-dir ../NovaShop-GitOps   # 30 checks
bash scripts/validate-observability.sh     --gitops-dir ../NovaShop-GitOps   # 25 checks
```

### `validate-platform.sh`

Renders every chart and schema-checks the result with `kubeconform`. Also asserts **toolchain
alignment**: Python and Node major versions must match across the Dockerfiles, the workflow
environment, `engines.node`, `@types/node`, and `requires-python`. Those drift silently and the
symptom appears far from the cause.

### `validate-gitops-revisions.sh` — the one that is genuinely unusual

For every reference from desired state to this repository it asserts:

- the revision is a 40-character hex SHA — not a branch, not a tag;
- that SHA is an **ancestor of `origin/main`**, so a force-push cannot orphan it;
- backend and frontend image tags in one environment come from the **same** commit;
- no tag is `latest`;
- **both images exist in GHCR**, checked with an anonymous registry token.

That last check is the one to remember. A pin to a commit whose release failed renders
perfectly, validates perfectly, and produces `ImagePullBackOff`. Only a registry query catches
it. No schema validator can.

### `validate-observability.sh`

Renders the observability charts and inspects the resulting Prometheus configuration:
`promtool check config`, every required job present by name, Traefik's discovery role asserted
explicitly, every alert's runbook resolved to a real file, every component bounded by resource
requests and limits.

### The gates are negative-tested

A check that cannot fail is worse than no check, because it produces confidence. Every gate was
deliberately broken to confirm it catches what it claims.

This found a real bug **in a gate itself**: the runbook check returned `"<count>\n<problems>"`
on stdout, and because `$(...)` strips trailing newlines, a clean repository produced a count
that was read as the problem list. It passed on a clean repo for the wrong reason. Fixed by
sending the count to stderr and the verdict to the exit status.

---

## 14. Security

The theme is **proven, not assumed**.

### Pod Security Admission

`restricted` enforced in `novashop-*`. Tested by applying a non-compliant pod and confirming
the API server rejects it. `observability` runs `privileged` because the node exporter needs
host access — namespace-scoped and documented.

### NetworkPolicy

Four policies, all with `podSelector: {}` so they apply to every pod in the namespace:

| Policy | Effect |
|---|---|
| `default-deny-ingress` | Nothing may connect in |
| `allow-edge-and-probes` | Traefik from `kube-system`, **and the node network** |
| `allow-metrics-scrape` | Prometheus to the metrics port |
| `allow-same-namespace` | Frontend to backend |

**Why the node network is admitted.** Kubelet probes originate from the node itself, not from a
pod. A policy that admits only `kube-system` blocks every liveness and readiness probe — the
pods then fail their probes and are killed. Getting this wrong turns a security control into an
outage.

**Egress is deliberately unrestricted.** Restricting egress on a platform whose datastores live
on the host and whose cert-manager must reach Let's Encrypt would break things in ways that are
hard to attribute. It is a stated gap, not an oversight.

**How enforcement was proven.** kube-router programs the rules, and there is a propagation
delay of seconds. The first test run reported same-namespace traffic BLOCKED — which was
wrong; the rules simply were not programmed yet. Everything was re-run with a 20-second settle
**and a no-policy control group**, because the cross-namespace BLOCKED result from the same run
was equally suspect. Without a control group you cannot distinguish "the policy works" from
"the test is broken".

### Secrets

Never in Git. [ADR 010](../adr/010-secret-management.md). Two Secrets are created by hand and
are deliberately outside GitOps:

- `novashop-secrets` — `DATABASE_URL`, `REDIS_URL`
- `novashop-grafana-admin`, `novashop-datastore-exporter`

External secret managers were considered and rejected: every option moves the bootstrap problem
(now you need a credential to reach the credential store) rather than removing it.

### Supply chain

Images tagged by SHA. Actions pinned by SHA. Argo CD's install manifest verified against a
pinned SHA-256. Trivy runs before credentials exist. Secret scanning and push protection are on.

### Least privilege — a subtlety worth knowing

The metrics exporter was given `pg_monitor`, which sounds read-only. On **PostgreSQL 14** it is
not sufficient in the way you would assume: PG14 grants `CREATE` on the `public` schema to
`PUBLIC`, so any role can create objects there. PostgreSQL 15 removed that default. The grant
had to be revoked explicitly.

The general lesson: a role named for an intent is not a guarantee of that intent. Verify what
it can actually do on the version you are running.

### Known gap

`/metrics` on the backend host is publicly reachable. Low severity, real, and documented with a
remedy in [security/hardening.md](security/hardening.md). It is a recorded decision, not an
oversight — the fix spans two repositories and an AppProject whitelist change.

---

## 15. Infrastructure as Code

Terraform, with **no cloud provider**. [ADR 012](../adr/012-terraform-scope.md).

There is no AWS account. Terraform here manages what exists: a GitHub organisation, a DNS zone,
an Ubuntu node, the datastores on it, and the Argo CD seed.

### The ownership boundary — the rule that decides whether it works

```
Terraform  →  the node, datastores, k3s, GitHub, DNS, and the Argo CD seed
Argo CD    →  everything inside the cluster, once the seed exists
```

**Terraform must never manage an object Argo CD reconciles.** Every Application has
`selfHeal: true`, so a Terraform-managed Deployment would be reverted within about three
minutes, `terraform plan` would never converge, and neither tool would be the source of truth.

This is a functional constraint, not a style preference.

### Seven layers, each a separate root module

`0-node` · `1-datastores` · `2-k3s` · `3-github` · `4-dns` · `5-cluster` · `6-gitops`

Separate rather than workspaces because they differ in **lifecycle** and in **who may run
them**. Workspaces share one backend configuration and encourage `count`-by-environment, which
is not the axis this platform varies on.

**Current status, honestly:** only `5-cluster` and `6-gitops` declare resources. The other five
are foundation — providers, pins, variables, outputs, validation — and manage nothing. The
node, datastores, k3s, GitHub and DNS are configured by scripts and by hand.

### Import, never create

Everything Terraform would manage already exists. So each layer lands with `import` blocks and
an acceptance gate of a **completely empty plan**. If the plan is not empty, the model does not
match reality and the model is wrong.

`5-cluster` **asserts far more than it owns** — two resources against eleven assertions.
Checking what Argo CD actually reconciles, rather than assuming, is what revealed the
`managedNamespaceMetadata` trap in §9.

### Practical Terraform lessons from this project

- **`-backend-config` cannot change the backend *type*.** `backend "pg" {}` cannot be
  initialised as local by passing a path. You need an override file — hence
  `backend-local-override.tf.example`.
- **`kubernetes_manifest` does not support import**, which is why the root Application is
  handled with `terraform_data` and content-hash triggers instead.
- **Importing a namespace fails if you omit an annotation it carries.** The `argocd` namespace
  has `argocd.argoproj.io/sync-wave: "-2"`; omitting it plans its removal. And
  `kubernetes.io/metadata.name` is not returned on read, so declaring it creates permanent
  drift. The import gate caught both.
- **HCL rejects `\.` in a regex string** — you need `\\.`.

---

## 16. Backup, restore, recovery

### What is backed up, and why the sizes matter

| Tier | Contents | Size |
|---|---|---|
| Datastores | PostgreSQL dump, k3s SQLite | ~21 KB compressed |
| Node state | Configuration, certificates, env file | Small |
| Volumes | Prometheus, Loki, Grafana data | ~550 MB |

Observability volumes are **not** backed up off-node. They are historical telemetry: losing
them loses history, not capability, and 550 MB per cycle to preserve metrics about a platform
that no longer exists is a poor trade. That is a decision, and it is written down.

### Never copy a live SQLite file

`cp` of an active SQLite database is very likely corrupt. Use the online backup API:

```sh
sqlite3 /var/lib/rancher/k3s/server/db/state.db ".backup /path/out.db"
```

then `PRAGMA integrity_check` on the result. And again: **`k3s etcd-snapshot` does not work
here** — it is etcd-only.

### Verification is by content, not by existence

`verify-backup.sh` runs seven checks, including a **SHA-256 per artefact** recorded in a
manifest. A backup that exists is not a backup that is correct. A restore was validated by
round-tripping 137 rows and comparing a content checksum, not a row count.

### Recovery order, and why it is that order

1. Node preparation
2. Datastores
3. **Certificate material** ← before Argo CD
4. k3s
5. Argo CD seed
6. Everything else reconciles from Git

Step 3 exists because of the Let's Encrypt weekly limit (§10). If Argo CD reconciles first,
cert-manager immediately requests new certificates.

### The defect that made the whole thing worthless

`recover.sh` could not run at all. It checked for required variables with:

```sh
grep '^DATABASE_URL=' "${PLATFORM_ENV_FILE}"
```

The file declares `export DATABASE_URL=`. The pattern never matched, so the script aborted
during preconditions — on a perfectly healthy platform, with a perfectly valid environment
file.

Two things about this are worth more than the fix:

1. **The same bug had already been found and fixed in `configure-datastores.sh`.** Fixing a bug
   in one place is not fixing the bug.
2. It was found by *running* the script, not by reading it. A recovery procedure that has been
   reviewed but not exercised is a document, not a capability.

### The honest limit

**Full recovery has never been run on a replacement node.** Every component is tested —
preconditions pass, a database restore round-trips with an identical checksum, a deleted Service
is reconciled in 5 seconds — but the sequence has not been executed end to end.

**RTO is an estimate of 30–45 minutes and should be treated as unknown.** RPO depends on backup
frequency, and off-node backup is manual.

This appears on the README, in the release notes, and in the audit. It is the single largest
gap in the platform.

---

## 17. The complete tech stack

| Layer | Technology | Version | Why | ADR |
|---|---|---|---|---|
| OS | Ubuntu Server LTS | 22.04.5 | Long support, familiar | — |
| Kubernetes | k3s | v1.33.13+k3s1 | One binary, one node, SQLite | [002](../adr/002-kubernetes-distribution.md) |
| Datastore (cluster) | SQLite | k3s built-in | No etcd on one node | [002](../adr/002-kubernetes-distribution.md) |
| Storage | local-path | k3s built-in | Only option on one node | — |
| Ingress | Traefik | 3.7.4 | Bundled; four host rules | [007](../adr/007-ingress-controller.md) |
| Certificates | cert-manager | v1.21.0 | Let's Encrypt, HTTP-01 | — |
| GitOps | Argo CD | v3.4.4 | UI, app-of-apps, ApplicationSet | [005](../adr/005-gitops-controller.md) |
| Packaging | Helm | 3.x | Templating the application | [006](../adr/006-helm-and-kustomize.md) |
| Composition | Kustomize | via kubectl | Composing Applications | [006](../adr/006-helm-and-kustomize.md) |
| Metrics | Prometheus | v3.13.2 | Pull model, PromQL | [009](../adr/009-observability-stack.md) |
| Alerts | Alertmanager | chart 29.20.1 | Grouping, inhibition | [009](../adr/009-observability-stack.md) |
| Logs | Loki | 3.6.11 | Label-indexed, cheap | [009](../adr/009-observability-stack.md) |
| Log agent | Grafana Alloy | v1.18.0 | Promtail is EOL; reads via API | [004](../adr/004-log-collection-agent.md) |
| Dashboards | Grafana | 12.3.1 | Provisioned from Git | [009](../adr/009-observability-stack.md) |
| Database | PostgreSQL | 14 | On the host | — |
| Cache | Redis | On the host | — | — |
| Backend | FastAPI, Python 3.12 | — | Async, typed | — |
| Frontend | Next.js, Node 22 | — | — | — |
| CI/CD | GitHub Actions | — | Reusable workflow | [008](../adr/008-ci-platform.md) |
| Registry | GHCR | — | No extra credential | — |
| Scanning | Trivy | — | Before credentials exist | — |
| IaC | Terraform | 1.9.8 | Seven layers, no cloud | [012](../adr/012-terraform-scope.md) |
| State | Terraform `pg` backend | — | PostgreSQL already exists | — |
| DNS | Cloudflare | — | Zone + proxy | — |
| Firewall | FortiGate + UFW | — | 80/443 only | — |
| Tracing | OpenTelemetry SDK | **installed, disabled** | Nothing worth tracing | [011](../adr/011-distributed-tracing.md) |

---

## 18. Every defect, and what it taught

The full log is [LEARNING_LOG.md](LEARNING_LOG.md). These are the ones that changed how the
platform is built.

| Defect | Lesson |
|---|---|
| Scrape annotation named the Service port | Endpoints-role discovery dials the **pod**. Silent metric loss looks like idleness |
| `route_template` iterated `app.routes` before routing | FastAPI wraps included routers; every request was labelled `unmatched`. A broken *dimension* is easy to read past |
| Argo CD OutOfSync with `helm template` showing no diff | `ServerSideApply` compares `predictedLiveState` to `normalizedLiveState`. **Two wrong fixes shipped** |
| `kubectl patch` reverted by `selfHeal` before recomputation | An inconclusive experiment is not a negative result |
| Loki StatefulSet refused after merge | The AppProject whitelist enforces at **sync time**. Move runtime refusals earlier |
| `recover.sh` grepped `^DATABASE_URL=` on `export DATABASE_URL=` | Same bug already fixed elsewhere. Fixing it in one place is not fixing it |
| My own runbook gate passed on a clean repo for the wrong reason | `$(...)` strips trailing newlines. Negative-test every gate |
| NetworkPolicy test reported BLOCKED before rules propagated | Use a control group. Without one you cannot tell a working policy from a broken test |
| `pg_monitor` was not read-only on PG14 | A role named for an intent is not a guarantee of it |
| inotify exhaustion | Silent non-reaction, not an error. A correctness problem |
| PR #51 merged into its stacked base | A stacked PR merges into its stated base. 1,091 lines orphaned, CI green throughout |
| `git tag -F` stripped every `#` line | Release notes lost all headings, including *Known limitations*. Use `--cleanup=verbatim` |
| Two documents claimed a backup captured the SQLite datastore | It did not. A reader would have stopped looking. Documentation defects are defects |
| Ubuntu version wrong in five documents | Facts drift. Re-measure, do not copy forward |

---

## 19. What is deliberately absent

Saying no is part of the design. Each has a recorded reason.

| Not here | Why |
|---|---|
| **Distributed tracing (Tempo)** | The backend has no business endpoints. A trace would be `GET /ready` plus two dependency calls. Instrumentation exists and is disabled — [ADR 011](../adr/011-distributed-tracing.md) |
| **High availability** | One node. Every document says so rather than implying redundancy |
| **Service mesh** | Nothing here exercises traffic management |
| **Kyverno / OPA** | Pod Security Admission and RBAC already cover what these would add |
| **External secret manager** | Every option moves the bootstrap problem rather than removing it — [ADR 010](../adr/010-secret-management.md) |
| **Gateway API** | Four `Host` rules are satisfied by Ingress — [ADR 007](../adr/007-ingress-controller.md) |
| **Argo CD Image Updater** | It would remove the second merge — and that merge is the human control point [ADR 003](../adr/003-gitops-delivery.md) exists to preserve |
| **HPA / PDB** | One node. Nothing to spread across, nothing to drain to |
| **Alert routing** | Needs a credential this repository does not hold and an on-call decision |
| **Frontend tests** | A genuine gap, not a decision. Stated in [AUDIT.md](AUDIT.md) |

The last row matters. The others are choices; that one is a shortfall, and mixing the two
categories is how a portfolio loses credibility.

---

## 20. Glossary

**ADR** — Architecture Decision Record. A short document stating a decision, its context, the
alternatives rejected, and the consequences accepted. Fifteen here.

**Alloy** — Grafana's log/telemetry collection agent. Replaced Promtail.

**AppProject** — An Argo CD boundary listing which repositories, destinations, and resource
kinds an Application may use. Enforced at sync time.

**ApplicationSet** — An Argo CD controller that generates Applications from a generator. Here,
a list generator produces one Application per environment.

**App-of-apps** — A pattern where one Argo CD Application's job is to create others.

**Cardinality** — The number of unique time series. Every distinct label-value combination is
one series. Unbounded labels kill Prometheus.

**Endpoints role** — Prometheus service discovery that derives targets from a Service's
Endpoints and dials **pod** addresses.

**GitOps** — A controller in the cluster continuously reconciles live state toward state
declared in Git.

**HSTS** — `Strict-Transport-Security`. Tells browsers to refuse HTTP for this host. Cannot be
recalled for clients that already received it.

**Idempotent** — Running it again changes nothing. The property that makes a script safe to run
during an incident.

**Inhibition** — An Alertmanager rule suppressing alerts implied by another. `NodeDown`
suppresses everything on the node.

**inotify** — The Linux file-watching mechanism. Exhausting it causes silent non-reaction.

**Liveness vs readiness** — Liveness: should this process be killed? Readiness: should traffic
go here? Never make liveness depend on a dependency.

**local-path** — k3s's storage provisioner. A PV is a directory on the node.

**managedNamespaceMetadata** — An Argo CD field that reapplies namespace labels every sync,
leaving no tracking annotation on the namespace.

**Pod Security Admission (PSA)** — Built-in Kubernetes admission enforcing `privileged`,
`baseline`, or `restricted` per namespace.

**PromQL** — Prometheus' query language.

**Relabelling** — Rules applied to discovered targets before scraping. `keep`, `drop`,
`target_label`.

**RTO / RPO** — Recovery Time Objective: how long to get back. Recovery Point Objective: how
much data you can lose. Here: RTO estimated 30–45 min (**unverified**); RPO depends on manual
backup frequency.

**Self-heal** — Argo CD reverting live drift automatically. Also a debugging trap.

**Server-side apply** — Kubernetes computing the merge server-side. Changes what "difference"
means for Argo CD's sync status.

**Sync wave** — An integer ordering resources within an Argo CD sync. Most negative first.

**Trivy** — Container image vulnerability scanner.

---

## Where to go next

| You want | Go to |
|---|---|
| To learn it properly, with labs | [docs/academy/](academy/) — 19 modules |
| To be asked hard questions | [docs/interview/questions.md](interview/questions.md) — 107 |
| The diagrams | [docs/architecture/](architecture/) — 13 views |
| The decisions | [adr/](../adr/) — 15, each with rejected alternatives |
| The honest scoring | [AUDIT.md](AUDIT.md) |
| The defects | [LEARNING_LOG.md](LEARNING_LOG.md) |
| To run it | [operations/local-development.md](operations/local-development.md) |
| To deploy it | [operations/production-deployment.md](operations/production-deployment.md) |
| To demo it | [PORTFOLIO_EVIDENCE.md](PORTFOLIO_EVIDENCE.md) · [EVIDENCE_CATALOG.md](EVIDENCE_CATALOG.md) |
