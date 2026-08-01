# Troubleshooting Guide

For when something is wrong and you do not yet know what. If an alert fired, go straight to
its [runbook](../observability/runbooks/) instead — this document is for the case with no
alert to start from.

## Start here

```sh
sudo k3s kubectl get applications -n argocd          # is Git being applied?
sudo k3s kubectl get pods -A | grep -v Running       # is anything unhealthy?
df -h / && free -h                                   # is the node out of something?
```

Three commands, and they separate the four classes of problem this platform has: delivery,
workload, node, and edge.

## Narrow by status code first

For anything user-facing, the HTTP status identifies the layer before you read a single log.
This is the fastest diagnostic in the repository.

| Symptom | Layer | Go to |
|---|---|---|
| Name does not resolve | Cloudflare DNS | [DNS](../architecture/dns.md) |
| Resolves, connection times out | FortiGate DNAT or UFW | [Networking](../architecture/networking.md) |
| Connects, TLS fails | cert-manager or Traefik | [TLS Flow](../architecture/tls-flow.md) |
| TLS fine, **404** | Traefik routing — `Host` or entrypoint | below |
| **502 / 503** | No ready endpoint | [IngressErrors](../observability/runbooks/ingress-errors.md) |
| **504** | Backend accepted and did not answer | [HighLatency](../observability/runbooks/high-latency.md) |
| **500** | Application fault | [ApplicationErrorRate](../observability/runbooks/application-error-rate.md) |

502 and 503 are the most commonly misread. They almost always mean Traefik has no healthy
endpoint — a readiness problem, not an application bug. Check
`kubectl -n novashop-production get endpoints` before reading application logs.

## Delivery problems

### An Application is OutOfSync but the sync says Succeeded

This is permanent drift, not slowness, and re-syncing will not help. Read
[ArgoSyncFailed](../observability/runbooks/argo-sync-failed.md).

The critical part: with `ServerSideApply`, sync status is decided by comparing a server-side
apply **dry-run** against the live object. `helm template | diff` — the natural instinct —
compares the rendered manifest against live, and it will report **zero differences** on an
Application that is permanently OutOfSync. Comparing the wrong pair of states caused two
consecutive wrong fixes on this platform.

### A resource is Missing and nothing errored

Check the `AppProject` whitelist. Argo CD refuses to create a kind the project does not
permit, and it does so **at sync time** — so the manifest rendered, validated, and merged
cleanly, and was refused afterwards.

```sh
sudo k3s kubectl get appproject novashop-platform -n argocd -o yaml | grep -A40 namespaceResourceWhitelist
```

`validate-observability.sh` now fails a pull request that renders a kind the project does not
allow, so this should be caught before merge.

### My kubectl change disappeared

It did. `selfHeal` reverts live edits within about three minutes.

This matters most when debugging: a patch used to test a hypothesis is reverted, usually
before Argo CD has recomputed its comparison, so the status you read afterwards reflects the
**reverted** state. An approach that works looks like an approach that does nothing. To test
against a live Application, pause root's self-heal first and restore it immediately after —
the procedure is in the ArgoSyncFailed runbook.

### ImagePullBackOff

The GitOps repository pins image tags to commit SHAs, and
`validate-gitops-revisions.sh` verifies each tag exists in GHCR before a pull request can
merge. A pull failing anyway means the package visibility changed or the tag was deleted
after merge.

```sh
bash scripts/validate-gitops-revisions.sh --gitops-dir ../NovaShop-GitOps
```

## Workload problems

### CrashLoopBackOff

Read the **previous** container's logs. The current one is usually too young to have logged
the fault.

```sh
sudo k3s kubectl -n <ns> logs <pod> --previous --tail=100
```

| Exit code | Meaning |
|---|---|
| 137 | OOM killed — limit too low, or a leak |
| 143 | SIGTERM, usually a failing probe |
| 1 / 2 | Application error |
| 127 | Command not found — wrong image or entrypoint |

Full detail: [PodCrashLooping](../observability/runbooks/pod-crashlooping.md).

