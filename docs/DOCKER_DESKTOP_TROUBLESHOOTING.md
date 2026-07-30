# Docker Desktop GitOps Troubleshooting

## Pending Pods

```powershell
kubectl get pods -A -o wide
kubectl describe pod <pod-name> -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

Check resource pressure, PVC binding, node selectors, taints, and missing
Secrets. Increase Docker Desktop CPU or memory only when events show resource
pressure.

## ImagePullBackOff

```powershell
kubectl describe pod <pod-name> -n <namespace>
kubectl get pod <pod-name> -n <namespace> `
  -o jsonpath='{.spec.containers[*].image}'
```

Confirm the exact Git SHA tag exists in GHCR. Public packages need no pull
Secret. For a private package, create a namespace-scoped GHCR credential
outside Git and reference it through the platform.

## CrashLoopBackOff

```powershell
kubectl logs <pod-name> -n <namespace> --all-containers --previous
kubectl describe pod <pod-name> -n <namespace>
kubectl get secret -n <namespace>
```

Validate environment configuration, runtime Secret names, container user
permissions, and probe failures.

## Ingress Unavailable

```powershell
kubectl get pods,services -n traefik
kubectl get ingressclass
kubectl describe ingress novashop -n novashop-development
kubectl logs deployment/traefik -n traefik --tail=200
Test-NetConnection localhost -Port 80
```

Confirm the hosts file maps both development hostnames to `127.0.0.1`.

## Repository Authentication

```powershell
argocd repo list
argocd repo get https://github.com/nguyenlpn2015/NovaShop-GitOps.git
kubectl logs deployment/argocd-repo-server -n argocd --tail=200
```

For public repositories, re-register anonymous HTTPS:

```powershell
argocd repo add https://github.com/nguyenlpn2015/NovaShop-GitOps.git `
  --name novashop-gitops `
  --project novashop `
  --upsert
```

## Application OutOfSync

```powershell
argocd app diff novashop-development
argocd app get novashop-development --refresh
argocd app sync novashop-development
argocd app wait novashop-development --sync --health --timeout 600
```

Do not patch managed resources directly.

## Application Degraded

```powershell
argocd app get novashop-development --show-operation
kubectl describe application novashop-development -n argocd
kubectl get pods -n novashop-development
kubectl get events -n novashop-development --sort-by='.lastTimestamp'
```

Resolve the unhealthy Kubernetes resource, then refresh Argo CD. Roll back by
reverting the failed `NovaShop-GitOps` commit.

## Docker Desktop Context Missing

```powershell
docker desktop kubernetes status
kubectl config get-contexts
```

Start the cluster from Docker Desktop > Kubernetes and wait for the
`docker-desktop` context. Do not substitute another cluster context.
