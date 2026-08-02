<#
.SYNOPSIS
    Deploys NovaShop to the Kubernetes cluster built into Docker Desktop.

.DESCRIPTION
    A local equivalent of the production platform, close enough to be useful and
    honest about where it differs.

    What matches production:
      - the same Helm chart, rendered from this repository
      - the same container images, pulled from GHCR by commit SHA
      - Traefik as the ingress controller
      - a local-path storage provisioner
      - the same Alembic migration and seed, run as a Job before the rollout

    What does not, and why:
      - PostgreSQL and Redis run inside the cluster. On the node they run on the
        host, because a database in a pod on a single node adds failure modes
        without adding any of the benefits that make it worthwhile at scale.
        Here, in-cluster is self-contained and disposable, which matters more.
      - No Argo CD. Nothing reconciles: this script applies once and stops.
        GitOps is the thing the real platform demonstrates, and simulating it
        locally would teach the shape without the substance.
      - No TLS, no cert-manager. Let's Encrypt cannot issue for localhost.
      - Namespace novashop-local, deliberately separate from the
        novashop-development / staging / production namespaces this cluster may
        already carry from earlier work.

.PARAMETER Revision
    Commit SHA to deploy. Defaults to the current HEAD of origin/main, which is
    what has images published in GHCR.

.PARAMETER Uninstall
    Remove everything this script created and exit.

.EXAMPLE
    .\scripts\deploy-local-k8s.ps1

.EXAMPLE
    .\scripts\deploy-local-k8s.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$Revision,
    [string]$Namespace = 'novashop-local',
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$HelmImage = 'alpine/helm:3.16.2'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn2 { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }

function Assert-Command {
    param([string]$Name, [string]$Hint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is not on PATH. $Hint"
    }
}

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------
# Checked before anything is created. A script that fails halfway through
# leaves a namespace of partial state that the next run has to reason about.

Write-Step 'Preflight'

Assert-Command -Name 'docker' -Hint 'Install Docker Desktop.'
Assert-Command -Name 'kubectl' -Hint 'Enable Kubernetes in Docker Desktop settings.'

$context = (kubectl config current-context 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'kubectl has no current context. Enable Kubernetes in Docker Desktop.' }
if ($context -ne 'docker-desktop') {
    # Refused rather than switched. Applying a local development manifest to
    # whichever cluster happens to be selected is how people deploy to the wrong
    # place, and the wrong place is sometimes production.
    throw "Current context is '$context', not 'docker-desktop'. Refusing to continue. Run: kubectl config use-context docker-desktop"
}

kubectl version --request-timeout=10s -o json 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot reach the cluster. Is Kubernetes running in Docker Desktop?' }
Write-Ok "Context: $context"

if (-not (kubectl get ingressclass traefik -o name 2>$null)) {
    Write-Warn2 'No traefik IngressClass. The Ingress will be created but nothing will route it.'
    Write-Warn2 'Use the port-forward printed at the end instead.'
}

# -----------------------------------------------------------------------------
# Uninstall
# -----------------------------------------------------------------------------

if ($Uninstall) {
    Write-Step "Removing namespace $Namespace"
    kubectl delete namespace $Namespace --ignore-not-found --wait=false | Out-Null
    Write-Ok 'Deletion started. Everything created by this script lived in that namespace.'
    return
}

# -----------------------------------------------------------------------------
# Revision
# -----------------------------------------------------------------------------

if (-not $Revision) {
    Push-Location $RepoRoot
    try {
        git fetch origin main --quiet 2>$null
        $Revision = (git rev-parse origin/main).Trim()
    } finally { Pop-Location }
}
if ($Revision -notmatch '^[0-9a-f]{40}$') {
    throw "Revision must be a 40-character commit SHA. Got: $Revision"
}
Write-Ok "Revision: $Revision"

