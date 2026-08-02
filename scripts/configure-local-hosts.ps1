#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hostsPath = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
$entries = @(
    # The Docker Desktop Kubernetes deployment (scripts/deploy-local-k8s.ps1).
    '127.0.0.1 novashop.local',
    '127.0.0.1 api.novashop.local',
    # The earlier Docker Desktop work, in the novashop-development namespace.
    # Kept separate deliberately: two Ingresses claiming one host is not an
    # error, Traefik just picks one, and the other returns 404 from a namespace
    # that looks entirely healthy.
    '127.0.0.1 dev.novashop.local',
    '127.0.0.1 api.dev.novashop.local'
)
$content = Get-Content -LiteralPath $hostsPath -Raw

foreach ($entry in $entries) {
    if ($content -notmatch "(?m)^\s*$([regex]::Escape($entry))\s*$") {
        Add-Content -LiteralPath $hostsPath -Value $entry -Encoding ascii
        Write-Host "Added: $entry"
    }
    else {
        Write-Host "Already present: $entry"
    }
}

Clear-DnsClientCache
Write-Host 'Local NovaShop hostnames are configured.' -ForegroundColor Green
