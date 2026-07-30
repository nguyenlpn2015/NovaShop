# Runtime Verification Checklist

Set the target environment:

```bash
export NOVASHOP_ENVIRONMENT=development
export NOVASHOP_APP="novashop-${NOVASHOP_ENVIRONMENT}"
export NOVASHOP_NAMESPACE="novashop-${NOVASHOP_ENVIRONMENT}"
```

## Cluster

- [ ] Kubernetes server is version 1.33 or newer.

  ```bash
  kubectl get --raw=/version
  ```

- [ ] Every node is `Ready`.

  ```bash
  kubectl get nodes -o wide
  ```

## Pods

- [ ] Argo CD pods are running.

  ```bash
  kubectl get pods --namespace argocd
  ```

- [ ] NovaShop pods are `Running` and ready.

  ```bash
  kubectl get pods --namespace "${NOVASHOP_NAMESPACE}" -o wide
  kubectl wait --namespace "${NOVASHOP_NAMESPACE}" \
    --for=condition=Ready pod --all --timeout=5m
  ```

## Services

- [ ] Backend and frontend ClusterIP Services exist.

  ```bash
  kubectl get services --namespace "${NOVASHOP_NAMESPACE}"
  kubectl get endpointslices --namespace "${NOVASHOP_NAMESPACE}"
  ```

## Ingress

- [ ] Traefik is available.

  ```bash
  kubectl -n kube-system rollout status deployment/traefik --timeout=5m
  ```

- [ ] NovaShop Ingress contains frontend and backend routes.

  ```bash
  kubectl get ingress novashop --namespace "${NOVASHOP_NAMESPACE}"
  kubectl describe ingress novashop --namespace "${NOVASHOP_NAMESPACE}"
  ```

- [ ] Development routes return successfully.

  ```bash
  NODE_IP="$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
  curl --fail --resolve "dev.novashop.local:80:${NODE_IP}" \
    http://dev.novashop.local/
  curl --fail --resolve "api.dev.novashop.local:80:${NODE_IP}" \
    http://api.dev.novashop.local/health
  ```

## Helm

Argo CD uses Helm to render manifests and does not create a Helm release.

- [ ] The environment values lint and render successfully.

  ```bash
  helm lint helm/novashop \
    -f ../NovaShop-GitOps/apps/novashop/values/"${NOVASHOP_ENVIRONMENT}".yaml
  helm template novashop helm/novashop \
    -f ../NovaShop-GitOps/apps/novashop/values/"${NOVASHOP_ENVIRONMENT}".yaml \
    >/dev/null
  ```

## Application

- [ ] The root and environment Applications exist.

  ```bash
  kubectl get applications --namespace argocd
  argocd app get novashop-root
  argocd app get "${NOVASHOP_APP}"
  ```

## ApplicationSet

- [ ] The `novashop` ApplicationSet generated three applications.

  ```bash
  kubectl get applicationset novashop --namespace argocd
  kubectl get applications --namespace argocd \
    --selector=app.kubernetes.io/part-of=novashop
  ```

## Argo CD Sync

- [ ] The target application is `Synced` and `Healthy`.

  ```bash
  argocd app wait "${NOVASHOP_APP}" --sync --health --timeout 600
  argocd app get "${NOVASHOP_APP}"
  ```

- [ ] Automatic sync, prune, and self-heal are enabled.

  ```bash
  kubectl get application "${NOVASHOP_APP}" \
    --namespace argocd \
    -o jsonpath='{.spec.syncPolicy.automated}{"\n"}'
  ```

## GHCR Images

- [ ] Pods use immutable GHCR image tags.

  ```bash
  kubectl get pods --namespace "${NOVASHOP_NAMESPACE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
  ```

- [ ] No workload is using `:latest`.

  ```bash
  if kubectl get pods --namespace "${NOVASHOP_NAMESPACE}" \
    -o jsonpath='{.items[*].spec.containers[*].image}' \
    | grep -q ':latest'; then
    echo 'FAIL: mutable image tag detected' >&2
    exit 1
  fi
  ```
