# Layer 5 — Cluster

Cluster-scoped prerequisites, the one namespace Argo CD does not reconcile, and a read-only
role. Everything else here is **asserted, not owned**.

## Why this layer owns almost nothing

The obvious version of a Kubernetes layer manages namespaces, RBAC, and storage. On this
platform that would mostly mean two controllers writing one object.

Checking what Argo CD actually reconciles, rather than assuming, produced this:

| Namespace | Reconciled by Argo CD | Evidence | Terraform |
|---|---|---|---|
| `argocd` | **No** | `managed-by: kubectl`, no tracking annotation — created by the bootstrap script before Argo CD existed | **owns** |
| `cert-manager` | Yes | `tracking-id: novashop-cert-manager:/Namespace:cert-manager` | asserts |
| `observability` | Yes | `tracking-id: novashop-prometheus:/Namespace:observability` | asserts |
| `novashop-development` | Yes | `managedNamespaceMetadata` on the ApplicationSet reapplies its labels every sync | asserts |
| `novashop-staging` | Yes | same | asserts |
| `novashop-production` | Yes | same | asserts |

So Terraform owns exactly one namespace. The `managedNamespaceMetadata` finding is the one
that matters most — those three namespaces look unmanaged (`get namespace -o yaml` shows no
tracking annotation) and are not. Declaring them in Terraform would produce a plan that
never converges, and the cause would be genuinely hard to find.

Recorded in [ADR 013](../../../adr/013-terraform-kubernetes-boundary.md).

## What it does own

**The `argocd` namespace**, with `prevent_destroy`. Deleting it removes Argo CD and every
Application object; the cluster would keep serving whatever it last converged to, with
nothing reconciling it and no way to deploy.

**A read-only ClusterRole**, `novashop-platform-viewer`. New, additive, owned by nothing
else. It exists because the only credential on this platform today is the cluster-admin
kubeconfig, so reading a log during an incident currently requires the ability to delete the
platform. It deliberately excludes `secrets` — a credential that cannot exfiltrate
credentials.

The binding is created only when `read_only_subjects` is non-empty. A binding to a subject
nobody uses grants nothing and hides that fact.

## What it asserts

Five `check` blocks covering the assumptions the rest of the repository is built on:

| Assertion | Why it matters |
|---|---|
| `local-path` is the **default** StorageClass | A PVC without an explicit `storageClassName` binds elsewhere. This is how a volume silently lands on the wrong provisioner — it already happened once, via `storageClass` versus `storageClassName` in a Helm values file. |
| Binding mode is `WaitForFirstConsumer` | A volume should be provisioned where its pod is scheduled |
| Node count is **1** | Every document states single-node behaviour: no rescheduling, node-local volumes, recovery as a rehearsed procedure. A second node invalidates those claims and should say so loudly. |
| Kubernetes minor ≥ 30 | The floor the manifests are known to render against |
| Pod Security enforcement unchanged | `observability` is `privileged` because node-exporter needs host network and host mounts; everything else is `restricted`. A change here is a security posture change nobody declared. |

`check` blocks report at plan time and do not block apply, which is the right severity. These
describe assumptions; a violated assumption is something an operator must see, not something
Terraform should refuse to proceed past.

## Secrets: a contract, not resources

Terraform **does not create, import, or read** any Secret on this cluster, and there is no
Secret data source either.

The reason is specific. The kubernetes provider reads the whole object, so a data source is
as revealing as an import: either would place `admin-password` and `postgres-dsn` in
Terraform state in plaintext. That is weaker than where they live today —
`/root/.novashop-platform.env` at 0600, root-owned. Managing them here would make the
platform *less* secure while looking more codified.

What is codified is the **shape**: name, namespace, keys, type, consumer, and purpose. From
that, two outputs do the useful work:

```sh
terraform output -json secret_commands          # exact kubectl create for each
terraform output -raw secret_verification_command | sh
```

The first makes a rebuild a copy-paste instead of reconstructing key names from chart values.
The second reports which Secrets are missing without printing a value.

The key names come from the same declaration the charts consume, so the contract and the
consumer cannot drift apart.

## Running it

Unlike every other layer, `plan` here needs a reachable cluster — it reads live state to
assert prerequisites. `terraform validate` still needs nothing, which is why CI validates it
without a cluster.

```sh
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml     # cluster-admin, mode 0600

cp ../../examples/backend-local-override.tf.example backend_override.tf
cp ../../examples/5-cluster.tfvars.example terraform.tfvars

terraform init
terraform plan
```

## The acceptance gate

The `argocd` namespace exists, so it is **imported, not created**:

```hcl
import {
  to = kubernetes_namespace_v1.argocd
  id = "argocd"
}
```

The gate is that after import, the plan contains **only** the two new RBAC objects and **no
change to the namespace**. If the plan wants to modify the namespace, the label set in
`argocd_namespace_labels` does not match the cluster — applying it would strip labels that
are genuinely there.

```
Plan: 1 to add, 0 to change, 0 to destroy.        # role only, no subjects configured
Plan: 2 to add, 0 to change, 0 to destroy.        # role and binding
```

This layer's first apply is not a no-op, because the read-only role is new. That is the one
place in the Terraform work where Terraform creates rather than adopts, and it is additive.

## Handing `observability` over, if that is ever wanted

Not done, and worth stating why. Removing `namespace.yaml` from the prometheus Application's
source with `prune: true` in effect would **delete the namespace** — and with it Prometheus,
Grafana, Loki, Alloy, Alertmanager, and all four PersistentVolumeClaims.

A safe handover would be, in order:

1. Annotate the namespace manifest with `argocd.argoproj.io/sync-options: Prune=false`, and
   let that sync.
2. Confirm the annotation is live on the cluster.
3. Remove `namespace.yaml` from the Application source; confirm the namespace survives.
4. Add it to this layer with an `import` block; confirm an empty plan.

Four steps, two repositories, and a destructive failure mode at step 3 if step 1 did not take
effect. The value is consistency; the cost is a real chance of deleting the observability
stack. It has not been judged worth it.
