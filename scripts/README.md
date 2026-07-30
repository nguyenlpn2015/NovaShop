# Runtime Scripts

Run every script from the NovaShop repository root. Platform scripts prepare
the target cluster; application delivery remains controlled by Argo CD and
`NovaShop-GitOps`.

## Deployment Target A: Windows and Docker Desktop Kubernetes

| Script | Purpose |
|--------|---------|
| `verify-docker-desktop.ps1` | Verify tools, context, cluster, and Kubernetes version |
| `install-argocd.ps1` | Install pinned official Argo CD manifests and verified Windows CLI |
| `bootstrap-docker-desktop.ps1` | Install Traefik and reconcile the complete GitOps runtime |
| `port-forward-argocd.ps1` | Open local access to the Argo CD UI and API |
| `configure-local-hosts.ps1` | Add idempotent NovaShop entries to the Windows hosts file |
| `cleanup-docker-desktop.ps1` | Remove runtime resources with explicit confirmation |

Run the PowerShell scripts from the NovaShop repository root:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\verify-docker-desktop.ps1
```

## Deployment Target B: Ubuntu Server and k3s

| Script | Purpose |
|--------|---------|
| `linux/install-k3s.sh` | Install pinned k3s and create a user-scoped kubeconfig |
| `linux/install-helm.sh` | Install a checksum-verified, pinned Helm 3 client |
| `linux/install-argocd.sh` | Install the pinned official Argo CD runtime and CLI |
| `linux/bootstrap.sh` | Provision and reconcile the complete Target B platform |
| `linux/verify.sh` | Validate k3s, Traefik, Argo CD, Applications, and workloads |
| `linux/cleanup.sh` | Remove Target B resources with explicit confirmation |

Run Target B scripts with Bash:

```bash
bash scripts/linux/bootstrap.sh
```

## Shared Linux GitOps Primitives

| Script | Purpose |
|--------|---------|
| `install-argocd.sh` | Install pinned Argo CD server manifests and verified CLI |
| `bootstrap.sh` | Bootstrap the root GitOps application and runtime Secrets |
| `port-forward.sh` | Open local access to the Argo CD API and UI |
| `cleanup.sh` | Remove NovaShop runtime resources with explicit confirmation |

`bootstrap.sh` preserves existing runtime Secrets. Missing Secrets are created
from environment-specific `*_DATABASE_URL` and `*_REDIS_URL` variables, or
from the shared `DATABASE_URL` and `REDIS_URL` fallback for local clusters.
