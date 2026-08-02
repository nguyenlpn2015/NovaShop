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

**A field the server-side apply dry-run cannot predict.** The subtlest of the four,
and the one that looks most like a bug in Argo CD.

When an Application syncs with `ServerSideApply`, the comparison that decides sync
status is **not** the desired manifest against the live object. It is a server-side
apply *dry-run* against the live object. If Kubernetes adds a field that the
dry-run does not reproduce, that field exists in live, is missing from the
prediction, and never converges: the sync reports Succeeded, self-heal reapplies,
and the difference survives every attempt.

The Alertmanager StatefulSet does this. Kubernetes fills in `apiVersion` and
`kind` on a `volumeClaimTemplate`; the dry-run does not. Loki is the control that
proves the mechanism — same shape, same `syncOptions`, same two fields live, and
Synced, because the Loki chart templates that TypeMeta explicitly while the
prometheus chart does not.

`ignoreDifferences` on the two paths is the fix. It is in the Application in the
GitOps repository.

## The inverse problem: Synced and Healthy, and the work never ran

Not every failure shows as OutOfSync. This one shows as nothing at all, and it is the
reason the migration Job is worth understanding before you need it.

**Hooks are not part of the desired state.** A resource annotated
`argocd.argoproj.io/hook: PreSync` is not compared, is not reported in
`status.resources`, and does not create drift. It is *executed* during a sync
operation and nowhere else.

Two consequences, both observed on this platform when the schema first shipped:

**Enabling a hook does not trigger a sync.** Flipping `migrations.enabled` from
`false` to `true` changed only a resource that Argo CD does not diff. There was
no drift, so automated sync had nothing to do, so the hook never ran. Staging and
production sat Synced and Healthy for as long as it took to notice, with entirely
empty databases behind them.

**A failing hook is retried before it is fatal.** The first attempt in development
failed with `permission denied for schema public`, and the Application still
reported Synced and Healthy while the retry backed off.

Neither is a bug. Both mean the same thing: **the Application's status does not
tell you whether the migration ran.** Ask the database.

```sh
kubectl -n novashop-<env> get job novashop-migrate
kubectl -n novashop-<env> logs job/novashop-migrate

sudo -u postgres psql -d novashop_<env> -tAc \
  "SELECT version_num FROM alembic_version"
```

To make a hook run when nothing else changed, trigger a sync explicitly:

```sh
kubectl -n argocd patch application novashop-<env> --type merge \
  -p '{"operation":{"initiatedBy":{"username":"operator"},"sync":{}}}'
```

`ttlSecondsAfterFinished` is 3600, so a Job that completed more than an hour ago
has been collected and `kubectl get job` returns nothing. Absence of a Job is not
evidence that one never ran — check `alembic_version`.

## Diff the right pair of states

This is the part that costs hours if you get it wrong. Under `ServerSideApply`,
`helm template | diff` — desired against live — is **not** the comparison Argo CD
uses, and it can report zero differences on an Application that is OutOfSync:

```
target    vs normalizedLive   0 differences
predicted vs normalizedLive   2 differences   <- this decides sync status
```

Reading the wrong pair on this platform produced two consecutive wrong fixes, one
of which changed a runtime setting that was never involved.

Read all four states from the API:

```sh
SIP=$(sudo k3s kubectl -n argocd get svc argocd-server -o jsonpath='{.spec.clusterIP}')
PW=$(sudo k3s kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)
TOKEN=$(curl -sk "https://${SIP}/api/v1/session" -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"${PW}\"}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://${SIP}/api/v1/applications/<app>/managed-resources"
```

Compare **`predictedLiveState` against `normalizedLiveState`**. Any field differing
between those two is a real difference; anything that differs only between
`targetState` and the live object is almost always a server default that Argo CD
already ignores. Add the differing paths to `ignoreDifferences` on the Application.

## Testing a fix against a live Application

Every Application here is managed by `novashop-root` with `selfHeal` enabled, so a
`kubectl patch` is reverted within about three minutes — usually before the
comparison has been recomputed. A patch that appears to change nothing has very
likely just been reverted.

Pause self-heal for the duration, and restore it immediately afterwards:

```sh
sudo k3s kubectl -n argocd patch application novashop-root --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false}}}}'

# ... patch the child Application, annotate refresh=hard, wait, read status ...

sudo k3s kubectl -n argocd patch application novashop-root --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}'
```

An inconclusive experiment is not a negative result. Reading "unchanged" from a
reverted patch is how a working fix gets discarded.

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
