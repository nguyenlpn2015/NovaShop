# Production Deployment Guide

Building the platform on a real node. Read
[Ubuntu + k3s deployment](../deployment/ubuntu-k3s.md) for server preparation detail; this
guide is the sequence and the decisions.

## Before you start

| Requirement | Why it is checked first |
|---|---|
| Ubuntu 22.04 LTS, 4 vCPU, 8GB, 30GB disk | Below this, memory limits at ~150% stop being survivable |
| `sudo` and SSH access | Bootstrap runs as root |
| Public DNS already pointing at the site | HTTP-01 cannot validate otherwise, and certificates are rate limited |
| DNAT for 80 **and** 443 to the node | Port 80 is required for ACME, not just for redirects |
| `/root/.novashop-platform.env` prepared | Bootstrap will not invent credentials |
| Your own source address known | UFW must not be enabled without it |

That last row is not paperwork. The operator workstation on this platform is `192.168.3.2`,
which is **not** inside `10.10.0.0/16`. A firewall rule written for the node's own subnet
would lock the operator out of the only node, with no second machine to fix it from. This is
why `configure-datastores.sh` refuses to enable UFW unless `MANAGEMENT_CIDR` is set
explicitly — a sensible-looking default is worse than refusing to act.

## The environment file

```sh
sudo install -m 0600 /dev/null /root/.novashop-platform.env
sudo tee /root/.novashop-platform.env >/dev/null <<'EOF'
export DATABASE_URL="postgresql://novashop:CHANGE_ME@10.10.1.45:5432/novashop"
export REDIS_URL="redis://:CHANGE_ME@10.10.1.45:6379/0"
export MANAGEMENT_CIDR="192.168.3.0/24"
EOF
```

Root-owned, mode 0600, never committed. It is part of the backup and a **precondition** of
recovery — `recover.sh` verifies its ownership and mode before changing anything. See
[ADR 010](../../adr/010-secret-management.md).

Note the addresses are `10.10.1.45`, not `localhost`. From inside a pod, `localhost` is the
pod.

## Bootstrap

```sh
git clone https://github.com/nguyenlpn2015/NovaShop.git
cd NovaShop
sudo scripts/linux/bootstrap.sh
```

What it does, in order — see [Bootstrap Flow](../architecture/bootstrap-flow.md) for the
diagram:

1. Loads the environment file.
2. Prepares the server: packages, swap off, time sync, hostname.
3. Raises inotify limits, 128 → 512 instances.
4. Configures UFW **only if** `MANAGEMENT_CIDR` is set.
5. Configures PostgreSQL and Redis for pod-network access.
6. Installs k3s, Helm, and Argo CD — verifying the Argo CD manifest against a pinned digest.
7. Confirms the GitOps repository is reachable **before** handing over control.
8. Applies the root Application and lets Argo CD reconcile everything else.

Every step is idempotent. Rerunning it on a configured node changes nothing and restarts
nothing, which is what makes it safe to run during an incident.

## Create the two out-of-band Secrets

Argo CD will reconcile everything except these. Grafana and the exporters will not become
healthy until they exist.

```sh
kubectl -n observability create secret generic novashop-grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24)"

kubectl -n observability create secret generic novashop-datastore-exporter \
  --from-literal=DATA_SOURCE_NAME='postgresql://novashop_exporter:PASS@10.10.1.45:5432/novashop?sslmode=disable' \
  --from-literal=REDIS_PASSWORD='PASS'
```

Record the Grafana password somewhere durable. It is not in Git and it is not recoverable
from the cluster in plain text.

## Watch it converge

```sh
watch kubectl get applications -n argocd
```

Expect **12 Applications**, all `Synced/Healthy`. Convergence takes a few minutes; TLS takes
longer because certificate issuance depends on Let's Encrypt.

If one sits `OutOfSync` while the sync reports `Succeeded`, that is permanent drift rather
than slowness. Do not re-sync it repeatedly — read
[ArgoSyncFailed](../observability/runbooks/argo-sync-failed.md), which explains which pair of
states to compare. `helm template | diff` will report zero differences on an Application that
is genuinely OutOfSync.

## Verify

```sh
sudo scripts/linux/verify.sh
```

It detects the edge phase from live cluster state and asserts the properties appropriate to
it. It does not need to be told which phase it is in, because a script that can be told can
be told the wrong thing.

| Phase | Means |
|---|---|
| `http` | Serving, no certificates yet |
| `baseline` | HTTPS available, HTTP still served |
| `enforced` | Redirect and HSTS active |

Then the observability checks:

```sh
kubectl -n observability port-forward svc/novashop-prometheus-server 9090:80
# 31/31 targets up; count(ALERTS) queryable; 14 rules, all inactive on a healthy platform
```

## TLS reaches `enforced` on its own

The phases exist because Let's Encrypt allows **five duplicate certificates per 168 hours**.
A bootstrap that demanded TLS before the edge was reachable would fail validation, retry, and
burn a week's budget in an afternoon.

So do not force it. Let the phases progress, and if certificates are not issuing, read
[CertificateExpiring](../observability/runbooks/certificate-expiring.md) — in particular the
instruction **not** to delete a Certificate to force a retry. It feels like a reset and it
spends one of five.

## Take a backup before you need one

```sh
sudo scripts/backup-platform-state.sh
```

Captures **certificate Secrets and the ACME account key** — Kubernetes Secrets, and nothing
else. It contains private keys, which is why `.gitignore` blocks `platform-state*/`,
`tls-*.json`, `acme-*.json`, and `runtime-*.json`.

Application data needs the second script:

```sh
sudo scripts/backup-datastores.sh --output-dir /srv/novashop-backup
sudo scripts/verify-backup.sh /srv/novashop-backup/<timestamp>
```

That one dumps PostgreSQL and takes an online copy of the k3s SQLite datastore. **Run both.**
Neither covers what the other does.

Prometheus, Loki, and Alertmanager volumes are **not** in the backup. They are node-local by
definition and their contents are observational and bounded by retention anyway. Excluding
them keeps a backup small enough that taking one is not a decision.

Then rehearse the restore. A recovery procedure that has never been run is a document, not a
capability — see [Disaster Recovery](../recovery/disaster-recovery.md).

## Post-deployment

| Task | Where |
|---|---|
| Apply branch protection to both repositories | `scripts/apply-branch-protection.sh` |
| Rotate the node password, move to SSH keys | [Hardening](../security/hardening.md) |
| Configure alert routing | [Alerts](../observability/alerts.md) |

## Next

- [Observability Guide](observability-guide.md)
- [Troubleshooting](troubleshooting.md)
- [Platform Upgrade](platform-upgrade.md)
