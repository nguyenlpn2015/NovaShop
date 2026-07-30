# Deployment Target B Lab Environment

## Declared Baseline

| Property | Value |
|----------|-------|
| Purpose | Production-like Platform Engineering lab |
| Virtualization | On-premises virtualized environment |
| Topology | Single-node VPS-like VM |
| Operating system | Ubuntu Server 22.04 LTS |
| Hostname | `novashop-k3s` |
| Private address | `10.10.1.45` |
| CPU | 4 vCPU minimum |
| Memory | 8 GiB minimum |
| Disk | 60 GiB SSD minimum |
| Filesystem | `ext4` or `xfs` |
| Container runtime | k3s-managed containerd |
| k3s | `v1.33.13+k3s1` |
| kubectl | k3s-bundled, matched to the server |
| Helm | `v3.21.1` |
| Argo CD | `v3.4.4` |
| Traefik | Bundled and pinned transitively by k3s |
| Pod network | `10.42.0.0/16` |
| Service network | `10.43.0.0/16` |

The actual hypervisor, CPU model, RAM allocation, disk controller, and
filesystem must be recorded after provisioning rather than inferred.

## Capture Actual Values

```bash
printf '%s\n' '=== OS ==='
cat /etc/os-release
uname -a

printf '%s\n' '=== Compute ==='
lscpu
free -h

printf '%s\n' '=== Storage ==='
lsblk --fs
df -hT
findmnt -T /var/lib/rancher/k3s

printf '%s\n' '=== Network ==='
hostnamectl
ip -brief address
ip route
resolvectl status

printf '%s\n' '=== Platform versions ==='
k3s --version
kubectl version
helm version --short
argocd version --client
sudo k3s crictl version

printf '%s\n' '=== Bundled components ==='
kubectl --namespace kube-system get deployment traefik \
  --output=jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl get helmchart traefik \
  --namespace kube-system \
  --output=yaml
```

Store the command output with deployment evidence, excluding tokens,
kubeconfigs, Secret data, internal credentials, and private keys.

## Network Layout

```text
Management workstation
        |
        | SSH 22 / Kubernetes API 6443
        v
Ubuntu VM 10.10.1.45
        |
        +-- Traefik 80/443
        +-- k3s node
              |
              +-- Pod CIDR 10.42.0.0/16
              +-- Service CIDR 10.43.0.0/16
              +-- Argo CD
              +-- NovaShop environments
        |
        +-- Outbound HTTPS
        |     +-- GitHub
        |     +-- GHCR
        |
        +-- Private data network
              +-- PostgreSQL
              +-- Redis
```

## Capacity Guardrails

- Keep at least 20 GiB free under `/var/lib/rancher/k3s`.
- Avoid CPU overcommit that starves the control plane.
- Reserve enough memory for k3s, Argo CD, Traefik, metrics-server, and the
  production replica profile.
- Treat a host or disk failure as a complete cluster outage.
- Keep VM and k3s datastore backups outside the virtualization host.
- Do not claim high availability for this target.
