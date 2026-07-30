#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command is not available in PATH: $Name"
    }
}

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

Assert-Command docker
Assert-Command git
Assert-Command helm
Assert-Command kubectl

Write-Host '== Docker Desktop =='
Invoke-CheckedCommand docker @('desktop', 'status')
$kubernetesStatus = (& docker desktop kubernetes status 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $kubernetesStatus -notmatch 'State:\s+running') {
    throw @'
Docker Desktop Kubernetes is not running.
Open Docker Desktop > Kubernetes, create/start the cluster, and wait until it is ready.
'@
}
$kubernetesStatus.Trim()

Write-Host '== Tools =='
Invoke-CheckedCommand kubectl @('version', '--client', '--output=yaml')
Invoke-CheckedCommand helm @('version', '--short')
Invoke-CheckedCommand git @('--version')

$contexts = (& kubectl config get-contexts -o name 2>$null)
if ($LASTEXITCODE -ne 0 -or $contexts -notcontains 'docker-desktop') {
    throw 'The docker-desktop kubectl context does not exist.'
}

$currentContext = (& kubectl config current-context 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or $currentContext -ne 'docker-desktop') {
    throw 'Current context must be docker-desktop. Run: kubectl config use-context docker-desktop'
}

Write-Host '== Cluster =='
Invoke-CheckedCommand kubectl @('cluster-info')
Invoke-CheckedCommand kubectl @('get', 'nodes', '-o', 'wide')
Invoke-CheckedCommand kubectl @('get', 'namespaces')

$serverVersion = (& kubectl get --raw=/version | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to read the Kubernetes server version.'
}
$serverMinor = [int]($serverVersion.minor -replace '[^0-9]', '')
if ($serverMinor -lt 33) {
    throw "Kubernetes 1.33+ is required; server is $($serverVersion.gitVersion)."
}

Write-Host "Docker Desktop Kubernetes $($serverVersion.gitVersion) is ready." -ForegroundColor Green
