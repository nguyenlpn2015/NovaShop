# Runbook: DeploymentFailed

**Severity:** critical · **Fires after:** 10 minutes
**Expression:** `kube_deployment_status_replicas_available < kube_deployment_spec_replicas`

## What it means

A Deployment has fewer ready replicas than it wants, and has for ten minutes. A
normal rolling update resolves well inside that window.

## Diagnose

```sh
NS=novashop-production
D=<deployment>
sudo k3s kubectl -n $NS rollout status deploy/$D --timeout=10s
sudo k3s kubectl -n $NS describe deploy/$D | tail -20
sudo k3s kubectl -n $NS get pods -l app.kubernetes.io/name=$D
```

The pod state identifies which of four faults this is:

| Pod state | Cause | Go to |
|---|---|---|
| `Pending` | No node has room | [MemoryHigh](memory-high.md) |
| `ImagePullBackOff` | Tag missing from GHCR, or auth failed | below |
| `CrashLoopBackOff` | Container dies on start | [PodCrashLooping](pod-crashlooping.md) |
| `Running`, not ready | Readiness probe failing | below |

## ImagePullBackOff

The GitOps repository pins image tags to commit SHAs, and
`scripts/validate-gitops-revisions.sh` verifies each tag exists in GHCR before a
GitOps pull request can merge. A pull failing anyway means the package visibility
changed or the tag was deleted after merge.

```sh
sudo k3s kubectl -n $NS describe pod <pod> | grep -A3 Failed
```

## Readiness failing

The backend's `/ready` probe checks PostgreSQL and Redis and returns 503 when
either is unreachable. That is deliberate — the pod is honestly reporting it
cannot serve. Rule out [DatabaseDown](database-down.md) and
[RedisDown](redis-down.md) before touching the deployment.

## Fix

Roll back through Git: revert the GitOps commit that changed the image tag and let
Argo CD converge. Do not use `kubectl rollout undo` — self-heal restores the Git
state within three minutes and undoes your undo.
