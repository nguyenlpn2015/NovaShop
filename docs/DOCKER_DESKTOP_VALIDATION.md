# Docker Desktop Runtime Validation

Run from PowerShell with the `docker-desktop` context.

## Cluster and Platform

```powershell
kubectl config current-context
kubectl get nodes -o wide
kubectl get namespaces
kubectl get pods -A -o wide
kubectl get services -A
kubectl get ingress -A
```

Expected:

- Context is `docker-desktop`.
- Every node is `Ready`.
- Argo CD and Traefik Pods are ready.
- NovaShop environment namespaces exist.

## Argo CD

```powershell
kubectl get applications -n argocd
kubectl get applicationsets -n argocd
kubectl describe application novashop-root -n argocd
kubectl describe application novashop-development -n argocd
kubectl describe applicationset novashop -n argocd

argocd app list
argocd app get novashop-root
argocd app get novashop-development
argocd app wait novashop-development --sync --health --timeout 600
```

The deployed application is named `novashop-development`; there is no
standalone `Application` named `novashop`.

Verify automatic sync controls:

```powershell
kubectl get application novashop-development -n argocd `
  -o jsonpath='{.spec.syncPolicy.automated}{"`n"}'
```

Expected fields:

- `enabled: true`
- `prune: true`
- `selfHeal: true`

## Workloads and Services

```powershell
$Namespace = 'novashop-development'

kubectl get deployments,pods,services,ingress -n $Namespace
kubectl wait --for=condition=Available deployment --all `
  -n $Namespace `
  --timeout=10m
kubectl wait --for=condition=Ready pod --all `
  -n $Namespace `
  --timeout=10m
```

Verify immutable GHCR images:

```powershell
kubectl get pods -n $Namespace `
  -o jsonpath='{range .items[*]}{.metadata.name}{"`t"}{.spec.containers[*].image}{"`n"}{end}'
```

No image may use `:latest`.

## Helm Rendering

Argo CD uses Helm to render manifests and does not create a Helm release for
NovaShop.

```powershell
helm lint .\helm\novashop `
  -f ..\NovaShop-GitOps\apps\novashop\values\development.yaml

helm template novashop .\helm\novashop `
  -f ..\NovaShop-GitOps\apps\novashop\values\development.yaml |
  Out-Null

helm list -n traefik
```

## Ingress and Browser

```powershell
kubectl get ingressclass
kubectl describe ingress novashop -n $Namespace
kubectl get service traefik -n traefik -o wide

curl.exe --fail http://dev.novashop.local/
curl.exe --fail http://api.dev.novashop.local/health
```

Expected:

- Frontend returns HTTP 200.
- Backend `/health` returns HTTP 200 with healthy status.

## Logs

```powershell
kubectl logs deployment/novashop-backend `
  -n $Namespace `
  --all-containers `
  --tail=200

kubectl logs deployment/novashop-frontend `
  -n $Namespace `
  --all-containers `
  --tail=200

kubectl logs deployment/argocd-repo-server `
  -n argocd `
  --tail=200

kubectl logs deployment/traefik `
  -n traefik `
  --tail=200
```

## Events

```powershell
kubectl get events -A --sort-by='.lastTimestamp'
```

No unresolved warning event may remain for the deployed NovaShop workloads.
