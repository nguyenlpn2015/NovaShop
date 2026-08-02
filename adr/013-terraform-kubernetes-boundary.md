# ADR 013: Terraform's Kubernetes layer asserts more than it owns

## Status

Accepted. Refines [ADR 012](012-terraform-scope.md), which stated there would be no
Kubernetes layer at all.

## Date

2026-08-02

## Context

[ADR 012](012-terraform-scope.md) drew the boundary at the cluster edge: Terraform manages
the node, datastores, k3s, GitHub, and DNS, and nothing inside Kubernetes. The reason was
sound — two controllers reconciling one object is a platform that never converges.

The boundary was drawn from the principle rather than from the cluster, and a Kubernetes
layer was then requested. Before writing one, the obvious question is which objects Argo CD
actually reconciles. The answer was not what the principle predicted.

Reading the live cluster:

| Namespace | Argo CD reconciles it | Evidence |
|---|---|---|
| `argocd` | **No** | `managed-by: kubectl`, no tracking annotation. The bootstrap script applies `argocd/namespace.yaml` before Argo CD exists. |
| `cert-manager` | Yes | `tracking-id: novashop-cert-manager:/Namespace:cert-manager` |
| `observability` | Yes | `tracking-id: novashop-prometheus:/Namespace:observability` |
| `novashop-development` | Yes | `managedNamespaceMetadata` on the ApplicationSet |
| `novashop-staging` | Yes | same |
| `novashop-production` | Yes | same |

The last three are the finding that matters. They carry **no tracking annotation**, so
`kubectl get namespace -o yaml` shows nothing suggesting Argo CD owns them. It does:
`managedNamespaceMetadata` on the ApplicationSet reapplies their labels on every sync. A
Terraform declaration of those labels would be reverted continuously, `terraform plan` would
never converge, and the cause would be genuinely hard to find because the usual evidence of
Argo CD ownership is absent.

So there is exactly one namespace Terraform can own, and the useful contribution a
Kubernetes layer makes is not ownership.

## Decision

A `5-cluster` layer exists. It **owns two things and asserts eleven**.

**Owns:**

- The `argocd` namespace, imported, with `prevent_destroy`. Its labels and annotations
  mirror `argocd/namespace.yaml` exactly.
- A read-only `ClusterRole`, `novashop-platform-viewer`, and a binding created only when
  subjects are declared. New, additive, owned by nothing else.

**Asserts, through data sources and `check` blocks:**

- `local-path` exists, is the default StorageClass, and binds with `WaitForFirstConsumer`.
- Node count is 1.
- Kubernetes minor is at or above a declared floor.
- Pod Security enforcement per tracked namespace matches the declared posture —
  `observability` privileged, everything else restricted.
- Every Argo CD-tracked namespace exists.

**Never touches:** any Helm release, any Application or AppProject, any workload, and — most
importantly — any Secret.

Secrets are codified as a **contract**: name, namespace, keys, type, consumer, purpose, plus
outputs rendering the exact `kubectl create secret` command and a verification command. No
Secret resource, no Secret import, and no Secret data source.

## Alternatives Considered

**Manage all six namespaces.** The version that looks most complete. Rejected on evidence:
five of six are reconciled by Argo CD, three of them invisibly. This would produce permanent
drift on the namespaces holding every application environment.

**Hand `observability` over from Argo CD to Terraform.** Coherent, and the safe sequence is
known: annotate the namespace `Prune=false`, sync, confirm, remove it from the Application
source, confirm survival, then import. Rejected on risk against benefit. Removing a tracked
resource from an Application with `prune: true` **deletes** it, and this namespace holds
Prometheus, Grafana, Loki, Alloy, Alertmanager, and four PersistentVolumeClaims. Four steps
across two repositories, with a destructive failure at step three if step one did not take
effect, to gain consistency. Documented in the layer README so the option stays open.

