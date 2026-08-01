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
| `linux/recover.sh` | Rebuild the platform on a replacement node from Git and a certificate backup |

Run Target B scripts with Bash:

```bash
bash scripts/linux/bootstrap.sh
```

Recovery differs from bootstrap: it verifies every precondition and aborts before
touching k3s if any is unmet. See
[Disaster Recovery](../docs/recovery/disaster-recovery.md).

## Shared Linux GitOps Primitives

| Script | Purpose |
|--------|---------|
| `install-argocd.sh` | Install the digest-verified Argo CD manifests and verified CLI |
| `bootstrap.sh` | Bootstrap the root GitOps application and runtime Secrets |
| `port-forward.sh` | Open local access to the Argo CD API and UI |
| `cleanup.sh` | Remove NovaShop runtime resources with explicit confirmation |
| `lib/edge-phase.sh` | Sourced helper that detects the reconciled edge phase |

`bootstrap.sh` preserves existing runtime Secrets and rejects a Secret that
exists without both `DATABASE_URL` and `REDIS_URL`. Missing Secrets are created
from environment-specific `*_DATABASE_URL` and `*_REDIS_URL` variables, or
from the shared `DATABASE_URL` and `REDIS_URL` fallback for local clusters.

The active edge phase is read from the reconciled Argo CD Application, not passed
in. `EXPECTED_EDGE_SOURCE_PATH` and `ENABLE_TLS_VALIDATION` are assertions: set
them to make bootstrap stop when the cluster does not match your expectation,
and leave them unset to adopt whatever Git declares.

## Platform Guardrails

| Script | Purpose |
|--------|---------|
| `validate-platform.sh` | Render and validate the desired state across both repositories |
| `validate-gitops-revisions.sh` | Enforce revision durability and image traceability |
| `apply-branch-protection.sh` | Apply the reviewed rulesets in `.github/rulesets` |
| `backup-platform-state.sh` | Export TLS keys and the ACME account key |
| `restore-platform-state.sh` | Restore certificate material before cert-manager reconciles |

Run the full gate before opening a pull request in either repository:

```bash
bash scripts/validate-platform.sh --gitops-dir ../NovaShop-GitOps
```

It requires `yamllint`, `helm`, `kubeconform`, and either `kustomize` or a
`kubectl` new enough to embed it. Set `SKIP_SCHEMA_VALIDATION=true` when the CRD
schema catalog is unreachable; everything else runs offline.

`apply-branch-protection.sh` defaults to a dry run and refuses to apply a
required status check that no workflow has ever reported, because such a check
would block every pull request permanently.

Certificate material is the only platform state Git cannot reproduce. Back it up
while the platform is healthy:

```bash
bash scripts/backup-platform-state.sh --output-dir /srv/novashop-state
```

The export contains private keys. It is written with mode `0600`, must be stored
outside the cluster, and its filenames are ignored by Git.

Details are in [Platform Guardrails](../docs/PLATFORM_GUARDRAILS.md).
