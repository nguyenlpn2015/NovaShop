# Platform Upgrade Guide

Moving k3s, Argo CD, or an upstream chart to a new version on a single node.

## The rule that makes this safe

**Upgrade one thing, verify, then upgrade the next.** On one node there is nothing to fail
over to, so a batched upgrade that breaks leaves you diagnosing several changes at once with
no healthy comparison.

Every upgrade below is a Git change. The only exceptions are k3s and the node itself, because
they are what runs Git's output.

## Before any upgrade

```sh
sudo scripts/backup-platform-state.sh
sudo scripts/linux/verify.sh              # a green baseline to compare against
kubectl get applications -n argocd        # 12, all Synced/Healthy
```

Upgrading from an already-degraded state means you cannot tell which fault is yours.

## Upgrading an upstream chart

The common case: Prometheus, Grafana, Loki, Alloy, cert-manager, an exporter.

**1. Bump the version in the Argo CD Application** in the GitOps repository:

```yaml
- repoURL: https://prometheus-community.github.io/helm-charts
  chart: prometheus
  targetRevision: 29.20.1        # <- here
```

**2. Bump the matching constant in the gate**, in `scripts/validate-observability.sh`:

```bash
readonly PROMETHEUS_CHART_VERSION="${PROMETHEUS_CHART_VERSION:-29.20.1}"
```

The gate renders the version it is told about. Leaving it behind means CI validates a chart
the cluster is not running — which is worse than not validating, because it reports success.

**3. Run the gate before opening the pull request:**

```sh
bash scripts/validate-observability.sh --gitops-dir ../NovaShop-GitOps
```

This is where chart upgrades actually get caught. The gate asserts that required scrape jobs
are still present by name, that Traefik is still discovered by pod, that Loki has not quietly
reintroduced its caches, gateway, canary, or MinIO, that every rendered kind is still
permitted by the `AppProject`, and that every container still declares requests and limits.
Chart defaults change between minor versions and none of those regressions would fail a
render.

**4. Merge, then verify convergence:**

```sh
kubectl get applications -n argocd
kubectl -n observability get pods
```

### What chart upgrades break here

Three real ones, worth checking for by name:

**A new resource kind.** Argo CD refuses kinds the `AppProject` does not whitelist, at sync
time — so it merges cleanly and fails afterwards. The gate now catches this before merge.

**A field that server-side apply cannot predict.** If a chart stops templating a field that
Kubernetes defaults, the Application goes permanently OutOfSync while the sync reports
Succeeded. Loki templates `apiVersion`/`kind` on its `volumeClaimTemplate`; Prometheus's
Alertmanager does not, and needed an `ignoreDifferences` entry. See
[ArgoSyncFailed](../observability/runbooks/argo-sync-failed.md) for which pair of states to
compare — not the rendered manifest against live.

**A resource request that no longer fits.** Node memory limits sit near 150% of allocatable.
A chart that raises a default request can make a pod unschedulable, and `Pending` is the only
symptom.

## Upgrading k3s

The most disruptive operation on this platform. It restarts the API server, and on one node
that is a control-plane outage — workloads keep running, but nothing can be observed or
changed while it happens.

```sh
sudo scripts/backup-platform-state.sh
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=vX.Y.Z+k3sN sh -
sudo systemctl status k3s
kubectl get nodes
kubectl get applications -n argocd
sudo scripts/linux/verify.sh
```

Two consequences specific to k3s:

**Traefik comes with it.** Traefik is a bundled component versioned by k3s, currently chart
40.1.3+up40.1.0 and image 3.7.4. A k3s upgrade can move Traefik, which means the ingress and
its metrics endpoint can change in an upgrade you thought was about the API server.
Re-run the observability gate afterwards. See
[ADR 007](../../adr/007-ingress-controller.md).

**SQLite is the datastore.** There is no quorum to roll back to — the backup is the rollback.
Take one, and confirm it exists rather than assuming.

