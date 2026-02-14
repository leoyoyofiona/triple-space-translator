param(
    [string]$Configuration = "Release",
    [string]$AppVersion = "1.0.0",
    [switch]$SkipPublish,
    [string]$IsccPath = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsRoot = Resolve-Path (Join-Path $scriptDir "..")
$projectPath = Join-Path $windowsRoot "TripleSpaceTranslator.Win\TripleSpaceTranslator.Win.csproj"
$distRoot = Join-Path $windowsRoot "dist"
$outX64 = Join-Path $distRoot "win-x64"
$outArm64 = Join-Path $distRoot "win-arm64"
$setupOut = Join-Path $distRoot "installer"

New-Item -ItemType Directory -Force -Path $outX64 | Out-Null
New-Item -ItemType Directory -Force -Path $outArm64 | Out-Null
New-Item -ItemType Directory -Force -Path $setupOut | Out-Null

if (-not (Test-Path $projectPath)) {
    throw "Project file not found: $projectPath. Run this script from windows\\installer inside the repo."
}

$dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnetCmd) {
    throw "dotnet SDK not found. Install .NET 8 SDK first: https://dotnet.microsoft.com/download"
}

if (-not $SkipPublish) {
    Write-Host "Publishing win-x64..." -ForegroundColor Cyan
    dotnet publish $projectPath -c $Configuration -r win-x64 --self-contained true /p:PublishSingleFile=true /p:PublishTrimmed=false -o $outX64
    Write-Host "Publishing win-arm64..." -ForegroundColor Cyan
    dotnet publish $projectPath -c $Configuration -r win-arm64 --self-contained true /p:PublishSingleFile=true /p:PublishTrimmed=false -o $outArm64
}

$exeName = "TripleSpaceTranslator.Win.exe"
if (-not (Test-Path (Join-Path $outX64 $exeName))) {
    throw "Missing x64 publish output: $outX64\$exeName"
}
if (-not (Test-Path (Join-Path $outArm64 $exeName))) {
    throw "Missing arm64 publish output: $outArm64\$exeName"
}

if ([string]::IsNullOrWhiteSpace($IsccPath)) {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
    )

    $IsccPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($IsccPath) -or -not (Test-Path $IsccPath)) {
    throw "ISCC.exe not found. Install Inno Setup 6 or pass -IsccPath."
}

$issPath = Join-Path $scriptDir "TripleSpaceTranslator.iss"
if (-not (Test-Path $issPath)) {
    throw "Inno Setup script not found: $issPath"
}

Write-Host "Building installer with Inno Setup..." -ForegroundColor Cyan
& $IsccPath "/DAppVersion=$AppVersion" $issPath

Write-Host "Done. Installer output:" -ForegroundColor Green
Get-ChildItem $setupOut | Select-Object FullName, Length, LastWriteTime
