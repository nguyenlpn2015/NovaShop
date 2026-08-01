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

**A chart sending a field's default value.** The subtlest of the four, and the one
that looks most like a bug in Argo CD. If a chart templates a field explicitly at
the value Kubernetes treats as its default, the API server stores nothing and
reads the field back absent. Argo CD then compares a desired field against a live
object that does not have it and can never converge: the sync succeeds, self-heal
reapplies, and the difference survives.

The Alertmanager StatefulSet did this with `minReadySeconds: 0`.

`ignoreDifferences` does **not** fix this, which is worth knowing before spending
an afternoon on it. Its normalizer removes the path from the live state, where the
path is already absent, so it does nothing; the target keeps the field. Confirm by
reading all four states from the API rather than guessing:

```sh
SIP=$(sudo k3s kubectl -n argocd get svc argocd-server -o jsonpath='{.spec.clusterIP}')
PW=$(sudo k3s kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)
TOKEN=$(curl -sk "https://${SIP}/api/v1/session" -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"${PW}\"}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://${SIP}/api/v1/applications/<app>/managed-resources"
```

Compare `targetState` against `normalizedLiveState`. Anything showing `target:
<absent>` is a server default and Argo CD ignores it; a field with a value in the
target and absent in the live state is the real difference. `predictedLiveState`
is a server-side apply dry-run, so if the field is missing there too, applying the
target will not produce it and no amount of re-syncing will help.

The fix is to make the field round-trip: set it to a value that is not the API
default. See the comment on `minReadySeconds` in
`kubernetes/observability/prometheus/alerting-values.yaml`.

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
