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
    # Ensure package files exist even when dependency resolver behaves unexpectedly.
    Invoke-Python @("-m", "pip", "install", "--target", $sitePackagesDir, "--upgrade", "--force-reinstall", "--ignore-installed", "--no-deps", "argostranslate==1.9.6") | Out-Null
    # Also install to python root as fallback source for deterministic copy into site-packages.
    Invoke-Python @("-m", "pip", "install", "--target", $pythonDir, "--upgrade", "--force-reinstall", "--ignore-installed", "--no-deps", "argostranslate==1.9.6") | Out-Null

    try {
        Invoke-Python @("-c", "import argostranslate.translate as _t;print('argostranslate_translate_import_ok')") | Out-Null
    }
    catch {
        Write-Step "Primary target import check failed, retrying install to python root..."
        Invoke-Python @("-m", "pip", "install", "--target", $pythonDir, "--upgrade", "--force-reinstall", "--ignore-installed", "argostranslate==1.9.6") | Out-Null
        try {
            Invoke-Python @("-c", "import argostranslate.translate as _t;print('argostranslate_translate_import_ok')") | Out-Null
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

    Write-Step "Ensuring bundled argostranslate package files..."
    $targetArgosDir = Join-Path $sitePackagesDir "argostranslate"
    $targetArgosTranslate = Join-Path $targetArgosDir "translate.py"
    $targetArgosInit = Join-Path $targetArgosDir "__init__.py"
    $targetArgosPackage = Join-Path $targetArgosDir "package.py"
    $bootstrapWheelDir = Join-Path $workDir "bootstrap-wheelhouse"

    $hasTargetPackage = (Test-Path $targetArgosTranslate) -and (Test-Path $targetArgosInit) -and (Test-Path $targetArgosPackage)
    if ($hasTargetPackage) {
        Write-Step "argostranslate already present in bundled site-packages (from pip target install)."
    }

    $needWheelFallback = -not $hasTargetPackage
    if ($needWheelFallback) {
        Write-Step "Trying wheel extraction fallback for argostranslate..."
        if (Test-Path $bootstrapWheelDir) {
            Remove-Item -Recurse -Force $bootstrapWheelDir
        }
        New-Item -ItemType Directory -Force -Path $bootstrapWheelDir | Out-Null

        $wheelFile = $null
        try {
            Invoke-Python @("-m", "pip", "download", "--no-deps", "--only-binary=:all:", "--dest", $bootstrapWheelDir, "argostranslate==1.9.6") | Out-Null
        }
        catch {
            Write-Step "Warning: wheel download failed: $($_.Exception.Message)"
        }

        if (-not (Get-ChildItem -Path $bootstrapWheelDir -Filter "argostranslate-*.whl" -ErrorAction SilentlyContinue)) {
            try {
                Invoke-Python @("-m", "pip", "wheel", "--no-deps", "--wheel-dir", $bootstrapWheelDir, "argostranslate==1.9.6") | Out-Null
            }
            catch {
                Write-Step "Warning: wheel build failed: $($_.Exception.Message)"
            }
        }

        $wheelCandidate = Get-ChildItem -Path $bootstrapWheelDir -Filter "argostranslate-*.whl" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($wheelCandidate) {
            $wheelFile = $wheelCandidate.FullName
        }

        if ([string]::IsNullOrWhiteSpace($wheelFile)) {
            Write-Step "Trying direct PyPI wheel download fallback..."
            try {
                $pypiJson = Join-Path $bootstrapWheelDir "argostranslate-1.9.6.json"
                Invoke-WebRequest -Uri "https://pypi.org/pypi/argostranslate/1.9.6/json" -OutFile $pypiJson
                $meta = Get-Content -Path $pypiJson -Raw | ConvertFrom-Json
                $wheelUrl = ($meta.urls | Where-Object { $_.filename -like "argostranslate-*.whl" } | Select-Object -First 1).url
                if (-not [string]::IsNullOrWhiteSpace($wheelUrl)) {
                    $wheelName = Split-Path $wheelUrl -Leaf
                    $wheelPath = Join-Path $bootstrapWheelDir $wheelName
                    Invoke-WebRequest -Uri $wheelUrl -OutFile $wheelPath
                    if (Test-Path $wheelPath) {
                        $wheelFile = $wheelPath
                    }
                }
            }
            catch {
                Write-Step "Warning: direct PyPI wheel download failed: $($_.Exception.Message)"
            }
        }

        if ([string]::IsNullOrWhiteSpace($wheelFile)) {
            $wheelDirList = ""
            try {
                $wheelDirList = (Get-ChildItem -Path $bootstrapWheelDir -Name -ErrorAction SilentlyContinue | Select-Object -First 50) -join ", "
            }
            catch {
                $wheelDirList = "<unavailable>"
            }
            throw "Wheel fallback unavailable: no argostranslate wheel in $bootstrapWheelDir; files=$wheelDirList"
        }

        Write-Step "Wheel selected: $wheelFile"
        $wheelExtractDir = Join-Path $workDir "wheel-extract"
        if (Test-Path $wheelExtractDir) {
            Remove-Item -Recurse -Force $wheelExtractDir
        }
        New-Item -ItemType Directory -Force -Path $wheelExtractDir | Out-Null
        $wheelAsZip = Join-Path $workDir "argostranslate-wheel.zip"
        Copy-Item -Path $wheelFile -Destination $wheelAsZip -Force
        Expand-Archive -Path $wheelAsZip -DestinationPath $wheelExtractDir -Force

        $sourceTranslate = Get-ChildItem -Path $wheelExtractDir -Recurse -File -Filter "translate.py" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '[\\/]argostranslate[\\/]translate\.py$' } |
            Select-Object -First 1

        if (-not $sourceTranslate) {
            $wheelTop = ""
            try {
                $wheelTop = (Get-ChildItem -Path $wheelExtractDir -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 50 -ExpandProperty FullName) -join "; "
            }
            catch {
                $wheelTop = "<unavailable>"
            }
            throw "Wheel extraction failed: translate.py not found under argostranslate; wheel=$wheelFile; extracted_files=$wheelTop"
        }

        $sourceArgosDir = Split-Path -Parent $sourceTranslate.FullName
        if (Test-Path $targetArgosDir) {
            Remove-Item -Recurse -Force $targetArgosDir
        }
        Get-ChildItem -Path $sitePackagesDir -Directory -Filter "argostranslate-*.dist-info" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue
        }
        Copy-Item -Path $sourceArgosDir -Destination $sitePackagesDir -Recurse -Force
        Write-Step "WHEEL_EXTRACT_OK source=$sourceArgosDir target=$targetArgosDir"
    }

    if (-not (Test-Path $targetArgosTranslate)) {
        $debugList = ""
        try {
            $debugList = (Get-ChildItem -Path $targetArgosDir -Name -ErrorAction SilentlyContinue | Select-Object -First 30) -join ", "
        }
        catch {
            $debugList = "<unavailable>"
        }
        throw "Bundled argostranslate package missing translate.py after copy: $targetArgosTranslate; contents=$debugList"
    }
    if (-not (Test-Path $targetArgosInit)) {
        throw "Bundled argostranslate package missing __init__.py after copy: $targetArgosInit"
    }
    if (-not (Test-Path $targetArgosPackage)) {
        throw "Bundled argostranslate package missing package.py after copy: $targetArgosPackage"
    }

    Write-Step "Installing core runtime dependencies for offline translation..."
    $runtimeDeps = @(
        "ctranslate2>=4.0,<5",
        "sentencepiece==0.2.0",
        "sacremoses==0.0.53",
        "packaging"
    )
    $runtimeDepArgs = @("-m", "pip", "install", "--target", $sitePackagesDir, "--upgrade", "--force-reinstall", "--ignore-installed") + $runtimeDeps
    Invoke-Python $runtimeDepArgs | Out-Null

    $verifyCoreScriptPath = Join-Path $workDir "verify_offline_core.py"
    @'
