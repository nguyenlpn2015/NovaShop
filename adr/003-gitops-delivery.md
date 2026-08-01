# ADR 003: GitOps as the delivery model

## Status

Accepted

## Date

2026-08-01

## Context

Something has to decide what runs on the cluster. The realistic options are a CI job
that holds cluster credentials and applies manifests, or a controller in the cluster
that pulls a declared desired state.

Three facts about this platform shaped the choice.

There is one node and one operator. When something is wrong, the first question is
always "what is supposed to be running?", and answering it by reading the cluster only
tells you what *is* running.

The platform must be recoverable onto a replacement node. That means the desired state
has to exist somewhere other than the cluster, in a form that can be replayed.

Manual intervention had to be designed out. A platform where the fix for an incident is
`kubectl edit` accumulates changes nobody can reproduce, and the recovery procedure
becomes fiction.

## Decision

GitOps, with two repositories.

`NovaShop` holds application code, the Helm chart, and platform component values.
`NovaShop-GitOps` holds the desired state: which Applications exist, which revision of
`NovaShop` each renders from, and which image tags run.

Every reference from the GitOps repository to `NovaShop` is a 40-character commit SHA.
Nothing tracks a branch except the two deliberate self-references.

Reconciliation is automated with `prune: true` and `selfHeal: true`, so drift is
reverted within about three minutes.

## Alternatives Considered

**Push-based CI deployment.** A workflow with a kubeconfig running `helm upgrade`.
Simpler, one repository, and immediate. Rejected on two grounds: it puts long-lived
cluster-admin credentials in a CI system, which is the highest-value secret in the
platform sitting in the place with the largest attack surface; and it gives no answer
to "what is supposed to be running" other than replaying workflow logs. It also cannot
self-heal — drift persists until someone notices.

**One repository for code and desired state.** Fewer moving parts, and a real
convenience. Rejected because it couples the two lifecycles: every image build becomes
a potential deployment, and reverting a deployment means reverting code. The two-merge
cost of separate repositories is the feature, since the second merge is where a human
decides that a verified image should become live.

**Manual `kubectl apply` from a checkout.** Honest about scale and defensible for a one
person lab. Rejected because it makes the recovery procedure untestable — there is no
artefact to replay, only a person remembering the order.

**Flux instead of Argo CD.** A GitOps choice, not a delivery-model choice. See
[ADR 005](005-gitops-controller.md).

## Consequences

**Easier.** The desired state is reviewable, diffable, and revertible. Recovery becomes
"rebuild the node, point it at the repository", which is why
`scripts/linux/recover.sh` can be a short script. Drift is corrected automatically.
There are no cluster credentials in CI at all.

**Harder, and accepted.**

*Two merges per release.* Intentional, and it does slow down a hotfix.

*Live edits are reverted.* Correct behaviour with a genuinely counter-intuitive
consequence: a `kubectl patch` used to test a hypothesis is undone, usually before the
controller has recomputed its comparison, so the status read afterwards reflects the
reverted state. An approach that works then looks like an approach that does nothing.
This cost two wrong fixes on this platform before it was understood. The procedure for
testing safely is in the
[ArgoSyncFailed runbook](../docs/observability/runbooks/argo-sync-failed.md).

*Pinning by SHA needs enforcement.* A pin is only durable if it cannot be a branch, a
tag, or an orphaned commit, and only useful if the images it names exist.
`scripts/validate-gitops-revisions.sh` checks all of that, including querying GHCR,
because a pin to a commit whose release failed renders and validates perfectly and
produces `ImagePullBackOff`.

*Sync-time policy fails after merge.* An `AppProject` whitelist is enforced when Argo CD
syncs, so a manifest can render, validate, and merge, and only then be refused. Loki's
`StatefulSet` did. The response was to move the check earlier:
`scripts/validate-observability.sh` now fails a pull request that renders a kind the
project does not permit.

## Validation

```sh
# No reference to the application repository tracks a branch
bash scripts/validate-gitops-revisions.sh --gitops-dir ../NovaShop-GitOps

# The cluster agrees with Git
kubectl get applications -n argocd     # all Synced/Healthy
```

Drift correction can be demonstrated by scaling a Deployment by hand and watching it
return within three minutes.
