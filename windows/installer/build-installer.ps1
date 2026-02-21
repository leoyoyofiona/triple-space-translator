param(
    [string]$Configuration = "Release",
    [string]$AppVersion = "1.0.0",
    [switch]$SkipPublish,
    [switch]$SkipOfflineRuntime,
    [string]$IsccPath = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsRoot = Resolve-Path (Join-Path $scriptDir "..")
$projectPath = Join-Path $windowsRoot "TripleSpaceTranslator.Win\TripleSpaceTranslator.Win.csproj"
$distRoot = Join-Path $windowsRoot "dist"
$outX86 = Join-Path $distRoot "win-x86"
$outX64 = Join-Path $distRoot "win-x64"
$outArm64 = Join-Path $distRoot "win-arm64"
$outOfflineRuntime = Join-Path $distRoot "offline-runtime"
$setupOut = Join-Path $distRoot "installer"

New-Item -ItemType Directory -Force -Path $outX86 | Out-Null
New-Item -ItemType Directory -Force -Path $outX64 | Out-Null
New-Item -ItemType Directory -Force -Path $outArm64 | Out-Null
New-Item -ItemType Directory -Force -Path $setupOut | Out-Null

$offlinePrepareScript = Join-Path $windowsRoot "offline-model\prepare-offline-runtime.ps1"
if (-not $SkipOfflineRuntime) {
    if (-not (Test-Path $offlinePrepareScript)) {
        throw "Offline runtime prepare script not found: $offlinePrepareScript"
    }

    Write-Host "Preparing offline runtime..." -ForegroundColor Cyan
    try {
        # Invoke directly so any throw in prepare script stops this build with the real root-cause.
        & $offlinePrepareScript -OutDir $outOfflineRuntime
    }
    catch {
        throw "prepare-offline-runtime failed: $($_.Exception.Message)"
    }
}

if (-not (Test-Path $projectPath)) {
    throw "Project file not found: $projectPath. Run this script from windows\\installer inside the repo."
}

$dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnetCmd) {
    throw "dotnet SDK not found. Install .NET 8 SDK first: https://dotnet.microsoft.com/download"
}

if (-not $SkipPublish) {
    Write-Host "Publishing win-x86..." -ForegroundColor Cyan
    dotnet publish $projectPath -c $Configuration -r win-x86 --self-contained true /p:PublishSingleFile=true /p:PublishTrimmed=false -o $outX86
    Write-Host "Publishing win-x64..." -ForegroundColor Cyan
    dotnet publish $projectPath -c $Configuration -r win-x64 --self-contained true /p:PublishSingleFile=true /p:PublishTrimmed=false -o $outX64
    Write-Host "Publishing win-arm64..." -ForegroundColor Cyan
    dotnet publish $projectPath -c $Configuration -r win-arm64 --self-contained true /p:PublishSingleFile=true /p:PublishTrimmed=false -o $outArm64
}

$exeName = "TripleSpaceTranslator.Win.exe"
if (-not (Test-Path (Join-Path $outX86 $exeName))) {
    throw "Missing x86 publish output: $outX86\$exeName"
}
if (-not (Test-Path (Join-Path $outX64 $exeName))) {
    throw "Missing x64 publish output: $outX64\$exeName"
}
if (-not (Test-Path (Join-Path $outArm64 $exeName))) {
    throw "Missing arm64 publish output: $outArm64\$exeName"
}
if (-not $SkipOfflineRuntime) {
    if (-not (Test-Path (Join-Path $outOfflineRuntime "python\\python.exe"))) {
        throw "Missing offline runtime python: $outOfflineRuntime\\python\\python.exe"
    }
    if (-not (Test-Path (Join-Path $outOfflineRuntime "translate_once.py"))) {
        throw "Missing offline runtime script: $outOfflineRuntime\\translate_once.py"
    }
    if (-not (Test-Path (Join-Path $outOfflineRuntime "offline-site-packages.zip"))) {
        throw "Missing offline runtime dependency archive: $outOfflineRuntime\\offline-site-packages.zip"
    }
}

Copy-Item (Join-Path $outX86 $exeName) (Join-Path $setupOut "TripleSpaceTranslator-win-x86.exe") -Force
Copy-Item (Join-Path $outX64 $exeName) (Join-Path $setupOut "TripleSpaceTranslator-win-x64.exe") -Force
Copy-Item (Join-Path $outArm64 $exeName) (Join-Path $setupOut "TripleSpaceTranslator-win-arm64.exe") -Force

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

if (-not (Test-Path $setupOut)) {
    throw "Installer output directory missing: $setupOut"
}

$expectedInstaller = Join-Path $setupOut "TripleSpaceTranslator-Setup-$AppVersion.exe"
if (-not (Test-Path $expectedInstaller)) {
    $candidates = Get-ChildItem $setupOut -Filter "TripleSpaceTranslator-Setup-*.exe" -File |
        Sort-Object LastWriteTime -Descending

    if ($candidates.Count -gt 0) {
        Copy-Item $candidates[0].FullName $expectedInstaller -Force
        Write-Host "Normalized installer file name to: $expectedInstaller" -ForegroundColor Yellow
    } else {
        throw "Inno Setup did not generate installer exe in $setupOut"
    }
}

Write-Host "Done. Installer output:" -ForegroundColor Green
Get-ChildItem $setupOut | Select-Object FullName, Length, LastWriteTime
