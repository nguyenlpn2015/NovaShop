# Operations

Everything needed to run this platform, in the order you are likely to need it.

## Guides

| Guide | Use when |
|---|---|
| [Local Development](local-development.md) | Running the application on your own machine |
| [Production Deployment](production-deployment.md) | Building the platform on a real node |
| [Observability](observability-guide.md) | Reading metrics, logs, dashboards, and alerts |
| [Troubleshooting](troubleshooting.md) | Something is wrong and you do not yet know what |
| [Platform Upgrade](platform-upgrade.md) | Moving k3s, Argo CD, or a chart to a new version |
| [Disaster Recovery](../recovery/disaster-recovery.md) | The node is gone |

## Reference

| Document | Contains |
|---|---|
| [Day-2 operations](../OPERATIONS.md) | Deploy, update, rollback, scale, sync, back up, by task |
| [Target operations](../deployment/operations.md) | k3s, Helm, and Argo CD upgrades; credential rotation |
| [Ubuntu + k3s deployment](../deployment/ubuntu-k3s.md) | Server preparation in detail |
| [Bootstrap sequence](../deployment/bootstrap-sequence.md) | What bootstrap does, step by step |
| [Verification checklist](../VERIFICATION_CHECKLIST.md) | Proving the platform is healthy |
| [Runbooks](../observability/runbooks/) | One per alert, 14 of them |

## Two rules that will save you time

**Fix it in Git, not on the cluster.** Every Application has `selfHeal: true`, so a
`kubectl edit` is reverted within about three minutes. This is also true when you are
debugging: a patch used to test a hypothesis is undone, usually before Argo CD has recomputed
its comparison, so the status you read afterwards reflects the reverted state. An approach
that works can look like an approach that does nothing. The procedure for testing safely —
pausing root's self-heal and restoring it — is in the
[ArgoSyncFailed runbook](../observability/runbooks/argo-sync-failed.md).

**Start from the status code.** For anything user-facing, the HTTP status narrows a
whole-stack problem to one layer before you touch a log. The table is in
[Networking](../architecture/networking.md#where-a-request-can-die) and repeated in
[Troubleshooting](troubleshooting.md).

## The one node

There is one node. A node fault is a total outage and there is nowhere for a pod to move.
Recovery is a rehearsed procedure rather than an assumption about redundancy, and
[Disaster Recovery](../recovery/disaster-recovery.md) is the document that matters most in
this directory even though it is the one you will read least.