**Manage the Secrets with `lifecycle.ignore_changes = [data]`.** Superficially the elegant
answer: Terraform owns the shell, an operator fills the values. Rejected because adoption
requires `terraform import`, and importing a `kubernetes_secret` **reads its values into
state in plaintext**. `ignore_changes` prevents future writes; it does not un-read what
import already read.

**Use a Secret data source to assert existence.** Rejected for the same reason. The provider
returns the whole object, so a data source is as revealing as an import. Existence is
verified with `kubectl` instead, through a rendered command that prints presence and never a
value.

**Manage `local-path` as a resource rather than a data source.** It ships with k3s and is
recreated by the k3s installer. Terraform owning it would fight the distribution on every
upgrade. Reading and asserting it is the correct relationship: the platform depends on its
properties without claiming to control them.

**Use `check` blocks that fail the apply.** Rejected. `check` reports at plan time and does
not block, which is the right severity for an assumption. A node count of two is something an
operator must see; it is not a reason for Terraform to refuse to create a read-only role.

## Consequences

**Easier.** The assumptions the whole repository is built on are now executable. That
`local-path` is the default StorageClass is not a sentence in [ADR 002](002-kubernetes-distribution.md)
any more — it is an assertion that fires when it stops being true, which matters because a
`storageClass` versus `storageClassName` mistake in a Helm values file has already silently
provisioned from the wrong place once. The single-node claim, repeated in every document, is
now defended. The Pod Security posture cannot change without a plan reporting it. The Secret
contract makes a rebuild a copy-paste rather than reconstructing key names from chart values.

Incident triage no longer requires cluster-admin, once subjects are bound to the read-only
role.

**Harder, and accepted.**

*This layer's plan needs a live cluster.* Every other layer plans offline. `validate` still
needs nothing, so CI is unaffected, but a plan here cannot run from a workstation without
cluster access.

*Two declarations of the `argocd` namespace exist.* `argocd/namespace.yaml` remains the
bootstrap path — the namespace must exist before Argo CD, and this layer runs afterwards.
Terraform's declaration mirrors it exactly, and they must be changed together. The
alternative is a bootstrap that cannot create the namespace it needs.

*The layer's first apply is not a no-op.* The read-only role is new. This is the only place
in the Terraform work where Terraform creates rather than adopts, and it is additive.

*Assertions can drift from what they assert.* A `check` block naming the wrong expectation
passes quietly. Each was negative-tested against the live cluster to prove it fires.

*A missing StorageClass reads back as an empty object rather than an error.* Found by
testing: the two property assertions fired with messages describing the wrong problem. An
existence check now runs first and says so. It uses `coalesce`, not `length`, because
`length(null)` raises and would replace the message with a Terraform internal error.

## Validation

```sh
cd terraform/layers/5-cluster
terraform plan
```

The gate is:

```
Plan: 1 to import, 1 to add, 0 to change, 0 to destroy.
```

`1 to import` is the `argocd` namespace adopted with **no change**. `1 to add` is the new
read-only role. Anything under "to change" means the declared labels or annotations do not
match the cluster, and applying would strip metadata that is genuinely there.

Verified on the live cluster, including that every assertion fires when violated:

| Violation | Result |
|---|---|
| `expected_node_count = 2` | reported, naming the observed node |
| `minimum_kubernetes_minor = 99` | reported, naming the observed version |
| `storage_class_name = "does-not-exist"` | reported, naming non-existence rather than a property |
| `observability` declared `restricted` | reported, showing expected against observed |

And the boundary itself:

```sh
# Managed resources only. A bare grep for "argoproj" false-positives on the read-only
# role's api_groups and on the sync-wave annotation key, neither of which is an object
# Terraform manages.
grep -rnE '^resource "(helm_release|kubernetes_secret|kubernetes_manifest)' terraform/

# And what this layer does declare, in full:
grep -rnE '^resource ' terraform/layers/5-cluster/*.tf
```
