# Runtime Scripts

| Script | Purpose |
|--------|---------|
| `install-argocd.sh` | Install pinned Argo CD server manifests and verified CLI |
| `bootstrap.sh` | Bootstrap the root GitOps application and runtime Secrets |
| `port-forward.sh` | Open local access to the Argo CD API and UI |
| `cleanup.sh` | Remove NovaShop runtime resources with explicit confirmation |

Run scripts from the NovaShop repository root with Bash.

`bootstrap.sh` preserves existing runtime Secrets. Missing Secrets are created
from environment-specific `*_DATABASE_URL` and `*_REDIS_URL` variables, or
from the shared `DATABASE_URL` and `REDIS_URL` fallback for local clusters.
