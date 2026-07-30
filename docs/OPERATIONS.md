# NovaShop Operations

## Environment Map

| Environment | Argo CD Application | Namespace |
|-------------|---------------------|-----------|
| Development | `novashop-development` | `novashop-development` |
| Staging | `novashop-staging` | `novashop-staging` |
| Production | `novashop-production` | `novashop-production` |

Set the target once per session:

```bash
export NOVASHOP_ENVIRONMENT=development
export NOVASHOP_APP="novashop-${NOVASHOP_ENVIRONMENT}"
export NOVASHOP_NAMESPACE="novashop-${NOVASHOP_ENVIRONMENT}"
```

## Deploy

1. Update the target values file in `NovaShop-GitOps`.
2. Use the immutable GHCR tag produced by the NovaShop release workflow.
3. Validate, open a pull request, and merge after review.
4. Watch reconciliation:

```bash
argocd app wait "${NOVASHOP_APP}" \
  --sync \
  --health \
  --timeout 600
```

Do not deploy the application with `kubectl apply` or `helm install`.

## Update

Change both image tags in:

```text
NovaShop-GitOps/apps/novashop/values/<environment>.yaml
```

Validate before opening the pull request:

```bash
RENDERED_MANIFEST="$(mktemp)"
helm lint helm/novashop \
  -f ../NovaShop-GitOps/apps/novashop/values/"${NOVASHOP_ENVIRONMENT}".yaml

helm template novashop helm/novashop \
  -f ../NovaShop-GitOps/apps/novashop/values/"${NOVASHOP_ENVIRONMENT}".yaml \
  >"${RENDERED_MANIFEST}"

kubectl apply --dry-run=server -f "${RENDERED_MANIFEST}"
rm -f "${RENDERED_MANIFEST}"
```

## Rollback

Preferred rollback:

```bash
cd ../NovaShop-GitOps
git log --oneline -- apps/novashop/values/"${NOVASHOP_ENVIRONMENT}".yaml
git revert <failed-gitops-commit>
git push origin HEAD
```

After review and merge, wait for health:

```bash
argocd app wait "${NOVASHOP_APP}" --sync --health --timeout 600
```

Emergency rollback:

```bash
argocd app history "${NOVASHOP_APP}"
argocd app rollback "${NOVASHOP_APP}" <history-id>
```

Immediately commit the restored image revision to `NovaShop-GitOps`; otherwise
self-heal may restore the failed desired state.

## Restart

Use only for runtime recovery when desired state is unchanged:

```bash
kubectl rollout restart deployment/novashop-backend \
  deployment/novashop-frontend \
  --namespace "${NOVASHOP_NAMESPACE}"

kubectl rollout status deployment/novashop-backend \
  --namespace "${NOVASHOP_NAMESPACE}" \
  --timeout=5m
kubectl rollout status deployment/novashop-frontend \
  --namespace "${NOVASHOP_NAMESPACE}" \
  --timeout=5m
```

## Scale

Update `backend.replicaCount` or `frontend.replicaCount` in the environment
values file and merge through the normal GitOps pull request. Do not use
`kubectl scale`; Argo CD self-heal will restore the Git value.

Verify:

```bash
kubectl get deployment --namespace "${NOVASHOP_NAMESPACE}"
```

## Sync

Automatic sync is enabled. To request an immediate reconciliation:

```bash
argocd app get "${NOVASHOP_APP}" --refresh
argocd app sync "${NOVASHOP_APP}"
argocd app wait "${NOVASHOP_APP}" --sync --health --timeout 600
```

Inspect differences before syncing:

```bash
argocd app diff "${NOVASHOP_APP}"
```

## Delete

For an environment decommission, remove its element from the `ApplicationSet`
through a reviewed GitOps pull request.

For complete local runtime teardown:

```bash
bash scripts/cleanup.sh --confirm
```

To remove NovaShop and the Argo CD installation:

```bash
bash scripts/cleanup.sh --confirm --include-argocd
```

The cleanup script does not uninstall k3s.

## Recover

Reconcile the runtime safely:

```bash
bash scripts/install-argocd.sh
bash scripts/bootstrap.sh
argocd app get "${NOVASHOP_APP}" --hard-refresh
argocd app sync "${NOVASHOP_APP}"
argocd app wait "${NOVASHOP_APP}" --sync --health --timeout 600
```

If a runtime Secret was lost, export the appropriate database and Redis URLs
and re-run `scripts/bootstrap.sh`.

## Troubleshooting

### Application is OutOfSync

```bash
argocd app diff "${NOVASHOP_APP}"
argocd app get "${NOVASHOP_APP}" --show-operation
kubectl get events --namespace "${NOVASHOP_NAMESPACE}" \
  --sort-by='.lastTimestamp'
```

### Pods are Pending or Restarting

```bash
kubectl get pods --namespace "${NOVASHOP_NAMESPACE}" -o wide
kubectl describe pods --namespace "${NOVASHOP_NAMESPACE}"
kubectl logs --namespace "${NOVASHOP_NAMESPACE}" \
  deployment/novashop-backend --all-containers --tail=200
kubectl logs --namespace "${NOVASHOP_NAMESPACE}" \
  deployment/novashop-frontend --all-containers --tail=200
```

### Image Pull Fails

```bash
kubectl get pods --namespace "${NOVASHOP_NAMESPACE}" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
kubectl describe pods --namespace "${NOVASHOP_NAMESPACE}" \
  | grep -A5 -E 'ErrImagePull|ImagePullBackOff'
```

Confirm the Git SHA tag exists in GHCR and that packages are public. Private
packages require a namespace-scoped registry credential managed outside Git.

### Ingress Does Not Route

```bash
kubectl -n kube-system get deployment,service,pods -l app.kubernetes.io/name=traefik
kubectl get ingress --namespace "${NOVASHOP_NAMESPACE}"
kubectl describe ingress novashop --namespace "${NOVASHOP_NAMESPACE}"
```

### Argo CD is Unavailable

```bash
kubectl get pods --namespace argocd
kubectl logs --namespace argocd deployment/argocd-server --tail=200
kubectl logs --namespace argocd deployment/argocd-repo-server --tail=200
bash scripts/port-forward.sh
```
