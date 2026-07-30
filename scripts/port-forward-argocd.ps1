#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateRange(1, 65535)][int]$LocalPort = 8080
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$currentContext = (& kubectl config current-context 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or $currentContext -ne 'docker-desktop') {
    throw 'Current kubectl context must be docker-desktop.'
}

$existing = Get-CimInstance Win32_Process |
    Where-Object {
        $_.CommandLine -match 'kubectl(.exe)?\s+port-forward' -and
        $_.CommandLine -match 'argocd-server' -and
        $_.CommandLine -match "$LocalPort`:443"
    } |
    Select-Object -First 1

if ($existing) {
    Write-Host "Argo CD port-forward already runs as PID $($existing.ProcessId)."
    Write-Host "https://localhost:$LocalPort"
    return
}

& kubectl get service argocd-server --namespace argocd *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'Service argocd/argocd-server does not exist.'
}

Write-Host "Argo CD UI: https://localhost:$LocalPort"
Write-Host 'Press Ctrl+C to stop the port-forward.'
& kubectl port-forward service/argocd-server "${LocalPort}:443" --namespace argocd
if ($LASTEXITCODE -ne 0) {
    throw "kubectl port-forward failed with exit code $LASTEXITCODE."
}
