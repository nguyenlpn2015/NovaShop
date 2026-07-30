#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ArgoCDVersion = 'v3.4.4',
    [int]$TimeoutSeconds = 600,
    [string]$InstallDirectory = "$env:LOCALAPPDATA\Programs\ArgoCD"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$ArgoCDNamespace = 'argocd'

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

function Install-ArgoCDCli {
    $executable = Join-Path $InstallDirectory 'argocd.exe'
    if (Test-Path -LiteralPath $executable) {
        $installedVersion = (& $executable version --client 2>$null | Out-String)
        if ($LASTEXITCODE -eq 0 -and $installedVersion -match [regex]::Escape($ArgoCDVersion.TrimStart('v'))) {
            Write-Host "Argo CD CLI $ArgoCDVersion is already installed."
            return
        }
    }

    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

    try {
        $assetName = 'argocd-windows-amd64.exe'
        $assetPath = Join-Path $temporaryDirectory $assetName
        $checksumPath = Join-Path $temporaryDirectory 'cli_checksums.txt'
        $releaseBase = "https://github.com/argoproj/argo-cd/releases/download/$ArgoCDVersion"

        Invoke-WebRequest -Uri "$releaseBase/$assetName" -OutFile $assetPath
        Invoke-WebRequest -Uri "$releaseBase/cli_checksums.txt" -OutFile $checksumPath

        $checksumLine = Get-Content -LiteralPath $checksumPath |
            Where-Object { $_ -match "\s\*?$([regex]::Escape($assetName))$" } |
            Select-Object -First 1
        if (-not $checksumLine) {
            throw "Checksum not found for $assetName."
        }

        $expectedHash = ($checksumLine -split '\s+')[0].ToUpperInvariant()
        $actualHash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) {
            throw 'Argo CD CLI checksum verification failed.'
        }

        New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
        Copy-Item -LiteralPath $assetPath -Destination $executable -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDirectory) {
            Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
        }
    }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $userEntries = @($userPath -split ';' | Where-Object { $_ })
    if ($userEntries -notcontains $InstallDirectory) {
        $newUserPath = (@($userEntries) + $InstallDirectory) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    }
    if (($env:Path -split ';') -notcontains $InstallDirectory) {
        $env:Path = "$InstallDirectory;$env:Path"
    }

    Write-Host "Installed verified Argo CD CLI to $executable."
}

& (Join-Path $PSScriptRoot 'verify-docker-desktop.ps1')

if ($ArgoCDVersion -notmatch '^v\d+\.\d+\.\d+$') {
    throw 'ArgoCDVersion must be a pinned release tag such as v3.4.4.'
}

$namespaceManifest = Join-Path $RepositoryRoot 'argocd\namespace.yaml'
$officialManifest = "https://raw.githubusercontent.com/argoproj/argo-cd/$ArgoCDVersion/manifests/install.yaml"

Invoke-CheckedCommand kubectl @(
    'apply', '--server-side',
    '--field-manager=novashop-bootstrap',
    '-f', $namespaceManifest
)
Invoke-CheckedCommand kubectl @(
    'apply', '--namespace', $ArgoCDNamespace,
    '--server-side', '--force-conflicts',
    '--field-manager=argocd-installer',
    '-f', $officialManifest
)

$timeout = "${TimeoutSeconds}s"
Invoke-CheckedCommand kubectl @(
    'wait', '--for=condition=Established',
    'customresourcedefinition/applications.argoproj.io',
    'customresourcedefinition/applicationsets.argoproj.io',
    'customresourcedefinition/appprojects.argoproj.io',
    "--timeout=$timeout"
)
Invoke-CheckedCommand kubectl @(
    'wait', '--namespace', $ArgoCDNamespace,
    '--for=condition=Available',
    'deployment', '--all',
    "--timeout=$timeout"
)
Invoke-CheckedCommand kubectl @(
    'rollout', 'status',
    'statefulset/argocd-application-controller',
    '--namespace', $ArgoCDNamespace,
    "--timeout=$timeout"
)

Install-ArgoCDCli
Invoke-CheckedCommand kubectl @('get', 'pods', '--namespace', $ArgoCDNamespace)
Write-Host "Argo CD $ArgoCDVersion is ready." -ForegroundColor Green
