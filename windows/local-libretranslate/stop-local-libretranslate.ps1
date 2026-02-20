param(
    [string]$ContainerName = "triple-space-libretranslate"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) {
    Write-Host "[Local LibreTranslate] $msg" -ForegroundColor Yellow
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker is not installed."
}

$exists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }
if (-not $exists) {
    Write-Step "Container '$ContainerName' not found. Nothing to stop."
    exit 0
}

$running = docker inspect -f "{{.State.Running}}" $ContainerName 2>$null
if ($running -eq "true") {
    Write-Step "Stopping container '$ContainerName' ..."
    docker stop $ContainerName | Out-Null
}

Write-Step "Removing container '$ContainerName' ..."
docker rm $ContainerName | Out-Null

Write-Host "Done." -ForegroundColor Green
