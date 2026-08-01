# ADR 005: Argo CD as the GitOps controller

## Status

Accepted

## Date

2026-08-01

## Context

[ADR 003](003-gitops-delivery.md) settled on pull-based GitOps. This decision is which
controller.

The requirements that discriminated between the candidates:

- **Multi-source Applications.** The Helm chart lives in `NovaShop`, the values live in
  `NovaShop-GitOps`, and the chart may come from an upstream repository. One Application
  has to compose sources from more than one place.
- **Templated environments.** Three environments differing only by namespace, replica
  count, and a values file. Generating them from one definition, not three copies.
- **Enforceable boundaries.** Something that refuses to create resource kinds outside a
  declared set, so the platform's blast radius is a property of the configuration rather
  than of everyone's care.
- **Ordering.** cert-manager's CRDs must exist before a `Certificate` is valid;
  Prometheus should be running before what it observes.
- **Visible state to a single operator.** With one person on call, "what is different
  from Git, right now" has to be a question with a fast answer.

## Decision

Argo CD, installed from an upstream manifest whose SHA-256 is pinned in
`argocd/install-manifest.sha256`.

Used with: multi-source Applications, an `ApplicationSet` list generator for the three
environments, two `AppProject`s (`novashop` and `novashop-platform`) with resource
whitelists, sync waves from `-30` to `10`, `ServerSideApply=true`,
`ApplyOutOfSyncOnly=true`, and `automated: {prune: true, selfHeal: true}` everywhere.

## Alternatives Considered

**Flux v2.** The strongest alternative, and better than Argo CD in real ways: smaller
footprint, no UI to secure, and a controller-per-concern design that is arguably cleaner.
Rejected on two counts specific to this platform. Its `HelmRelease` composition across
repositories is less direct than an Argo CD multi-source Application, which is exactly
the shape needed here. And there is no equivalent of the `AppProject` whitelist —
Kyverno or an admission controller would have to supply that boundary, which means adding
a technology to get a property Argo CD includes. For a single operator, the web UI is
also a genuine diagnostic advantage rather than a liability.

**Helm from CI, no controller.** Rejected in [ADR 003](003-gitops-delivery.md): cluster
credentials in CI, and no self-heal.

**Argo CD with plain manifests instead of Helm.** Rejected in
[ADR 006](006-helm-and-kustomize.md).

**Rancher Fleet.** Designed for many clusters. Its unit of work is a bundle across a
fleet, which adds concepts that pay off at a scale this platform does not have.

## Consequences

**Easier.** Three environments from one `ApplicationSet` definition. Sync waves give
ordering without a scheduler. The `AppProject` whitelist makes the blast radius
declarative. Drift is visible and corrected. The UI answers "what differs from Git"
immediately.

**Harder, and accepted.**

*More components than Flux.* application-controller, repo-server, server, applicationset
controller, redis, dex. Dex is unused and still scraped-adjacent enough that the
Prometheus job has to drop `argocd-dex-server`, which does not serve metrics.

*The whitelist fails at sync time.* Discussed in ADR 003 and mitigated by a pre-merge
gate.

*Server-side diff is subtle.* With `ServerSideApply`, sync status is decided by comparing
a server-side apply **dry-run** against the live object — not the rendered manifest
against the live object. `helm template | diff` is the natural instinct and it reported
zero differences on an Application that was permanently OutOfSync. Two consecutive wrong
fixes came from reading the wrong pair of states. The correct procedure is in the
[ArgoSyncFailed runbook](../docs/observability/runbooks/argo-sync-failed.md).

*Charts that omit defaulted fields cause permanent drift.* Kubernetes fills in
`apiVersion` and `kind` on a StatefulSet's `volumeClaimTemplate`; a server-side apply
dry-run does not reproduce them. The Loki chart templates them explicitly and stays
Synced; the Prometheus chart does not and needed an `ignoreDifferences` entry. Every such
entry is a small permanent exception, and each one is commented with what it is for.

*The install manifest is large and applied with cluster-admin.* Hence the pinned digest —
a version tag is a mutable pointer at a URL.

## Validation

```sh
kubectl get applications -n argocd
kubectl get appprojects -n argocd
kubectl get applicationset -n argocd

# The install manifest matches what was reviewed
sha256sum -c argocd/install-manifest.sha256
```

`scripts/validate-platform.sh` asserts the ApplicationSet source invariants;
`scripts/validate-observability.sh` asserts every rendered kind is permitted by the
`AppProject`.
