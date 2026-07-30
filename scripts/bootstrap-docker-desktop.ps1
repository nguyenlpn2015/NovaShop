#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$DatabaseUrl = $env:DATABASE_URL,
    [string]$RedisUrl = $env:REDIS_URL,
    [string]$TraefikChartVersion = '41.1.0',
    [int]$TimeoutSeconds = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$Environments = @('development', 'staging', 'production')
$ApplicationRepository = 'https://github.com/nguyenlpn2015/NovaShop.git'
$GitOpsRepository = 'https://github.com/nguyenlpn2015/NovaShop-GitOps.git'

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

function Test-RemoteMainBranch {
    param([Parameter(Mandatory)][string]$Repository)

    & git ls-remote --exit-code $Repository refs/heads/main *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Remote repository is unavailable or has no main branch: $Repository"
    }
}

function Read-SecretText {
    param([Parameter(Mandatory)][string]$Prompt)

    $secureValue = Read-Host $Prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Wait-KubernetesResource {
    param(
        [Parameter(Mandatory)][string]$Resource,
        [Parameter(Mandatory)][string]$Namespace
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        & kubectl get $Resource --namespace $Namespace *> $null
        if ($LASTEXITCODE -eq 0) {
            return
        }
        Start-Sleep -Seconds 5
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Timed out waiting for $Resource in namespace $Namespace."
}

function Wait-ArgoApplication {
    param([Parameter(Mandatory)][string]$Name)

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $rawApplication = (& kubectl get application $Name --namespace argocd -o json 2>$null | Out-String)
        if ($LASTEXITCODE -eq 0 -and $rawApplication) {
            $application = $rawApplication | ConvertFrom-Json
            $sync = $application.status.sync.status
            $health = $application.status.health.status
            Write-Host "$Name sync=$sync health=$health"
            if ($sync -eq 'Synced' -and $health -eq 'Healthy') {
                return
            }
        }
        Start-Sleep -Seconds 5
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Timed out waiting for Argo CD application $Name."
}

function Ensure-RuntimeSecret {
    param([Parameter(Mandatory)][string]$Environment)

    $namespace = "novashop-$Environment"
    $secretName = "novashop-$Environment-secrets"
    & kubectl get secret $secretName --namespace $namespace *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Secret $namespace/$secretName already exists."
        return
    }

    $secret = @{
        apiVersion = 'v1'
        kind = 'Secret'
        metadata = @{
            name = $secretName
            namespace = $namespace
        }
        type = 'Opaque'
        stringData = @{
            DATABASE_URL = $DatabaseUrl
            REDIS_URL = $RedisUrl
        }
    } | ConvertTo-Json -Depth 5

    $secret | & kubectl apply --server-side `
        --field-manager=novashop-runtime-bootstrap `
        -f -
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create Secret $namespace/$secretName."
    }
}

& (Join-Path $PSScriptRoot 'verify-docker-desktop.ps1')
Test-RemoteMainBranch $ApplicationRepository
Test-RemoteMainBranch $GitOpsRepository

if (-not $DatabaseUrl) {
    $DatabaseUrl = Read-SecretText 'PostgreSQL URL'
}
if (-not $RedisUrl) {
    $RedisUrl = Read-SecretText 'Redis URL'
}
if (-not $DatabaseUrl -or -not $RedisUrl) {
    throw 'DatabaseUrl and RedisUrl are required.'
}

Invoke-CheckedCommand helm @(
    'repo', 'add', 'traefik',
    'https://traefik.github.io/charts',
    '--force-update'
)
Invoke-CheckedCommand helm @('repo', 'update', 'traefik')
Invoke-CheckedCommand helm @(
    'upgrade', '--install', 'traefik', 'traefik/traefik',
    '--version', $TraefikChartVersion,
    '--namespace', 'traefik',
    '--create-namespace',
    '--set', 'providers.kubernetesIngress.enabled=true',
    '--set', 'ingressClass.enabled=true',
    '--set', 'ingressClass.isDefaultClass=false',
    '--atomic', '--wait',
    '--timeout', "${TimeoutSeconds}s"
)

& (Join-Path $PSScriptRoot 'install-argocd.ps1') -TimeoutSeconds $TimeoutSeconds

Invoke-CheckedCommand kubectl @(
    'apply', '--server-side',
    '--field-manager=novashop-bootstrap',
    '-f', (Join-Path $RepositoryRoot 'argocd\project.yaml'),
    '-f', (Join-Path $RepositoryRoot 'argocd\application.yaml')
)

Wait-KubernetesResource -Resource 'applicationset/novashop' -Namespace 'argocd'

foreach ($environment in $Environments) {
    Wait-KubernetesResource -Resource "application/novashop-$environment" -Namespace 'argocd'
    Wait-KubernetesResource -Resource "namespace/novashop-$environment" -Namespace 'default'
    Ensure-RuntimeSecret -Environment $environment
}

foreach ($environment in $Environments) {
    Wait-KubernetesResource -Resource 'deployment/novashop-backend' -Namespace "novashop-$environment"
    Wait-KubernetesResource -Resource 'deployment/novashop-frontend' -Namespace "novashop-$environment"
    Invoke-CheckedCommand kubectl @(
        'wait', '--namespace', "novashop-$environment",
        '--for=condition=Available',
        'deployment/novashop-backend',
        'deployment/novashop-frontend',
        "--timeout=${TimeoutSeconds}s"
    )
    Wait-ArgoApplication -Name "novashop-$environment"
}

Invoke-CheckedCommand kubectl @('get', 'applications,applicationsets', '--namespace', 'argocd')
Invoke-CheckedCommand kubectl @('get', 'pods', '--all-namespaces')
Write-Host 'NovaShop GitOps runtime is ready on Docker Desktop Kubernetes.' -ForegroundColor Green
