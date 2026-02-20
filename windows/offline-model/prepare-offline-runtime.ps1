param(
    [string]$OutDir = "",
    [string]$PythonVersion = "3.11.9",
    [switch]$SkipModelInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsRoot = Resolve-Path (Join-Path $scriptDir "..")
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $windowsRoot "dist\offline-runtime"
}

$workDir = Join-Path $env:TEMP ("tst-offline-runtime-" + [Guid]::NewGuid().ToString("N"))
$pythonDir = Join-Path $OutDir "python"
$offlineHome = Join-Path $OutDir "home"
$sitePackagesDir = Join-Path $pythonDir "Lib\\site-packages"
$embedZip = Join-Path $workDir "python-embed.zip"
$getPip = Join-Path $workDir "get-pip.py"

function Write-Step([string]$msg) {
    Write-Host "[offline-runtime] $msg" -ForegroundColor Cyan
}

function Invoke-Python([string[]]$args, [hashtable]$extraEnv = @{}) {
    $pythonExe = Join-Path $pythonDir "python.exe"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $pythonExe
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    foreach ($a in $args) {
        [void]$psi.ArgumentList.Add($a)
    }

    $psi.Environment["PYTHONUTF8"] = "1"
    foreach ($key in $extraEnv.Keys) {
        $psi.Environment[$key] = [string]$extraEnv[$key]
    }

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    if ($p.ExitCode -ne 0) {
        throw "python failed (exit=$($p.ExitCode)): $stderr"
    }

    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        Write-Host $stdout
    }
}

try {
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

    if (Test-Path $pythonDir) {
        Remove-Item -Recurse -Force $pythonDir
    }

    if (Test-Path $offlineHome) {
        Remove-Item -Recurse -Force $offlineHome
    }

    New-Item -ItemType Directory -Force -Path $pythonDir | Out-Null
    New-Item -ItemType Directory -Force -Path $offlineHome | Out-Null
    New-Item -ItemType Directory -Force -Path $sitePackagesDir | Out-Null

    $pythonUrl = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"
    Write-Step "Downloading Python embeddable runtime: $pythonUrl"
    Invoke-WebRequest -Uri $pythonUrl -OutFile $embedZip

    Write-Step "Extracting Python runtime..."
    Expand-Archive -Path $embedZip -DestinationPath $pythonDir -Force

    $pthFile = Get-ChildItem -Path $pythonDir -Filter "python*._pth" | Select-Object -First 1
    if (-not $pthFile) {
        throw "python*._pth not found in embedded runtime"
    }

    $pthContent = Get-Content -Path $pthFile.FullName
    $updated = @()
    $hasSitePackages = $false
    foreach ($line in $pthContent) {
        if ($line -match '^#\s*import\s+site\s*$') {
            $updated += 'import site'
            continue
        }

        if ($line -eq 'Lib\\site-packages') {
            $hasSitePackages = $true
        }

        $updated += $line
    }

    if (-not $hasSitePackages) {
        $updated += 'Lib\\site-packages'
    }

    # Important: _pth must be written without BOM, otherwise python311.zip path may become "\ufeffpython311.zip"
    # and embedded Python fails with "No module named 'encodings'".
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $pthFile.FullName,
        (($updated -join [Environment]::NewLine) + [Environment]::NewLine),
        $utf8NoBom
    )

    Write-Step "Installing pip..."
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $getPip
    Invoke-Python @($getPip)

    Write-Step "Installing offline engine dependencies into bundled runtime..."
    Invoke-Python @("-m", "pip", "install", "--no-warn-script-location", "--target", $sitePackagesDir, "argostranslate==1.9.6")
    Invoke-Python @("-c", "import argostranslate,sys;print('argostranslate=',argostranslate.__version__);print('site=',sys.path)")

    if (-not $SkipModelInstall) {
        Write-Step "Installing zh<->en model packages..."

        $installScriptPath = Join-Path $workDir "install_models.py"
        @'
import argostranslate.package

pairs = [("zh", "en"), ("en", "zh")]
available = argostranslate.package.get_available_packages()

for source, target in pairs:
    candidates = [p for p in available if p.from_code == source and p.to_code == target]
    if not candidates:
        raise RuntimeError(f"No package found for {source}->{target}")

    package = candidates[0]
    path = package.download()
    argostranslate.package.install_from_path(path)
    print(f"Installed {source}->{target}")
'@ | Set-Content -Path $installScriptPath -Encoding UTF8

        Invoke-Python @($installScriptPath) @{ HOME = $offlineHome; USERPROFILE = $offlineHome }
    }

    Copy-Item -Path (Join-Path $scriptDir "translate_once.py") -Destination (Join-Path $OutDir "translate_once.py") -Force

    Write-Step "Offline runtime ready: $OutDir"
    Get-ChildItem -Path $OutDir -Recurse | Select-Object FullName, Length | Format-Table -AutoSize
}
finally {
    if (Test-Path $workDir) {
        Remove-Item -Recurse -Force $workDir
    }
}
