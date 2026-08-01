# Runbook: ArgoSyncFailed

**Severity:** warning · **Fires after:** 30 minutes
**Expression:** `argocd_app_info{sync_status!="Synced"} == 1`

## What it means

An Argo CD Application has not matched Git for half an hour. Automatic sync and
self-heal are enabled on every Application, so anything transient clears in
minutes. Persistence means the sync is *failing*, not merely pending.

Severity is warning rather than critical on purpose: the cluster keeps serving
whatever it last converged to. What is broken is the ability to deploy.

## Diagnose

```sh
sudo k3s kubectl -n argocd get applications
sudo k3s kubectl -n argocd describe application <name> | sed -n '/Conditions/,/Sync Result/p'
sudo k3s kubectl -n argocd logs deploy/argocd-application-controller --tail=100
```

Two states mean different things:

- **OutOfSync** — Argo CD sees a difference and has not applied it.
- **Unknown** — Argo CD cannot render the desired state at all, usually a bad
  revision or an unreachable repository.

## Common causes on this platform

**Resource kind not whitelisted by the AppProject.** The most frequent cause here.
Argo CD refuses to create a kind the AppProject does not permit, and the
Application sits OutOfSync with the offending kind Missing. Loki's `StatefulSet`
hit this. The fix is to add the kind to the AppProject in the GitOps repository —
and `scripts/validate-observability.sh` now fails a pull request that renders a
kind the project does not allow, so this should be caught before merge.

**targetRevision does not exist.** Revisions are pinned to 40-character commit
SHAs. A force-push that orphaned the commit leaves Argo CD unable to fetch it.
`scripts/validate-gitops-revisions.sh` enforces that every pinned SHA is an
ancestor of `origin/main` precisely to prevent this.

**Shared immutable field.** A change to a field Kubernetes will not update in
place, such as a StatefulSet's volumeClaimTemplate. The object must be deleted and
recreated; Argo CD will not do that on its own.

## Fix

Correct the GitOps repository and let the controller converge. To force an
immediate attempt rather than waiting for the poll interval:

```sh
sudo k3s kubectl -n argocd patch application <name> --type merge \
  -p '{"operation":{"initiatedBy":{"username":"runbook"},"sync":{}}}'
```

## Verify

```sh
sudo k3s kubectl -n argocd get applications
```

All twelve Applications should read `Synced` and `Healthy`.
