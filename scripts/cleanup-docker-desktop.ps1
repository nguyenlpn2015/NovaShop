#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$Confirm,
    [switch]$IncludeArgoCD,
    [switch]$IncludeTraefik,
    [string]$ArgoCDVersion = 'v3.4.4'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Confirm) {
    throw 'Refusing cleanup without -Confirm.'
}

$currentContext = (& kubectl config current-context 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or $currentContext -ne 'docker-desktop') {
    throw 'Current kubectl context must be docker-desktop.'
}

$hasArgoResources = (& kubectl api-resources --api-group=argoproj.io -o name 2>$null) -contains 'applications.argoproj.io'
if ($hasArgoResources) {
    kubectl delete application novashop-root --namespace argocd --ignore-not-found --timeout=10m
    kubectl delete applicationset novashop --namespace argocd --ignore-not-found --timeout=10m
    kubectl delete application --namespace argocd `
        --selector=app.kubernetes.io/part-of=novashop `
        --ignore-not-found --timeout=10m
    kubectl delete appproject novashop --namespace argocd --ignore-not-found --timeout=10m
}

foreach ($environment in @('development', 'staging', 'production')) {
    kubectl delete namespace "novashop-$environment" --ignore-not-found --timeout=10m
}

if ($IncludeArgoCD) {
    $manifest = "https://raw.githubusercontent.com/argoproj/argo-cd/$ArgoCDVersion/manifests/install.yaml"
    kubectl delete --namespace argocd --ignore-not-found --wait=false -f $manifest
    kubectl delete namespace argocd --ignore-not-found --timeout=10m
}

if ($IncludeTraefik -and (Get-Command helm -ErrorAction SilentlyContinue)) {
    helm uninstall traefik --namespace traefik --ignore-not-found
    kubectl delete namespace traefik --ignore-not-found --timeout=10m
}

Write-Host 'Docker Desktop runtime cleanup completed.' -ForegroundColor Green