### The pending k3s change

Scraping the scheduler and controller-manager needs bind-address flags:

```
--kube-scheduler-arg=bind-address=0.0.0.0
--kube-controller-manager-arg=bind-address=0.0.0.0
```

This requires a k3s restart, so it is deliberately deferred to a maintenance window and
should be combined with the next k3s upgrade rather than spending a separate outage on it.

## Upgrading Argo CD

Argo CD is installed from an upstream manifest whose digest is pinned in
`argocd/install-manifest.sha256`.

```sh
VERSION=vX.Y.Z
curl -sSL -o /tmp/argocd.yaml \
  "https://raw.githubusercontent.com/argoproj/argo-cd/${VERSION}/manifests/install.yaml"
sha256sum /tmp/argocd.yaml            # record this in argocd/install-manifest.sha256
```

Update the digest in the **same commit** as the version. The digest exists because a version
tag is a mutable pointer at a URL, and bootstrap applies that file with cluster-admin. A
digest updated in a separate commit is a digest that was never reviewed against its manifest.

Then:

```sh
sudo scripts/linux/install-argocd.sh
kubectl -n argocd get pods
kubectl get applications -n argocd
```

Argo CD upgrades can change diff behaviour. If Applications go OutOfSync afterwards with no
manifest change, suspect that before suspecting your configuration.

## Upgrading the application

Not a platform upgrade — it is the normal delivery path, and it needs no procedure:

1. Merge to `main` in `NovaShop`. CI validates, scans, and publishes images tagged by commit
   SHA.
2. Open a GitOps pull request re-pinning `targetRevision` and both image tags to that SHA.
3. `validate-gitops-revisions.sh` proves the SHA is an ancestor of `main` and that both
   images exist in GHCR.
4. Merge. Argo CD converges within about three minutes.

Rollback is `git revert` on the GitOps commit. Do **not** use `kubectl rollout undo` —
`selfHeal` restores the Git state within three minutes and undoes your undo.

## Upgrading Ubuntu

```sh
sudo apt update && sudo apt upgrade
sudo scripts/linux/configure-node-limits.sh      # confirm sysctl survived
sudo scripts/linux/configure-datastores.sh       # idempotent; confirms managed blocks
sudo scripts/linux/verify.sh
```

Both scripts are idempotent and rerunning them is the cheapest way to confirm a package
upgrade did not overwrite a managed block. A PostgreSQL major version upgrade is not routine
maintenance and is out of scope for this guide.

## Rolling back an upgrade

| What | How |
|---|---|
| Chart version | Revert the GitOps commit |
| Application image | Revert the GitOps commit |
| Argo CD | Reinstall the previous manifest, restore its digest |
| k3s | Reinstall the previous version, restore the datastore from backup |
| Node | [Disaster Recovery](../recovery/disaster-recovery.md) |

Rolling back **out of TLS enforcement** has a trap: serve `max-age=0` first so browsers
release the HSTS pin. Dropping straight to HTTP leaves every previous visitor unable to reach
the site, with no error they can click through. See
[TLS Flow](../architecture/tls-flow.md).

## Dependency upgrades from Dependabot

Dependabot raises image and package bumps. Two categories behave differently:

**Patch and minor** normally pass on their own.

**Major** language or base-image bumps will fail the runtime-alignment check in
`validate-platform.sh`, which asserts the Node major and Python minor versions match across
the Dockerfiles, the workflow environment variables, `engines.node`, `@types/node`, and
`requires-python`. That is the check working: a major bump has to move all of them together,
in one commit. Do not merge it piecemeal, and do not weaken the check to let it through.

## After any upgrade

```sh
sudo scripts/linux/verify.sh
kubectl get applications -n argocd
```

```promql
up == 0             # empty
count(ALERTS)       # 0 on a healthy platform
```

Then take a fresh backup — the old one now restores to a version you have moved away from.
