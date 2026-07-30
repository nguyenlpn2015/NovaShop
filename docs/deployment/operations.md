# Deployment Target B Operations

These procedures cover the Ubuntu Server and k3s platform lifecycle. Use the
existing [NovaShop Operations](../OPERATIONS.md) for application deployment,
promotion, synchronization, and GitOps rollback.

## Cluster Startup

```bash
sudo systemctl start k3s
sudo systemctl is-active k3s
kubectl wait --for=condition=Ready node --all --timeout=5m
bash scripts/linux/verify.sh
```

## Cluster Shutdown

Drain is unnecessary for a planned shutdown of this single-node lab because
there is no second scheduling target. Stop workloads and containerd cleanly:

```bash
sudo /usr/local/bin/k3s-killall.sh
sudo systemctl stop k3s
sudo systemctl is-active k3s
sudo systemctl poweroff
```

Use the virtualization console to confirm the VM is powered off before storage
or hypervisor maintenance.

## Cluster Restart

```bash
sudo systemctl restart k3s
sudo journalctl --unit=k3s --since='5 minutes ago' --no-pager
kubectl wait --for=condition=Ready node --all --timeout=5m
bash scripts/linux/verify.sh
```

## Upgrade k3s

1. Read the target release notes.
2. Back up k3s and take a VM snapshot.
3. Pin the reviewed target explicitly.
4. Reconcile using the installer guard:

```bash
export K3S_VERSION='v1.33.13+k3s1'
export NODE_IP='10.10.1.45'
export ALLOW_K3S_UPGRADE='true'
bash scripts/linux/install-k3s.sh
unset ALLOW_K3S_UPGRADE
```

Verify node, bundled components, Traefik, metrics-server, Argo CD, and all
NovaShop applications before deleting the pre-upgrade snapshot.

## Upgrade Helm

Helm is a client and has no in-cluster controller:

```bash
export HELM_VERSION='v3.21.1'
bash scripts/linux/install-helm.sh
helm version --short
helm list --all-namespaces
```

Do not change the default version until the repository baseline has been
reviewed and updated.

## Upgrade Argo CD

1. Review release notes and supported Kubernetes versions.
2. Update the pinned `ARGOCD_VERSION` through a pull request.
3. Reconcile and validate:

```bash
export ARGOCD_VERSION='v3.4.4'
bash scripts/linux/install-argocd.sh
kubectl get pods --namespace argocd
kubectl get applications --namespace argocd
```

Never use an unpinned `stable` manifest URL.

## Scale

Change `backend.replicaCount` or `frontend.replicaCount` in the environment
values file in `NovaShop-GitOps`. Merge through review and let Argo CD apply
the desired state.

```bash
kubectl get deployments --namespace novashop-development
argocd app wait novashop-development --sync --health --timeout 600
```

Manual `kubectl scale` changes are drift and will be self-healed.

## Rollback

Revert the failed GitOps commit:

```bash
cd "${HOME}/src/NovaShop-GitOps"
git log --oneline -- apps/novashop/values/development.yaml
git revert <failed-commit>
git push origin HEAD
```

Open and merge the rollback pull request, then verify:

```bash
argocd app wait novashop-development --sync --health --timeout 600
```

Use Argo CD history rollback only for incident containment, followed
immediately by an equivalent Git revert.

## Backup

The single-node default datastore is SQLite. Schedule a quiesced backup of the
server database, token, and configuration to storage outside the VM:

```bash
BACKUP_DIRECTORY="/srv/backups/k3s/$(date -u +%Y%m%dT%H%M%SZ)"
sudo install -d -m 0700 "${BACKUP_DIRECTORY}"

sudo systemctl stop k3s
sudo cp -a /var/lib/rancher/k3s/server/db "${BACKUP_DIRECTORY}/db"
sudo cp -a /var/lib/rancher/k3s/server/token "${BACKUP_DIRECTORY}/token"
sudo cp -a /etc/rancher/k3s "${BACKUP_DIRECTORY}/etc-rancher-k3s"
sudo systemctl start k3s

sudo tar --create --gzip \
  --file="${BACKUP_DIRECTORY}.tar.gz" \
  --directory="$(dirname "${BACKUP_DIRECTORY}")" \
  "$(basename "${BACKUP_DIRECTORY}")"
sudo sha256sum "${BACKUP_DIRECTORY}.tar.gz" \
  | sudo tee "${BACKUP_DIRECTORY}.tar.gz.sha256"
```

Database and Redis backups are separate responsibilities and must be tested
with their own recovery procedures.

## Restore

Perform restore only during an approved recovery window:

1. Provision the same Ubuntu and k3s version.
2. Stop k3s.
3. Verify the backup checksum.
4. Restore the saved database, token, and k3s configuration with original
   ownership and permissions.
5. Start k3s and run validation.

```bash
sudo sha256sum --check <backup>.tar.gz.sha256
sudo systemctl stop k3s
sudo tar --extract --gzip --file=<backup>.tar.gz --directory=/srv/backups/k3s
sudo rsync --archive --delete <restored>/db/ /var/lib/rancher/k3s/server/db/
sudo install -m 0600 <restored>/token /var/lib/rancher/k3s/server/token
sudo rsync --archive <restored>/etc-rancher-k3s/ /etc/rancher/k3s/
sudo systemctl start k3s
bash scripts/linux/verify.sh
```

Do not run `rsync --delete` until the resolved source and destination paths
have been reviewed at the console.

## Credential Rotation

Rotate runtime credentials at the provider first, then reconcile the
namespace Secret without writing values to disk:

```bash
read -rsp 'New PostgreSQL URL: ' DATABASE_URL
printf '\n'
read -rsp 'New Redis URL: ' REDIS_URL
printf '\n'

kubectl create secret generic novashop-development-secrets \
  --namespace novashop-development \
  --from-literal=DATABASE_URL="${DATABASE_URL}" \
  --from-literal=REDIS_URL="${REDIS_URL}" \
  --dry-run=client --output=yaml \
  | kubectl apply --server-side \
      --field-manager=novashop-runtime-bootstrap -f -

unset DATABASE_URL REDIS_URL
kubectl rollout restart deployment \
  --namespace novashop-development
```

Rotate the Argo CD local admin password with:

```bash
argocd account update-password
```

Prefer SSO and short-lived credentials for shared administration.

## Troubleshooting

### k3s Does Not Start

```bash
sudo systemctl status k3s --no-pager
sudo journalctl --unit=k3s --since='30 minutes ago' --no-pager
sudo ss -lntup | grep -E ':(80|443|6443)\b'
df -hT
```

### Node Is Not Ready

```bash
kubectl describe node
kubectl get events --all-namespaces --sort-by='.metadata.creationTimestamp'
sudo k3s crictl ps --all
sudo k3s crictl logs <container-id>
```

### Traefik Does Not Route

```bash
kubectl --namespace kube-system get \
  deployment,service,pods -l app.kubernetes.io/name=traefik
kubectl get ingress --all-namespaces
kubectl describe ingress novashop --namespace novashop-development
curl --resolve dev.novashop.local:80:10.10.1.45 \
  http://dev.novashop.local/
```

### Argo CD Cannot Reach Git

```bash
git ls-remote \
  https://github.com/nguyenlpn2015/NovaShop-GitOps.git refs/heads/main
kubectl logs --namespace argocd deployment/argocd-repo-server --tail=200
argocd repo list
```

### Application Is Degraded

```bash
argocd app get novashop-development
kubectl get pods --namespace novashop-development -o wide
kubectl describe pods --namespace novashop-development
kubectl logs --namespace novashop-development \
  deployment/novashop-backend --tail=200
```
