#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hostsPath = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
$entries = @(
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
