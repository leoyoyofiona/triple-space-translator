param(
    [string]$ContainerName = "triple-space-libretranslate",
    [int]$Port = 5000,
    [switch]$NoPull,
    [switch]$NoWait
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) {
    Write-Host "[Local LibreTranslate] $msg" -ForegroundColor Cyan
}

function Ensure-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker is not installed. Install Docker Desktop first: https://www.docker.com/products/docker-desktop/"
    }

    try {
        docker info *> $null
    }
    catch {
        throw "Docker Desktop is not running. Start Docker Desktop and run this script again."
    }
}

function Ensure-Container {
    $exists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }

    if (-not $exists) {
        if (-not $NoPull) {
            Write-Step "Pulling image libretranslate/libretranslate:latest ..."
            docker pull libretranslate/libretranslate:latest
        }

        Write-Step "Creating and starting container '$ContainerName' on 127.0.0.1:$Port ..."
        docker run -d --name $ContainerName -p "127.0.0.1:${Port}:5000" libretranslate/libretranslate:latest | Out-Null
        return
    }

    $running = docker inspect -f "{{.State.Running}}" $ContainerName 2>$null
    if ($running -eq "true") {
        Write-Step "Container '$ContainerName' is already running."
    }
    else {
        Write-Step "Starting existing container '$ContainerName' ..."
        docker start $ContainerName | Out-Null
    }
}

function Wait-ServiceReady {
    if ($NoWait) {
        return
    }

    $url = "http://127.0.0.1:$Port/languages"
    Write-Step "Waiting for service: $url"

    for ($i = 0; $i -lt 60; $i++) {
        try {
            $resp = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 2
            if ($resp) {
                Write-Step "Service is ready."
                return
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "Service did not become ready in time. Check Docker logs: docker logs $ContainerName"
}

function Set-Or-AddProperty($obj, [string]$name, $value) {
    if ($obj.PSObject.Properties.Match($name).Count -gt 0) {
        $obj.$name = $value
    }
    else {
        $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value
    }
}

function Update-AppSettings {
    $settingsDir = Join-Path $env:APPDATA "TripleSpaceTranslator"
    $settingsPath = Join-Path $settingsDir "settings.json"

    New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null

    if (Test-Path $settingsPath) {
        try {
            $raw = Get-Content -Raw -Path $settingsPath
            $settings = if ([string]::IsNullOrWhiteSpace($raw)) { [pscustomobject]@{} } else { $raw | ConvertFrom-Json }
        }
        catch {
            Write-Step "Existing settings.json is invalid. It will be recreated."
            $settings = [pscustomobject]@{}
        }
    }
    else {
        $settings = [pscustomobject]@{}
    }

    Set-Or-AddProperty $settings "TriplePressCount" 3
    Set-Or-AddProperty $settings "TriggerWindowMs" 500
    Set-Or-AddProperty $settings "SourceLanguage" "zh"
    Set-Or-AddProperty $settings "TargetLanguage" "en"

    Set-Or-AddProperty $settings "Provider" "LibreTranslate"
    Set-Or-AddProperty $settings "LibreTranslateUrl" "http://127.0.0.1:$Port/translate"
    Set-Or-AddProperty $settings "LibreTranslateApiKey" ""

    Set-Or-AddProperty $settings "OpenAiBaseUrl" "https://api.openai.com/v1"
    Set-Or-AddProperty $settings "OpenAiApiKey" ""
    Set-Or-AddProperty $settings "OpenAiModel" "gpt-4o-mini"

    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8
    Write-Step "App settings updated: $settingsPath"
}

Write-Step "Preparing local LibreTranslate one-click setup..."
Ensure-Docker
Ensure-Container
Wait-ServiceReady
Update-AppSettings

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Now open 'Triple Space Translator' and click Save Settings once (or restart app)." -ForegroundColor Green
Write-Host "Provider is set to LibreTranslate: http://127.0.0.1:$Port/translate" -ForegroundColor Green