# Images are pulled from GHCR, so the SHA must have been released. Checked here
# rather than discovered as ImagePullBackOff three minutes later.
Write-Step 'Checking the images exist in GHCR'
foreach ($component in 'backend', 'frontend') {
    $repo = "nguyenlpn2015/novashop-$component"
    $token = (Invoke-RestMethod -Uri "https://ghcr.io/token?scope=repository:${repo}:pull" -TimeoutSec 20).token
    $headers = @{
        Authorization = "Bearer $token"
        Accept        = 'application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json'
    }
    $response = Invoke-WebRequest -Uri "https://ghcr.io/v2/$repo/manifests/$Revision" -Headers $headers `
        -Method Head -SkipHttpErrorCheck -TimeoutSec 20
    if ($response.StatusCode -ne 200) {
        throw "No published image for $component at $Revision. Pick a revision whose release workflow completed."
    }
    Write-Ok "$component image present"
}

# -----------------------------------------------------------------------------
# Namespace and datastores
# -----------------------------------------------------------------------------

Write-Step "Namespace $Namespace"
kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f - | Out-Null

# Pod Security Admission, matching what the real namespaces enforce. Applied
# here so a chart change that violates `restricted` fails locally rather than
# at sync time on the node.
kubectl label namespace $Namespace `
    pod-security.kubernetes.io/enforce=restricted `
    pod-security.kubernetes.io/audit=restricted `
    pod-security.kubernetes.io/warn=restricted --overwrite | Out-Null
Write-Ok 'Created, with pod-security enforce=restricted'

Write-Step 'PostgreSQL and Redis (local only)'
$datastores = Join-Path $RepoRoot 'kubernetes/local/datastores.yaml'
if (-not (Test-Path $datastores)) { throw "Missing $datastores" }
kubectl apply -n $Namespace -f $datastores | Out-Null

Write-Ok 'Waiting for both to become ready'
kubectl wait --for=condition=available --timeout=180s -n $Namespace deployment/postgres deployment/redis | Out-Null
Write-Ok 'Ready'

# -----------------------------------------------------------------------------
# Secret
# -----------------------------------------------------------------------------
#
# Created here rather than templated into the chart, which is how the real
# platform does it: the chart requires an existing Secret and refuses to render
# without one. The password is local-only and fixed, so `-Uninstall` followed by
# a redeploy lands on the same credentials as the PersistentVolumeClaim it
# reconnects to.

Write-Step 'Application Secret'
kubectl create secret generic novashop-local-secrets -n $Namespace `
    --from-literal=DATABASE_URL='postgresql://novashop:localdev@postgres:5432/novashop' `
    --from-literal=REDIS_URL='redis://redis:6379/0' `
    --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Ok 'novashop-local-secrets'

# -----------------------------------------------------------------------------
# Render and apply the chart
# -----------------------------------------------------------------------------
#
# Rendered through a container because Helm is frequently not installed on
# Windows, and requiring it would put a tool install between someone and their
# first working deployment.

Write-Step 'Rendering the chart'
$mount = ($RepoRoot -replace '\\', '/')
$rendered = docker run --rm -v "${mount}:/app" -w /app $HelmImage template novashop helm/novashop `
    --namespace $Namespace `
    --values helm/novashop/values-local.yaml `
    --set "namespace.name=$Namespace" `
    --set "secrets.existingSecret=novashop-local-secrets" `
    --set "backend.image.tag=$Revision" `
    --set "frontend.image.tag=$Revision" 2>&1

if ($LASTEXITCODE -ne 0) { throw "helm template failed:`n$rendered" }
Write-Ok "$(($rendered | Select-String '^kind:').Count) resources rendered"

# The migration Job is removed before anything is applied, not after.
#
# A Job's pod template is immutable, so applying the rendered manifest over a
# Job left by a previous run is rejected -- and because kubectl applies what it
# can and reports the rest, the deployment still succeeded while printing a wall
# of "field is immutable" at the end. Correct outcome, alarming output, and the
# kind of noise that teaches people to skim past errors.
#
# Deleting first means one apply, and silence when it works.
Write-Step 'Applying'
kubectl delete job novashop-migrate -n $Namespace --ignore-not-found --wait=true | Out-Null
$rendered | kubectl apply -n $Namespace -f - | Out-Null

# The Job carries an Argo CD hook annotation, which kubectl ignores -- so it is
# applied like any other resource and simply runs.
Write-Step 'Migration and seed'
kubectl wait --for=condition=complete --timeout=240s job/novashop-migrate -n $Namespace | Out-Null
if ($LASTEXITCODE -ne 0) {
    kubectl logs job/novashop-migrate -n $Namespace --tail=40
    throw 'The migration Job did not complete. Its log is above.'
}
Write-Ok 'Schema applied and demo data seeded'

Write-Step 'Waiting for the rollout'
kubectl rollout status deployment/novashop-backend -n $Namespace --timeout=180s | Out-Null
kubectl rollout status deployment/novashop-frontend -n $Namespace --timeout=180s | Out-Null
Write-Ok 'Both deployments are available'

# -----------------------------------------------------------------------------
# Verify
# -----------------------------------------------------------------------------

Write-Step 'Verifying'
$ready = kubectl exec -n $Namespace deployment/novashop-backend -- `
    python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8000/ready').status)" 2>$null
if ($ready -ne '200') { Write-Warn2 "Backend /ready did not return 200 (got '$ready')" }
else { Write-Ok 'Backend readiness 200, both dependencies healthy' }

$products = kubectl exec -n $Namespace deployment/postgres -- `
    psql -U novashop -d novashop -tAc 'SELECT count(*) FROM products' 2>$null
Write-Ok "Products seeded: $($products.Trim())"

Write-Host ''
Write-Host 'NovaShop is running locally.' -ForegroundColor Green
Write-Host ''
Write-Host '  Port-forward (works regardless of ingress):' -ForegroundColor White
Write-Host "    kubectl port-forward -n $Namespace svc/novashop-frontend 3000:80"
Write-Host '    then open http://localhost:3000'
Write-Host ''
Write-Host '  Through Traefik. No hosts file, no administrator -- *.localhost' -ForegroundColor White
Write-Host '  resolves to 127.0.0.1 on its own:' -ForegroundColor White
Write-Host '    http://novashop.localhost'
Write-Host '    http://api.novashop.localhost/docs'
Write-Host ''
Write-Host '  Remove everything:' -ForegroundColor White
Write-Host "    .\scripts\deploy-local-k8s.ps1 -Uninstall"
Write-Host ''
