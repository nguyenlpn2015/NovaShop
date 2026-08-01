# ADR 010: Secrets created outside Git, by documented procedure

## Status

Accepted

## Date

2026-08-01

## Context

The platform needs several credentials at runtime: PostgreSQL and Redis passwords for the
application, a separate least-privilege pair for the metrics exporters, and Grafana admin
credentials.

Everything else about this platform is declarative and in Git. Secrets cannot be, and
something has to fill the gap in a way that survives a node rebuild — because
[recovery](../docs/architecture/recovery-flow.md) has to work, and a recovery that cannot
reproduce the credentials is not a recovery.

The constraint that ruled out the obvious answers: one node, one operator, no cloud
account, and no second machine. Any solution requiring a hosted service or a second
cluster is not available.

## Decision

Secrets are created outside Git by documented procedure.

Runtime credentials live in `/root/.novashop-platform.env`, owned by root with mode 0600,
sourced by the bootstrap and datastore configuration scripts. Two Kubernetes Secrets are
created out of band:

| Secret | Namespace | For |
|---|---|---|
| `novashop-grafana-admin` | `observability` | Grafana admin user and password |
| `novashop-datastore-exporter` | `observability` | PostgreSQL and Redis exporter credentials |

Charts reference them by name — `admin.existingSecret: novashop-grafana-admin` — so no
chart values file contains a credential.

`.gitignore` blocks `tls-*.json`, `acme-*.json`, `runtime-*.json`, and `platform-state*/`.
Captured platform state contains certificate private keys and datastore passwords, and a
backup is the easiest thing in this repository to commit by accident.

The environment file is part of the backup and a **precondition** of recovery:
`scripts/linux/recover.sh` checks it exists, is root-owned, and is mode 0600 before it
changes anything.

## Alternatives Considered

**Sealed Secrets (Bitnami).** The best fit of the GitOps-native options: encrypt with a
controller's public key, commit the ciphertext, and the desired state becomes complete.
Rejected because the controller's private key becomes the thing that must survive a node
rebuild — so the bootstrap problem does not go away, it moves and gains a component. If
the key is lost, every sealed secret in Git is permanently undecryptable, which on a
single node with node-local storage is a realistic outcome rather than a theoretical one.

**SOPS with age, via Argo CD plugin.** Same shape and the same objection: the age key has
to exist on the node before Argo CD can render anything. It also needs a config management
plugin, which means modifying the Argo CD installation whose manifest is pinned by digest.
Genuinely attractive and worth revisiting if the platform ever gains a second node.

**External Secrets Operator with a cloud provider.** The right answer for a real
organisation. Rejected because there is no cloud account, and adding one makes the platform
depend on a paid external service for the credentials it needs to start.

**HashiCorp Vault, self-hosted.** Rejected on resource grounds and on circularity. Vault on
the same 8GB node, needing its own unsealing procedure and its own backup, is a larger
operational surface than the problem. It would also have to be running before the platform
could start, on a node where the platform is what starts things.

**Plain Secrets committed to Git.** Rejected. base64 is not encryption.

**No secrets at all — trust the network.** Genuinely considered, since this is a lab. This
is what the platform *had* before: PostgreSQL on loopback, Redis with no password. Rejected
because a Redis reachable from the pod network with no `requirepass` is a real finding, not
a stylistic one, and because the exporters made it worse — `pg_monitor` alone let the
exporter create tables, since PostgreSQL 14 grants `CREATE` on `public` to `PUBLIC`. That
grant is now revoked and given to the application role only.

## Consequences

**Easier.** No credential is in Git, in any form, so there is nothing to leak by making the
repository public and nothing to rotate because of a history rewrite. No encryption key has
to survive a node rebuild. Charts reference Secrets by name, so a credential rotation is a
`kubectl create secret` and a pod restart.

**Harder, and accepted.**

*The desired state is incomplete.* This is the real cost. Git does not fully describe the
cluster: a rebuild from Git alone produces workloads that cannot authenticate. Recovery
therefore depends on a backup artefact as well as a repository, which is why the
environment file is a checked precondition rather than an assumption.

*Bootstrap has a manual step.* Creating the two Secrets is documented and not automated
from Git. Documented manual steps rot, so they are exercised by every recovery rehearsal.

*Rotation is not automated.* No expiry, no reminder. A rotation procedure exists in
[docs/deployment/operations.md](../docs/deployment/operations.md); nothing enforces it.

*Least privilege needed proving, not assuming.* `pg_monitor` was not sufficient. The
exporter's inability to write was verified by attempting a write and having it denied, and
the application's ability to write was verified separately — a role change that quietly
breaks the application is worse than the permission it fixed.

## Open item

The operator's node password was shared in plain text during development and should be
rotated, with SSH key authentication replacing password authentication. This is recorded
as an open item rather than a resolved one. See
[docs/security/hardening.md](../docs/security/hardening.md).

## Validation

```sh
# No credential material in the repository
git grep -nE 'password|passwd|secret' -- '*.yaml' | grep -v existingSecret | grep -v secretName

# The Secrets exist and are referenced by name
kubectl -n observability get secret novashop-grafana-admin novashop-datastore-exporter
grep -n existingSecret kubernetes/observability/grafana/helm-values.yaml

# The environment file is protected
sudo stat -c '%U %a' /root/.novashop-platform.env      # root 600

# Least privilege actually holds
sudo -u postgres psql -c "\du novashop_exporter"
```

The `security` job in `.github/workflows/validation.yml` runs a secret scan on every pull
request.
