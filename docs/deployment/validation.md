# Deployment Target B Validation

Run validation from the NovaShop repository on `10.10.1.45`:

```bash
export KUBECONFIG="${HOME}/.kube/config"
export PATH="${HOME}/.local/bin:${PATH}"
bash scripts/linux/verify.sh
```

## Platform

```bash
cat /etc/os-release
hostnamectl
timedatectl status
ip -brief -4 address
sudo systemctl is-active k3s
kubectl version
kubectl cluster-info
kubectl get nodes -o wide
```

Pass criteria:

- Ubuntu is `22.04`;
- time synchronization is active;
- k3s is `active`;
- the node InternalIP is `10.10.1.45`;
- every node is `Ready`.

## Kubernetes Resources

```bash
kubectl get namespaces
kubectl get pods --all-namespaces -o wide
kubectl get services --all-namespaces
kubectl get ingress --all-namespaces
kubectl get events --all-namespaces \
  --sort-by='.metadata.creationTimestamp'
```

Pass criteria:

- all expected containers are ready;
- no pod is in `Pending`, `CrashLoopBackOff`, or `ImagePullBackOff`;
- Traefik exposes ports `80` and `443`;
- NovaShop Ingress objects have an address.

## Helm and Traefik

```bash
helm version --short
helm list --all-namespaces
kubectl --namespace kube-system rollout status \
  deployment/traefik --timeout=5m
kubectl --namespace kube-system get \
  deployment,service,pods -l app.kubernetes.io/name=traefik
```

k3s manages Traefik through its bundled Helm controller, so it may appear as a
`HelmChart` rather than a release owned by the operator's Helm client:

```bash
kubectl get helmcharts.helm.cattle.io --namespace kube-system
```

## Argo CD and GitOps

```bash
kubectl get applications --namespace argocd
kubectl get applicationsets --namespace argocd
kubectl describe application novashop-root --namespace argocd
argocd app list
argocd app get novashop-root --hard-refresh
```

Pass criteria:

- `novashop-root`, `novashop-development`, `novashop-staging`, and
  `novashop-production` are `Synced` and `Healthy`;
- ApplicationSet `novashop` exists;
- the root and generated Applications have no repository comparison error.

## Workload Images

```bash
kubectl get deployments \
  --all-namespaces \
  --selector=app.kubernetes.io/part-of=novashop \
  --output=custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image'
```

Confirm all environments use the reviewed immutable GHCR commit tag.

## Metrics

```bash
kubectl top nodes
kubectl top pods --all-namespaces
kubectl --namespace kube-system get deployment metrics-server
```

If metrics are initially unavailable:

```bash
kubectl --namespace kube-system rollout status \
  deployment/metrics-server --timeout=5m
kubectl get apiservice v1beta1.metrics.k8s.io
```

## Ingress and Application

```bash
curl --fail --show-error \
  --resolve dev.novashop.local:80:10.10.1.45 \
  http://dev.novashop.local/

curl --fail --show-error \
  --resolve api.dev.novashop.local:80:10.10.1.45 \
  http://api.dev.novashop.local/health
```

Expected backend response:

```json
{"status":"healthy","service":"NovaShop API","version":"0.1.0"}
```

## Final Checklist

- [ ] Server preparation completed.
- [ ] k3s service active.
- [ ] Node `Ready` at `10.10.1.45`.
- [ ] Helm client version pinned.
- [ ] Traefik available.
- [ ] Argo CD control plane available.
- [ ] GitOps repositories reachable.
- [ ] ApplicationSet created all environments.
- [ ] All Applications `Synced`.
- [ ] All Applications `Healthy`.
- [ ] Pods ready with zero unexpected restarts.
- [ ] Immutable GHCR image tags deployed.
- [ ] Frontend returns HTTP `200`.
- [ ] Backend health returns HTTP `200`.
- [ ] Node and pod metrics available.
