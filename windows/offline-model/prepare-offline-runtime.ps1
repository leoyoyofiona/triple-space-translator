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

    Write-Step "Ensuring bundled argostranslate package files via robust Python copy..."
    $copyArgosScriptPath = Join-Path $workDir "copy_argostranslate.py"
    @'
import importlib.util
import os
import pathlib
import shutil
import sys

target_site = pathlib.Path(os.environ["TST_TARGET_SITE"]).resolve()
target_pkg = target_site / "argostranslate"
spec = importlib.util.find_spec("argostranslate")
if spec is None:
    raise RuntimeError("argostranslate spec not found")

candidates = []
if spec.submodule_search_locations:
    candidates.extend(pathlib.Path(p).resolve() for p in spec.submodule_search_locations if p)

origin = spec.origin or ""
if origin:
    op = pathlib.Path(origin).resolve()
    if op.name.lower() == "__init__.py":
        candidates.append(op.parent)
    elif op.name.lower() == "argostranslate.py":
        # Defensive fallback for unexpected module layout.
        candidates.append(op.parent / "argostranslate")

for entry in sys.path:
    if not entry:
        continue
    p = pathlib.Path(entry).resolve() / "argostranslate"
    candidates.append(p)

seen = set()
deduped = []
for c in candidates:
    key = str(c).lower()
    if key in seen:
        continue
    seen.add(key)
    deduped.append(c)

source_pkg = None
for c in deduped:
    if c.exists() and (c / "translate.py").exists():
        source_pkg = c
        break

if source_pkg is None:
    raise RuntimeError(
        "could not locate argostranslate package dir with translate.py; "
        f"origin={origin}; candidates={[str(x) for x in deduped[:20]]}"
    )

shutil.rmtree(target_pkg, ignore_errors=True)
shutil.copytree(source_pkg, target_pkg)
print(f"SRC={source_pkg}")
print(f"DST={target_pkg}")
'@ | Set-Content -Path $copyArgosScriptPath -Encoding UTF8

    Invoke-Python @($copyArgosScriptPath) @{ TST_TARGET_SITE = $sitePackagesDir } | Out-Null

    $targetArgosDir = Join-Path $sitePackagesDir "argostranslate"
    $targetArgosTranslate = Join-Path $targetArgosDir "translate.py"
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

    Invoke-Python @(
        "-c",
        "import importlib.util, pathlib, os; spec=importlib.util.find_spec('argostranslate'); root=pathlib.Path(os.environ['TST_RUNTIME_ROOT']).resolve(); assert spec is not None, 'argostranslate spec missing'; c=[]; origin=spec.origin or ''; c.extend([pathlib.Path(origin).resolve()] if origin else []); c.extend(pathlib.Path(p).resolve() for p in (spec.submodule_search_locations or [])); assert c, 'argostranslate has no origin or package locations'; ok=any(str(p).lower().startswith(str(root).lower()) for p in c); assert ok, f'argostranslate outside runtime: {c}'"
    ) @{ TST_RUNTIME_ROOT = $pythonDir } | Out-Null

    Write-Step "Downloading offline wheelhouse (best effort for runtime self-heal)..."
    $wheelOk = $false
    try {
        Invoke-Python @("-m", "pip", "download", "--no-deps", "--only-binary=:all:", "--dest", $wheelhouseDir, "argostranslate==1.9.6") | Out-Null
        if (Get-ChildItem -Path $wheelhouseDir -Filter "argostranslate-*.whl" -ErrorAction SilentlyContinue) {
            $wheelOk = $true
        }
    }
    catch {
        Write-Step "Warning: wheelhouse download failed: $($_.Exception.Message)"
    }

    if (-not $wheelOk) {
        try {
            Invoke-Python @("-m", "pip", "wheel", "--no-deps", "--wheel-dir", $wheelhouseDir, "argostranslate==1.9.6") | Out-Null
            if (Get-ChildItem -Path $wheelhouseDir -Filter "argostranslate-*.whl" -ErrorAction SilentlyContinue) {
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

    Write-Step "Packing site-packages fallback archive (best effort)..."
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

    try {
        Invoke-Python @($packScriptPath, $sitePackagesDir, $sitePackagesArchive) | Out-Null
        if (-not (Test-Path $sitePackagesArchive)) {
            Write-Step "Warning: fallback archive not generated, will rely on bundled site-packages at runtime."
        }
    }
    catch {
        Write-Step "Warning: failed to pack fallback archive: $($_.Exception.Message)"
    }

    Write-Step "Offline runtime ready: $OutDir"
    Get-ChildItem -Path $OutDir -Recurse | Select-Object FullName, Length | Format-Table -AutoSize
}
finally {
    if (Test-Path $workDir) {
        Remove-Item -Recurse -Force $workDir
    }
}