import importlib.util
import os
import pathlib
import sys
import types

os.environ["ARGOS_STANZA_AVAILABLE"] = "0"
if importlib.util.find_spec("stanza") is None:
    m = types.ModuleType("stanza")
    m.Pipeline = object
    sys.modules["stanza"] = m

import ctranslate2  # noqa: F401
import sentencepiece  # noqa: F401
import sacremoses  # noqa: F401
import argostranslate.translate as _t  # noqa: F401

root = pathlib.Path(os.environ["TST_RUNTIME_ROOT"]).resolve()
aspec = importlib.util.find_spec("argostranslate")
assert aspec is not None, "argostranslate spec missing"
candidates = []
origin = aspec.origin or ""
if origin:
    candidates.append(pathlib.Path(origin).resolve())
for p in aspec.submodule_search_locations or []:
    candidates.append(pathlib.Path(p).resolve())
assert candidates, "argostranslate has no origin or package locations"
assert any(str(p).lower().startswith(str(root).lower()) for p in candidates), f"argostranslate outside runtime: {candidates}"
print("offline_runtime_core_import_ok")
'@ | Set-Content -Path $verifyCoreScriptPath -Encoding UTF8
    Invoke-Python @($verifyCoreScriptPath) @{ TST_RUNTIME_ROOT = $pythonDir } | Out-Null

    Write-Step "Downloading offline wheelhouse (best effort for runtime self-heal)..."
    $wheelOk = $false
    $wheelSpecs = @(
        "argostranslate==1.9.6",
        "ctranslate2>=4.0,<5",
        "sentencepiece==0.2.0",
        "sacremoses==0.0.53",
        "packaging"
    )
    try {
        $downloadArgs = @("-m", "pip", "download", "--only-binary=:all:", "--dest", $wheelhouseDir) + $wheelSpecs
        Invoke-Python $downloadArgs | Out-Null
        if ((Get-ChildItem -Path $wheelhouseDir -Filter "argostranslate-*.whl" -ErrorAction SilentlyContinue) -and
            (Get-ChildItem -Path $wheelhouseDir -Filter "ctranslate2-*.whl" -ErrorAction SilentlyContinue) -and
            (Get-ChildItem -Path $wheelhouseDir -Filter "sentencepiece-*.whl" -ErrorAction SilentlyContinue)) {
            $wheelOk = $true
        }
    }
    catch {
        Write-Step "Warning: wheelhouse download failed: $($_.Exception.Message)"
    }

    if (-not $wheelOk) {
        try {
            $wheelBuildArgs = @("-m", "pip", "wheel", "--wheel-dir", $wheelhouseDir) + $wheelSpecs
            Invoke-Python $wheelBuildArgs | Out-Null
            if ((Get-ChildItem -Path $wheelhouseDir -Filter "argostranslate-*.whl" -ErrorAction SilentlyContinue) -and
                (Get-ChildItem -Path $wheelhouseDir -Filter "ctranslate2-*.whl" -ErrorAction SilentlyContinue) -and
                (Get-ChildItem -Path $wheelhouseDir -Filter "sentencepiece-*.whl" -ErrorAction SilentlyContinue)) {
                $wheelOk = $true
            }
        }
        catch {
            Write-Step "Warning: wheelhouse build failed: $($_.Exception.Message)"
        }
    }

    if (-not $wheelOk) {
        Write-Step "Warning: wheelhouse unavailable; runtime will rely on bundled site-packages self-heal."
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
        $smokeScriptPath = Join-Path $workDir "offline_smoke_test.py"
        @'
import importlib.util
import os
import sys
import types

os.environ["ARGOS_STANZA_AVAILABLE"] = "0"
if importlib.util.find_spec("stanza") is None:
    m = types.ModuleType("stanza")
    m.Pipeline = object
    sys.modules["stanza"] = m

import argostranslate.translate as t

langs = t.get_installed_languages()
en = next((x for x in langs if x.code.startswith("en")), None)
zh = next((x for x in langs if x.code.startswith("zh")), None)
assert en is not None and zh is not None, "missing en/zh"
translation = en.get_translation(zh)
assert translation is not None, "missing en->zh translation"
_ = translation.translate("hello")
'@ | Set-Content -Path $smokeScriptPath -Encoding UTF8

        Invoke-Python @($smokeScriptPath) @{
            HOME = $offlineHome
            USERPROFILE = $offlineHome
            TST_OFFLINE_DISABLE_SELF_HEAL = "1"
            ARGOS_STANZA_AVAILABLE = "0"
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

    $archivePacked = $false
    try {
        Invoke-Python @($packScriptPath, $sitePackagesDir, $sitePackagesArchive) | Out-Null
        if (Test-Path $sitePackagesArchive) {
            $archivePacked = $true
        }
    }
    catch {
        Write-Step "Warning: python zip pack failed: $($_.Exception.Message)"
    }

    if (-not $archivePacked) {
        Write-Step "Trying .NET fallback for site-packages archive..."
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            if (Test-Path $sitePackagesArchive) {
                Remove-Item -Force $sitePackagesArchive
            }
            [System.IO.Compression.ZipFile]::CreateFromDirectory(
                $sitePackagesDir,
                $sitePackagesArchive,
                [System.IO.Compression.CompressionLevel]::Optimal,
                $false
            )
            if (Test-Path $sitePackagesArchive) {
                $archivePacked = $true
            }
        }
        catch {
            Write-Step "Warning: .NET zip pack failed: $($_.Exception.Message)"
        }
    }

    if (-not $archivePacked) {
        throw "Failed to generate fallback archive: $sitePackagesArchive"
    }

    $archiveSize = (Get-Item -Path $sitePackagesArchive).Length
    Write-Step "Fallback archive ready: $sitePackagesArchive ($archiveSize bytes)"

    $keyFiles = @($targetArgosInit, $targetArgosTranslate, $targetArgosPackage, $sitePackagesArchive)
    foreach ($f in $keyFiles) {
        if (-not (Test-Path $f)) {
            throw "Offline runtime key file missing at finalize stage: $f"
        }
    }

    $finalVerifyCoreScriptPath = Join-Path $workDir "verify_offline_core_final.py"
    @'
import importlib.util
import pathlib
import os

root = pathlib.Path(os.environ["TST_RUNTIME_ROOT"]).resolve()

def assert_module_in_runtime(name: str):
    spec = importlib.util.find_spec(name)
    if spec is None:
        raise RuntimeError(f"{name} spec missing")
    candidates = []
    origin = spec.origin or ""
    if origin:
        candidates.append(pathlib.Path(origin).resolve())
    for p in spec.submodule_search_locations or []:
        candidates.append(pathlib.Path(p).resolve())
    if not candidates:
        raise RuntimeError(f"{name} has no origin/submodule locations")
    if not any(str(p).lower().startswith(str(root).lower()) for p in candidates):
        raise RuntimeError(f"{name} is outside runtime root: {candidates}")
    return candidates[0]

for mod in ("argostranslate", "ctranslate2", "sentencepiece", "sacremoses", "packaging"):
    loc = assert_module_in_runtime(mod)
    print(f"FINAL_CORE_OK {mod} {loc}")
'@ | Set-Content -Path $finalVerifyCoreScriptPath -Encoding UTF8
    Invoke-Python @($finalVerifyCoreScriptPath) @{ TST_RUNTIME_ROOT = $pythonDir } | Out-Null

    Write-Step "Offline runtime ready: $OutDir"
    Get-ChildItem -Path $OutDir -Recurse | Select-Object FullName, Length | Format-Table -AutoSize
}
finally {
    if (Test-Path $workDir) {
        Remove-Item -Recurse -Force $workDir
    }
}
