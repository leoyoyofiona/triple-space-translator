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
$wheelhouseDir = Join-Path $OutDir "wheelhouse"
$sitePackagesDir = Join-Path (Join-Path $pythonDir "Lib") "site-packages"
$sitePackagesArchive = Join-Path $OutDir "offline-site-packages.zip"
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
    $psi.Environment["PYTHONNOUSERSITE"] = "1"
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

    return $stdout
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
    if (Test-Path $wheelhouseDir) {
        Remove-Item -Recurse -Force $wheelhouseDir
    }
    if (Test-Path $sitePackagesArchive) {
        Remove-Item -Force $sitePackagesArchive
    }

    New-Item -ItemType Directory -Force -Path $pythonDir | Out-Null
    New-Item -ItemType Directory -Force -Path $offlineHome | Out-Null
    New-Item -ItemType Directory -Force -Path $wheelhouseDir | Out-Null
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

        if ($line -eq 'Lib\site-packages') {
            $hasSitePackages = $true
        }

        $updated += $line
    }

    if (-not $hasSitePackages) {
        $updated += 'Lib\site-packages'
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
    # Install directly from index during build (CI has network), package ships with installed files for offline runtime use.
    # Embedded Python behaves most consistently when dependencies are under Lib\site-packages.
    Invoke-Python @("-m", "pip", "install", "--target", $sitePackagesDir, "--upgrade", "--force-reinstall", "--ignore-installed", "argostranslate==1.9.6") | Out-Null

    try {
        Invoke-Python @("-c", "import argostranslate;print('argostranslate_import_ok')") | Out-Null
    }
    catch {
        Write-Step "Primary target import check failed, retrying install to python root..."
        Invoke-Python @("-m", "pip", "install", "--target", $pythonDir, "--upgrade", "--force-reinstall", "--ignore-installed", "argostranslate==1.9.6") | Out-Null
        try {
            Invoke-Python @("-c", "import argostranslate;print('argostranslate_import_ok')") | Out-Null
        }
        catch {
            $topLevel = ""
            try {
                $topLevel = (Get-ChildItem -Path $sitePackagesDir -Name -ErrorAction SilentlyContinue | Select-Object -First 20) -join ", "
            }
            catch {
                $topLevel = "<unavailable>"
            }
            throw "argostranslate import verification failed after retry. site-packages top-level: $topLevel"
        }
    }

    Write-Step "Downloading offline wheelhouse (best effort for runtime self-heal)..."
    try {
        Invoke-Python @("-m", "pip", "download", "--dest", $wheelhouseDir, "argostranslate==1.9.6") | Out-Null
    }
    catch {
        Write-Step "Warning: wheelhouse download skipped: $($_.Exception.Message)"
    }

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

    Write-Step "Running offline runtime smoke test..."
    try {
        Invoke-Python @(
            "-c",
            "import argostranslate.translate as t; langs=t.get_installed_languages(); en=next((x for x in langs if x.code.startswith('en')),None); zh=next((x for x in langs if x.code.startswith('zh')),None); assert en is not None and zh is not None, 'missing en/zh'; _ = en.get_translation(zh).translate('hello')"
        ) @{
            HOME = $offlineHome
            USERPROFILE = $offlineHome
            TST_OFFLINE_DISABLE_SELF_HEAL = "1"
        } | Out-Null
    }
    catch {
        throw "Offline runtime smoke test failed: $($_.Exception.Message)"
    }

    Write-Step "Packing site-packages fallback archive..."
    $packScriptPath = Join-Path $workDir "pack_site_packages.py"
    @'
import pathlib
import sys
import zipfile

src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2])

if not src.exists():
    raise RuntimeError(f"source not found: {src}")

with zipfile.ZipFile(dst, "w", compression=zipfile.ZIP_DEFLATED, allowZip64=True) as zf:
    for p in src.rglob("*"):
        if p.is_file():
            zf.write(p, p.relative_to(src).as_posix())

print(dst)
'@ | Set-Content -Path $packScriptPath -Encoding UTF8

    Invoke-Python @($packScriptPath, $sitePackagesDir, $sitePackagesArchive) | Out-Null

    if (-not (Test-Path $sitePackagesArchive)) {
        throw "Missing site-packages fallback archive: $sitePackagesArchive"
    }

    # Keep installer robust on end-user machines by loading dependencies from user-writable path at runtime.
    Get-ChildItem -Path $sitePackagesDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Write-Step "Offline runtime ready: $OutDir"
    Get-ChildItem -Path $OutDir -Recurse | Select-Object FullName, Length | Format-Table -AutoSize
}
finally {
    if (Test-Path $workDir) {
        Remove-Item -Recurse -Force $workDir
    }
}
