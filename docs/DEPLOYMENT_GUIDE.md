# NovaShop Deployment Guide

This guide bootstraps NovaShop on a clean single-node k3s cluster. Commands are
written for a modern Linux host or WSL with `systemd`.

## Supported Baseline

| Component | Version |
|-----------|---------|
| Kubernetes | 1.33+ |
| k3s | `v1.33.13+k3s1` |
| Helm | `v3.21.1` |
| Argo CD | `v3.4.4` |

## Prerequisites

- Linux `amd64` or `arm64`.
- At least 2 CPU cores, 4 GB RAM, and 20 GB SSD storage.
- `sudo`, `curl`, `git`, `sha256sum`, and outbound HTTPS access.
- TCP ports `80`, `443`, and `6443` available.
- Public GHCR access to both NovaShop images.
- Reachable PostgreSQL and Redis endpoints.
- The `NovaShop` and `NovaShop-GitOps` repositories published at their
  configured GitHub URLs with a `main` branch.

Clone both repositories as siblings:

```bash
git clone https://github.com/nguyenlpn2015/NovaShop.git
git clone https://github.com/nguyenlpn2015/NovaShop-GitOps.git
cd NovaShop
```

## Install k3s

The installation is pinned and keeps the bundled Traefik ingress controller.

```bash
if ! command -v k3s >/dev/null 2>&1; then
  K3S_INSTALLER="$(mktemp)"
  curl -sfL https://get.k3s.io -o "${K3S_INSTALLER}"
  sudo env INSTALL_K3S_VERSION='v1.33.13+k3s1' sh "${K3S_INSTALLER}"
  rm -f "${K3S_INSTALLER}"
fi
```

Create a user-scoped kubeconfig:

```bash
mkdir -p "${HOME}/.kube"
sudo install -o "$(id -u)" -g "$(id -g)" -m 0600 \
  /etc/rancher/k3s/k3s.yaml "${HOME}/.kube/config"
export KUBECONFIG="${HOME}/.kube/config"
```

## Verify the Cluster

```bash
sudo systemctl is-active --quiet k3s
kubectl cluster-info
kubectl wait --for=condition=Ready node --all --timeout=5m
kubectl get nodes -o wide
kubectl -n kube-system rollout status deployment/traefik --timeout=5m
```

Confirm the server minor version is at least `33`:

```bash
kubectl get --raw=/version
```

## Install kubectl

k3s installs a compatible `kubectl` automatically. For a separate Linux
workstation, install the client that matches the cluster:

```bash
KUBECTL_VERSION='v1.33.13'
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64) KUBECTL_ARCH='amd64' ;;
  aarch64 | arm64) KUBECTL_ARCH='arm64' ;;
  *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac

curl -fLO \
  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl"
curl -fLO \
  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl kubectl.sha256
kubectl version --client
```

## Install Helm

Use the official Helm 3 installer with a pinned version:

```bash
if ! helm version --short 2>/dev/null | grep -q 'v3.21.1'; then
  HELM_INSTALLER="$(mktemp)"
  curl -fsSL \
    https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    -o "${HELM_INSTALLER}"
  chmod 0700 "${HELM_INSTALLER}"
  DESIRED_VERSION='v3.21.1' "${HELM_INSTALLER}"
  rm -f "${HELM_INSTALLER}"
fi

helm version --short
```

## Install Argo CD

The installer uses the official pinned manifest, server-side apply, checksum
verification for the CLI, and rollout waits:

```bash
bash scripts/install-argocd.sh
export PATH="${HOME}/.local/bin:${PATH}"
argocd version --client
```

Re-running the installer reconciles the same version safely.

## Bootstrap Argo CD

Provide reachable connection URLs. Input is hidden and values are written
directly to Kubernetes Secrets, never to Git:

```bash
read -rsp 'PostgreSQL URL: ' DATABASE_URL
echo
read -rsp 'Redis URL: ' REDIS_URL
echo
export DATABASE_URL REDIS_URL

bash scripts/bootstrap.sh
unset DATABASE_URL REDIS_URL
```

For isolated credentials, set
`DEVELOPMENT_DATABASE_URL`, `STAGING_DATABASE_URL`,
`PRODUCTION_DATABASE_URL` and the matching `*_REDIS_URL` variables instead.

The bootstrap creates or reconciles:

- the Argo CD installation;
- the NovaShop `AppProject`;
- the root `Application`;
- the `ApplicationSet`;
- development, staging, and production `Application` resources;
- runtime Secrets in each environment namespace.

## Login

Start the port forward in a dedicated terminal:

```bash
bash scripts/port-forward.sh
```

In another terminal:

```bash
export PATH="${HOME}/.local/bin:${PATH}"
INITIAL_PASSWORD="$(argocd admin initial-password -n argocd)"

argocd login localhost:8080 \
  --username admin \
  --password "${INITIAL_PASSWORD}" \
  --insecure
```

Open <https://localhost:8080> and accept the local self-signed certificate.

## Change the Admin Password

```bash
argocd account update-password
kubectl delete secret argocd-initial-admin-secret \
  --namespace argocd \
  --ignore-not-found
unset INITIAL_PASSWORD
```

Use a password manager. For a shared environment, replace the local admin
workflow with SSO and disable the built-in admin account.

## Access NovaShop

Get the k3s node address:

```bash
NODE_IP="$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
echo "${NODE_IP}"
```

Add the development hosts on the machine running the browser:

```text
<NODE_IP> dev.novashop.local api.dev.novashop.local
```

Then open:

- `http://dev.novashop.local`
- `http://api.dev.novashop.local/health`

Staging and production hostnames require real DNS and TLS Secrets.

## Verify Installation

```bash
kubectl get pods --all-namespaces
kubectl get applications,applicationsets --namespace argocd
argocd app list
argocd app get novashop-development
```

Complete [Verification Checklist](VERIFICATION_CHECKLIST.md) before declaring
the runtime ready.

## Official References

- [k3s Quick Start](https://docs.k3s.io/quick-start)
- [k3s 1.33 release notes](https://docs.k3s.io/release-notes/v1.33.X)
- [kubectl installation](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
- [Helm 3 installation](https://v3.helm.sh/docs/intro/install/)
- [Argo CD installation](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [Argo CD v3.4.4 release](https://github.com/argoproj/argo-cd/releases/tag/v3.4.4)
