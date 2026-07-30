# Runtime Scripts

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
