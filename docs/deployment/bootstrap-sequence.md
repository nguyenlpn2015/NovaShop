# Deployment Target B Bootstrap Sequence

## Flow

```text
Ubuntu Server 22.04
  -> System update and prerequisites
  -> k3s
  -> kubectl and user kubeconfig
  -> Helm 3
  -> Bundled Traefik verification
  -> Argo CD
  -> NovaShop-GitOps
  -> ApplicationSet
  -> NovaShop applications
  -> Validation
```

## 1. Prepare Ubuntu

```bash
sudo apt-get update
sudo apt-get dist-upgrade --yes
sudo apt-get install --yes \
  ca-certificates curl git jq openssh-client tar ufw
sudo timedatectl set-ntp true
sudo swapoff --all
```

Verify:

```bash
grep -E '^(ID|VERSION_ID)=' /etc/os-release
timedatectl show --property=NTPSynchronized --value
ip -4 address show | grep '10.10.1.45/'
test -z "$(swapon --show --noheadings)"
```

Disable any persistent swap entry as described in the
[Ubuntu and k3s Deployment Guide](ubuntu-k3s.md) before continuing.

## 2. Clone Desired Inputs

```bash
mkdir -p "${HOME}/src"
cd "${HOME}/src"
git clone https://github.com/nguyenlpn2015/NovaShop.git
git clone https://github.com/nguyenlpn2015/NovaShop-GitOps.git
cd NovaShop
```

Confirm both default branches are reachable:

```bash
git ls-remote --exit-code \
  https://github.com/nguyenlpn2015/NovaShop.git refs/heads/main
git ls-remote --exit-code \
  https://github.com/nguyenlpn2015/NovaShop-GitOps.git refs/heads/main
```

## 3. Install k3s and kubectl

```bash
export NODE_IP='10.10.1.45'
bash scripts/linux/install-k3s.sh
export KUBECONFIG="${HOME}/.kube/config"
```

Expected result:

- `systemctl is-active k3s` returns `active`;
- the node is `Ready`;
- `kubectl` uses the copied user-scoped kubeconfig;
- the node InternalIP is `10.10.1.45`.

## 4. Install Helm

```bash
bash scripts/linux/install-helm.sh
helm version --short
```

Expected version: `v3.21.1`.

## 5. Verify Traefik

k3s owns the Traefik lifecycle. Do not install a second ingress controller:

```bash
kubectl --namespace kube-system rollout status \
  deployment/traefik --timeout=5m
kubectl --namespace kube-system get \
  deployment,service,pods -l app.kubernetes.io/name=traefik
```

## 6. Install Argo CD

```bash
bash scripts/linux/install-argocd.sh
export PATH="${HOME}/.local/bin:${PATH}"
```

Expected result: all Argo CD Deployments are available and the application
controller StatefulSet is ready.

## 7. Provide Runtime Secrets

The connection strings must reference endpoints reachable from the VM:

```bash
read -rsp 'PostgreSQL URL: ' DATABASE_URL
printf '\n'
read -rsp 'Redis URL: ' REDIS_URL
printf '\n'
export DATABASE_URL REDIS_URL
```

Use environment-specific variables when credentials differ:

```text
DEVELOPMENT_DATABASE_URL
DEVELOPMENT_REDIS_URL
STAGING_DATABASE_URL
STAGING_REDIS_URL
PRODUCTION_DATABASE_URL
PRODUCTION_REDIS_URL
```

## 8. Bootstrap GitOps

```bash
bash scripts/bootstrap.sh
unset DATABASE_URL REDIS_URL
```

The script applies only the NovaShop AppProject and root Application. Argo CD
then reads `NovaShop-GitOps`, creates the ApplicationSet, and reconciles the
three environments.

## 9. Validate

```bash
bash scripts/linux/verify.sh
```

Successful completion requires:

- node `Ready`;
- Traefik and Argo CD available;
- all backend and frontend Deployments available;
- every NovaShop Application `Synced` and `Healthy`.

## One-Command Orchestration

After reviewing the individual stages, a clean VM can run the orchestration
entry point:

```bash
export NODE_IP='10.10.1.45'
export CONFIGURE_HOSTNAME='true'
export ENABLE_UFW='true'
export MANAGEMENT_CIDR='10.10.1.0/24'

read -rsp 'PostgreSQL URL: ' DATABASE_URL
printf '\n'
read -rsp 'Redis URL: ' REDIS_URL
printf '\n'
export DATABASE_URL REDIS_URL

bash scripts/linux/bootstrap.sh
unset DATABASE_URL REDIS_URL
```
