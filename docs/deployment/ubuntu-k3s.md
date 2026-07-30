# Ubuntu Server and k3s Deployment

This runbook provisions Deployment Target B: a production-like, single-node
k3s platform on Ubuntu Server 22.04 LTS. Deployment Target A remains the
supported Windows developer workstation path.

## Supported Baseline

| Item | Baseline |
|------|----------|
| Operating system | Ubuntu Server 22.04 LTS |
| Node address | `10.10.1.45` |
| k3s | `v1.33.13+k3s1` |
| Helm | `v3.21.1` |
| Argo CD | `v3.4.4` |
| Ingress | k3s-bundled Traefik |
| Pod CIDR | `10.42.0.0/16` |
| Service CIDR | `10.43.0.0/16` |

## Prerequisites

- A clean Ubuntu Server 22.04 LTS VM with a static or reserved address of
  `10.10.1.45`.
- At least 4 vCPU, 8 GiB RAM, and 60 GiB SSD storage.
- A non-root operator with `sudo` access and SSH key authentication.
- Outbound TCP `443` access to GitHub, GHCR, k3s, Helm, and Argo CD release
  endpoints.
- Reachable PostgreSQL and Redis endpoints. The platform does not place
  stateful data services inside the single-node application cluster.
- Public `main` branches for `NovaShop` and `NovaShop-GitOps`.
- A hypervisor snapshot or tested VM backup before destructive maintenance.

## Server Preparation

Confirm the operating system and address:

```bash
cat /etc/os-release
ip -brief -4 address
ip route
```

Update the base system and reboot if `/var/run/reboot-required` exists:

```bash
sudo apt-get update
sudo apt-get dist-upgrade --yes
test ! -f /var/run/reboot-required || sudo systemctl reboot
```

Install required packages:

```bash
sudo apt-get install --yes \
  ca-certificates curl git jq openssh-client tar ufw
```

Do not install Docker, kubeadm, or another container runtime. k3s installs and
manages containerd.

## Swap

Disable swap and preserve the original filesystem configuration:

```bash
sudo swapoff --all
sudo cp --archive /etc/fstab /etc/fstab.pre-k3s
sudo sed --in-place --regexp-extended \
  '/^[^#].+[[:space:]]swap[[:space:]]/ s/^/# novashop-k3s: /' \
  /etc/fstab
swapon --show
```

`swapon --show` must return no active devices. Review `/etc/fstab` before
rebooting; restore `/etc/fstab.pre-k3s` from the virtualization console if the
file was changed incorrectly.

## Time Synchronization

Enable the Ubuntu time synchronization service:

```bash
sudo timedatectl set-ntp true
timedatectl status
timedatectl show --property=NTPSynchronized --value
```

`NTPSynchronized=yes` is required before capturing evidence or diagnosing
certificate and GitOps reconciliation timestamps.

## Hostname

Set a stable node identity before installing k3s:

```bash
sudo hostnamectl set-hostname novashop-k3s
hostnamectl
```

Add the address and hostname to internal DNS. If internal DNS is unavailable,
maintain it in the management workstation's hosts file; do not rewrite the
server's loopback entry.

## Network and DNS

Reserve `10.10.1.45` in DHCP or configure it through the virtualization
platform. Verify the default gateway and DNS resolver survive a reboot.

Create internal records:

```text
dev.novashop.local       A  10.10.1.45
api.dev.novashop.local   A  10.10.1.45
```

Staging and production names in the GitOps values use example domains. Replace
them through reviewed GitOps changes and provision valid TLS Secrets before
exposing those environments.

The following networks must not overlap the on-premises LAN, VPN, or
virtualization networks:

- Pods: `10.42.0.0/16`
- Services: `10.43.0.0/16`

## Firewall

Confirm hypervisor console access before enabling UFW. Allow only the
management subnet to reach SSH and the Kubernetes API:

```bash
export MANAGEMENT_CIDR='10.10.1.0/24'

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from "${MANAGEMENT_CIDR}" to any port 22 proto tcp
sudo ufw allow from "${MANAGEMENT_CIDR}" to any port 6443 proto tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow from 10.42.0.0/16
sudo ufw allow from 10.43.0.0/16
sudo ufw --force enable
sudo ufw status verbose
```

Do not expose ports `6443` or `22` to untrusted networks. Single-node k3s does
not require externally accessible inter-node Flannel ports.

## Storage

k3s uses its bundled local-path provisioner. Place `/var/lib/rancher/k3s` on
reliable local SSD storage; do not use ephemeral VM disks.

```bash
df -hT /
findmnt -T /var/lib
lsblk --fs
```

Maintain at least 20 GiB free space:

```bash
df --output=avail -BG /var/lib/rancher/k3s
sudo du -sh /var/lib/rancher/k3s
sudo k3s crictl images
```

Persistent database and cache data remain outside this cluster. The local-path
provisioner is not a substitute for replicated production storage.

## Clone the Repositories

```bash
mkdir -p "${HOME}/src"
cd "${HOME}/src"
git clone https://github.com/nguyenlpn2015/NovaShop.git
git clone https://github.com/nguyenlpn2015/NovaShop-GitOps.git
cd NovaShop
```

The repositories remain siblings so Helm validation can reference GitOps
values without copying them.

## Configure Runtime Connections

Verify the target endpoints from the VM:

```bash
getent hosts <postgres-host> <redis-host>
timeout 5 bash -c '</dev/tcp/<postgres-host>/5432'
timeout 5 bash -c '</dev/tcp/<redis-host>/6379'
```

Load credentials without writing them to Git or shell history:

```bash
read -rsp 'PostgreSQL URL: ' DATABASE_URL
printf '\n'
read -rsp 'Redis URL: ' REDIS_URL
printf '\n'
export DATABASE_URL REDIS_URL
```

## Bootstrap

Review the script and run it as the non-root operator:

```bash
export NODE_IP='10.10.1.45'
export CONFIGURE_HOSTNAME='true'
export ENABLE_UFW='true'
export MANAGEMENT_CIDR='10.10.1.0/24'

bash scripts/linux/bootstrap.sh
unset DATABASE_URL REDIS_URL
```

The script is safe to rerun. It refuses an implicit k3s version change and
does not overwrite existing runtime Secrets.

## Access

From a workstation that resolves the development records:

- Frontend: `http://dev.novashop.local`
- Backend: `http://api.dev.novashop.local/health`

Access Argo CD through SSH and a local-only port forward:

```bash
ssh -L 8080:127.0.0.1:8080 <operator>@10.10.1.45
cd "${HOME}/src/NovaShop"
bash scripts/port-forward.sh
```

Open `https://localhost:8080`. Rotate the initial admin password immediately;
use SSO and disable the built-in admin account before allowing multiple
operators:

```bash
export PATH="${HOME}/.local/bin:${PATH}"
INITIAL_PASSWORD="$(argocd admin initial-password --namespace argocd)"

argocd login localhost:8080 \
  --username admin \
  --password "${INITIAL_PASSWORD}" \
  --insecure
argocd account update-password

kubectl delete secret argocd-initial-admin-secret \
  --namespace argocd \
  --ignore-not-found
unset INITIAL_PASSWORD
```

## Next Steps

- Follow the [Bootstrap Sequence](bootstrap-sequence.md).
- Run the [Validation Runbook](validation.md).
- Use [Target B Operations](operations.md) for lifecycle work.
- Capture [Portfolio Evidence](portfolio-evidence.md).
- Use the existing [GitOps Architecture](../GITOPS_ARCHITECTURE.md) for
  repository, synchronization, and promotion behavior.