### Pods are Running but not Ready

The backend's `/ready` probe checks PostgreSQL and Redis and returns 503 when either is
unreachable. That is the pod honestly reporting it cannot serve. Rule out the datastores
before touching the deployment:

```promql
pg_up == 1 and redis_up == 1
```

### A probe fails on a port that works

Confirm the probe and any scrape annotation name the **container** port. Endpoints-role
discovery and probes connect to the pod IP, so naming a Service port yields connection
refused on every replica while everything else looks healthy. This happened here across six
production pods and produced no data with no error.

## Node problems

### Disk

```sh
df -h /
sudo du -sh /var/lib/rancher/k3s/storage/*
sudo k3s crictl rmi --prune          # usually the largest, always safe
```

One disk holds container images, the k3s SQLite datastore, PostgreSQL, and every volume. A
full disk stops the database *and* the monitoring that would have told you.
[DiskFull](../observability/runbooks/disk-full.md).

If an observability volume has grown past its configured size, retention is not being
enforced — that is a bug to fix, not disk to add.
[ObservabilityVolumeFilling](../observability/runbooks/observability-volume-filling.md).

### "too many open files" in any workload log

inotify instance exhaustion. The default limit is 128 and this node reached 140: every config
reloader, log collector, dashboard sidecar, and certificate watcher consumes one.

```sh
sudo scripts/linux/configure-node-limits.sh
```

This is a correctness problem, not a cosmetic one. A workload that cannot create a watcher
keeps running with whatever it loaded at startup and **silently stops noticing changes** —
which here means a renewed certificate or a synced manifest that never takes effect. Anything
that already logged the failure must be restarted.

### Memory

Limits sit near 150% of allocatable, deliberately. When it stops being free, the OOM killer
picks by score, not importance — so the visible symptom is usually a crash loop rather than
anything saying "out of memory".

```sh
sudo dmesg -T | grep -i 'killed process' | tail
```

[MemoryHigh](../observability/runbooks/memory-high.md). Reduce replicas before raising
thresholds.

## Datastore problems

Both run on the host and are reached over the pod network, so one symptom covers three
faults: the service being down, the bind address being wrong, and authentication failing.

```sh
sudo ss -ltnp | grep -E '5432|6379'       # expect 10.10.1.45, not only 127.0.0.1
sudo scripts/linux/configure-datastores.sh   # idempotent; safe to rerun
```

An unauthenticated `redis-cli ping` returning `NOAUTH` is the **healthy** answer. It proves
Redis is reachable and protected. Reading it as a failure sends you looking in the wrong
place.

[DatabaseDown](../observability/runbooks/database-down.md) ·
[RedisDown](../observability/runbooks/redis-down.md)

## Observability problems

### A metric returns no data

Distinguish "not collected" from "healthy with nothing to report" — they look identical, and
this is the failure mode the whole observability gate exists to prevent.

```promql
up{job="<job>"}                  # is the target even up?
count({__name__=~"<prefix>.*"})  # does any series exist?
```

Then check the target list for that job. A scrape job whose relabel rules match nothing
renders, validates, and deploys correctly and collects nothing.

### A query works in Prometheus and the alert never fires

Almost always a label selector that matches no series. Evaluate the alert's expression
directly, then strip the comparison to see whether the inputs exist at all. That technique
found a real defect here: Traefik was being scraped twice, so the edge alerts needed pinning
to `job="traefik"`.

## Validate the whole configuration

All three gates run without a cluster:

```sh
bash scripts/validate-platform.sh          --gitops-dir ../NovaShop-GitOps   # 38 checks
bash scripts/validate-gitops-revisions.sh  --gitops-dir ../NovaShop-GitOps   # 30 checks
bash scripts/validate-observability.sh     --gitops-dir ../NovaShop-GitOps   # 25 checks
```

## When it is the node itself

[NodeDown](../observability/runbooks/node-down.md), then
[Disaster Recovery](../recovery/disaster-recovery.md). There is one node and nowhere to
reschedule to.
