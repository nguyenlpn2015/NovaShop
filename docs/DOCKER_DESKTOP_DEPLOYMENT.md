# Docker Desktop GitOps Deployment

Run every command from PowerShell in the `NovaShop` repository root.

## 1. Verify Prerequisites

```powershell
docker desktop status
docker desktop kubernetes status
docker context show

kubectl version --client
kubectl config get-contexts
kubectl config current-context
kubectl cluster-info
kubectl get nodes -o wide
kubectl get namespaces

helm version --short
git --version
```

The expected context is `docker-desktop`. Switch only after confirming the
context exists:

```powershell
kubectl config use-context docker-desktop
```

Run the complete read-only preflight:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\verify-docker-desktop.ps1
```

Expected:

- Docker Desktop status is `running`.
- Docker Desktop Kubernetes state is `running`.
- Context is `docker-desktop`.
- The node is `Ready`.
- Kubernetes is version 1.33 or newer.
- `helm`, `git`, and `kubectl` are available in `PATH`.

If Docker Desktop reports Kubernetes as stopped, open Docker Desktop >
Kubernetes, create/start the cluster, and wait for the `docker-desktop` context.
Do not continue against another context.

## 2. Verify Repository Availability

Both repositories must have a public `main` branch:

```powershell
git ls-remote --exit-code `
  https://github.com/nguyenlpn2015/NovaShop.git `
  refs/heads/main

git ls-remote --exit-code `
  https://github.com/nguyenlpn2015/NovaShop-GitOps.git `
  refs/heads/main
```

Argo CD cannot deploy from an uncommitted local directory. Publish
`NovaShop-GitOps` before continuing.

## 3. Install Argo CD

The script applies the official version-pinned manifests with server-side
apply, waits for the CRDs and workloads, and installs the checksum-verified
Windows CLI:

```powershell
.\scripts\install-argocd.ps1
```

Verify:

```powershell
kubectl get namespace argocd
kubectl get customresourcedefinitions |
  Select-String 'argoproj.io'
kubectl get pods,services,deployments,statefulsets -n argocd
kubectl wait --for=condition=Ready pod --all -n argocd --timeout=10m
argocd version --client
```

## 4. Access Argo CD

Start the port-forward in one PowerShell window:

```powershell
.\scripts\port-forward-argocd.ps1
```

In a second window:

```powershell
$EncodedPassword = kubectl get secret argocd-initial-admin-secret `
  -n argocd `
  -o jsonpath='{.data.password}'
$InitialPassword = [Text.Encoding]::UTF8.GetString(
  [Convert]::FromBase64String($EncodedPassword)
)

argocd login localhost:8080 `
  --username admin `
  --password $InitialPassword `
  --insecure
```

Open <https://localhost:8080> and accept the local self-signed certificate.

Change the password interactively, then remove the initial password Secret:

```powershell
argocd account update-password
kubectl delete secret argocd-initial-admin-secret `
  -n argocd `
  --ignore-not-found
Remove-Variable EncodedPassword, InitialPassword
```

## 5. Register Repositories

Create the project boundary before registering project-scoped repositories:

```powershell
kubectl apply --server-side `
  --field-manager=novashop-bootstrap `
  -f .\argocd\project.yaml
```

Use anonymous HTTPS for this public portfolio. It is reproducible for
recruiters, requires no deploy key, and stores no long-lived credential.

```powershell
argocd repo add https://github.com/nguyenlpn2015/NovaShop.git `
  --name novashop-application `
  --project novashop `
  --upsert

argocd repo add https://github.com/nguyenlpn2015/NovaShop-GitOps.git `
  --name novashop-gitops `
  --project novashop `
  --upsert

argocd repo list
```

SSH is appropriate for a private repository when a dedicated read-only deploy
key and rotation process exist. It adds unnecessary key management for a
public recruiter-facing portfolio.

## 6. Deploy NovaShop

The bootstrap installs the official Traefik Helm chart, reapplies Argo CD
idempotently, creates the root `Application`, waits for the `ApplicationSet`,
creates missing runtime Secrets, and waits for every workload.

```powershell
.\scripts\bootstrap-docker-desktop.ps1
```

The script prompts for reachable PostgreSQL and Redis URLs when the environment
variables are not already set. Values are sent directly to Kubernetes and are
not written to Git.

Trigger an explicit reconciliation:

```powershell
argocd app sync novashop-root
argocd app wait novashop-root --sync --health --timeout 600

argocd app sync novashop-development
argocd app wait novashop-development --sync --health --timeout 600
```

Verify all generated applications:

```powershell
kubectl get applications,applicationsets -n argocd
argocd app list
argocd app get novashop-development
```

Expected status is `Synced` and `Healthy`.

## 7. Browser Verification

### Argo CD UI

```text
https://localhost:8080
```

### Traefik

```powershell
kubectl get pods,services -n traefik
kubectl rollout status deployment/traefik -n traefik --timeout=10m
kubectl get ingressclass traefik
```

The Docker Desktop `LoadBalancer` service should expose ports 80 and 443 on
localhost:

```powershell
kubectl get service traefik -n traefik -o wide
```

### Local Hostnames

Run the idempotent hosts-file helper from an elevated PowerShell process:

```powershell
$HostsScript = (Resolve-Path .\scripts\configure-local-hosts.ps1).Path
Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList @(
  '-NoProfile',
  '-ExecutionPolicy', 'Bypass',
  '-File', "`"$HostsScript`""
)
```

Verify:

```powershell
Resolve-DnsName dev.novashop.local
Resolve-DnsName api.dev.novashop.local

curl.exe --fail http://dev.novashop.local/
curl.exe --fail http://api.dev.novashop.local/health
```

Open:

- <http://dev.novashop.local>
- <http://api.dev.novashop.local/health>

## 8. Final Validation

Run every command in
[Docker Desktop Validation](DOCKER_DESKTOP_VALIDATION.md), then capture the
[Portfolio Evidence](PORTFOLIO_EVIDENCE.md).

## Official References

- [Docker Desktop Kubernetes](https://docs.docker.com/desktop/use-desktop/kubernetes/)
- [Argo CD installation](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [Argo CD Windows CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/)
- [Traefik Kubernetes installation](https://doc.traefik.io/traefik/master/setup/kubernetes/)
