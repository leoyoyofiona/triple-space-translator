#!/usr/bin/env python3
import argparse
import importlib.util
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import zipfile


def normalize_lang(value: str) -> str:
    if not value:
        return ""
    v = value.strip().lower()
    if v.startswith("zh"):
        return "zh"
    if v.startswith("en"):
        return "en"
    if "-" in v:
        return v.split("-", 1)[0]
    return v


def fail(msg: str, code: int = 2) -> None:
    print(msg, file=sys.stderr)
    sys.exit(code)


def bootstrap_stanza_compat() -> None:
    # We do not rely on stanza runtime in this app path.
    os.environ.setdefault("ARGOS_STANZA_AVAILABLE", "0")
    if importlib.util.find_spec("stanza") is not None:
        return

    import types

    stub = types.ModuleType("stanza")

    class _PipelineUnavailable:
        def __init__(self, *args, **kwargs):
            raise RuntimeError("stanza runtime is not bundled")

    stub.Pipeline = _PipelineUnavailable
    sys.modules.setdefault("stanza", stub)


def bootstrap_bundled_site_packages() -> None:
    runtime_root = pathlib.Path(__file__).resolve().parent
    python_root = runtime_root / "python"
    extra_user_site = os.environ.get("TST_OFFLINE_USER_SITE", "").strip()
    candidates = [
        python_root / "Lib" / "site-packages",
        python_root,
        python_root / "python311.zip",
        pathlib.Path(extra_user_site) if extra_user_site else None,
    ]

    for path in candidates:
        if path and path.exists():
            value = str(path)
            if value not in sys.path:
                sys.path.insert(0, value)


def bootstrap_seed_home() -> None:
    seed_home = os.environ.get("TST_OFFLINE_SEED_HOME", "").strip()
    if not seed_home:
        return

    seed_path = pathlib.Path(seed_home)
    if not seed_path.exists():
        return

    user_home = pathlib.Path(os.path.expanduser("~"))
    target_packages = user_home / ".local" / "share" / "argos-translate" / "packages"
    need_copy = not target_packages.exists() or not any(target_packages.iterdir())
    if not need_copy:
        return

    seed_local = seed_path / ".local"
    seed_config = seed_path / ".config"
    if seed_local.exists():
        shutil.copytree(seed_local, user_home / ".local", dirs_exist_ok=True)
    if seed_config.exists():
        shutil.copytree(seed_config, user_home / ".config", dirs_exist_ok=True)


def _clear_import_cache() -> None:
    # Keep binary extension modules (e.g. ctranslate2/sentencepiece) loaded in-process.
    # Re-importing them from a different path can trigger "type ... is already registered".
    prefixes = ("argostranslate", "sacremoses", "packaging", "numpy", "yaml")
    for name in list(sys.modules.keys()):
        for prefix in prefixes:
            if name == prefix or name.startswith(prefix + "."):
                sys.modules.pop(name, None)
                break


def _rmtree_force(path: pathlib.Path) -> None:
    def _on_error(func, name, _exc_info):
        try:
            os.chmod(name, 0o700)
            func(name)
        except Exception:
            pass

    if not path.exists():
        return
    try:
        shutil.rmtree(path, onerror=_on_error)
    except Exception:
        pass


def _remove_path_force(path: pathlib.Path) -> None:
    if not path.exists():
        return
    if path.is_dir():
        _rmtree_force(path)
        return
    try:
        os.chmod(path, 0o600)
    except Exception:
        pass
    try:
        path.unlink()
    except Exception:
        pass


def _ensure_writable_dir(path: pathlib.Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    probe = path / f".tst_write_probe_{os.getpid()}"
    with open(probe, "w", encoding="utf-8") as fp:
        fp.write("ok")
    try:
        probe.unlink()
    except OSError:
        pass


def _dedupe_paths(paths: list[pathlib.Path]) -> list[pathlib.Path]:
    seen: set[str] = set()
    out: list[pathlib.Path] = []
    for p in paths:
        key = str(p)
        if key in seen:
            continue
        seen.add(key)
        out.append(p)
    return out


def _activate_user_site(current: pathlib.Path, all_candidates: list[pathlib.Path]) -> None:
    current_text = str(current)
    for candidate in all_candidates:
        value = str(candidate)
        while value in sys.path:
            sys.path.remove(value)
    if current_text not in sys.path:
        sys.path.insert(0, current_text)


def ensure_argostranslate_available() -> None:
    def _verify_runtime_imports() -> None:
        import argostranslate.translate  # noqa: F401
        import ctranslate2  # noqa: F401
        import sentencepiece  # noqa: F401
        import numpy  # noqa: F401
        import yaml  # noqa: F401
        import packaging  # noqa: F401

    first_error = None
    try:
        _verify_runtime_imports()
        return
    except Exception as first_exc:
        first_error = first_exc
        disable_self_heal = os.environ.get("TST_OFFLINE_DISABLE_SELF_HEAL", "").strip() == "1"
        if disable_self_heal:
            fail(f"argostranslate import failed (self-heal disabled): {first_exc}; sys.path={sys.path}")

    runtime_root = pathlib.Path(__file__).resolve().parent
    python_exe = runtime_root / "python" / "python.exe"
    wheelhouse = runtime_root / "wheelhouse"
    site_archive = runtime_root / "offline-site-packages.zip"
    bundled_site = runtime_root / "python" / "Lib" / "site-packages"
    bundled_argos = bundled_site / "argostranslate"
    bundled_root_argos = runtime_root / "python" / "argostranslate"
    bundled_ctranslate = bundled_site / "ctranslate2"
    bundled_sentencepiece = bundled_site / "sentencepiece"
    bundled_ctranslate_ext = any(bundled_ctranslate.glob("_ext*.pyd")) if bundled_ctranslate.exists() else False
    bundled_sentencepiece_ext = any(bundled_sentencepiece.glob("_sentencepiece*.pyd")) if bundled_sentencepiece.exists() else False
    wheel_candidates = sorted(wheelhouse.glob("*.whl")) if wheelhouse.exists() else []

    primary_user_site = os.environ.get("TST_OFFLINE_USER_SITE", "").strip()
    if not primary_user_site:
        local_app_data = os.environ.get("LOCALAPPDATA", "").strip()
        if local_app_data:
            primary_user_site = str(pathlib.Path(local_app_data) / "TripleSpaceTranslator" / "offline-site-packages")
        else:
            primary_user_site = str(pathlib.Path(os.path.expanduser("~")) / ".triple-space-translator" / "site-packages")

    fallback_root = os.environ.get("TST_OFFLINE_ALT_USER_SITE_ROOT", "").strip()
    if fallback_root:
        fallback_base = pathlib.Path(fallback_root)
    else:
        fallback_base = pathlib.Path(tempfile.gettempdir()) / "TripleSpaceTranslator"

    alt_user_site = os.environ.get("TST_OFFLINE_ALT_USER_SITE", "").strip()
    home_user_site = pathlib.Path(os.path.expanduser("~")) / ".triple-space-translator" / "site-packages"
    user_site_candidates = _dedupe_paths(
        [
            fallback_base / "offline-site-packages",
            fallback_base / f"offline-site-packages-{os.getpid()}",
            pathlib.Path(primary_user_site),
            pathlib.Path(alt_user_site) if alt_user_site else pathlib.Path(primary_user_site),
            home_user_site,
        ]
    )

    attempt_errors: list[str] = []
    for user_site_path in user_site_candidates:
        user_site = str(user_site_path)
        candidate_error: Exception = first_error if first_error is not None else RuntimeError("argostranslate import failed")
        try:
            _ensure_writable_dir(user_site_path)
        except Exception as writable_exc:
            attempt_errors.append(f"user_site_not_writable={user_site}; err={writable_exc}")
            continue

        # If previous runs wrote an incomplete environment, clear stale core folders first.
        cleanup_failed: list[str] = []
        for stale_name in ("argostranslate", "ctranslate2", "sentencepiece", "sacremoses", "packaging", "numpy", "yaml"):
            stale_target = user_site_path / stale_name
            _remove_path_force(stale_target)
            if stale_target.exists():
                cleanup_failed.append(str(stale_target))
        for stale_glob in ("*.dist-info", "*.data"):
            for stale_path in user_site_path.glob(stale_glob):
                _remove_path_force(stale_path)
                if stale_path.exists():
                    cleanup_failed.append(str(stale_path))
        if cleanup_failed:
            attempt_errors.append(f"user_site={user_site}; cleanup_failed={cleanup_failed}")
            continue

        _activate_user_site(user_site_path, user_site_candidates)
        _clear_import_cache()

        # First self-heal path: copy packaged site-packages to user-writable location.
        if bundled_argos.exists():
            try:
                shutil.copytree(bundled_site, user_site_path, dirs_exist_ok=True)
                _activate_user_site(user_site_path, user_site_candidates)
                _clear_import_cache()
                _verify_runtime_imports()
                return
            except Exception as bundled_copy_exc:
                candidate_error = RuntimeError(f"{candidate_error}; bundled_copy={bundled_copy_exc}")

        # Extra fallback: locate any packaged argostranslate folder under runtime/python and copy it.
        if not bundled_argos.exists():
            matches = list((runtime_root / "python").rglob("argostranslate/__init__.py"))
            if matches:
                try:
                    source_pkg = matches[0].parent
                    shutil.copytree(source_pkg, user_site_path / "argostranslate", dirs_exist_ok=True)
                    _activate_user_site(user_site_path, user_site_candidates)
                    _clear_import_cache()
                    _verify_runtime_imports()
                    return
                except Exception as deep_copy_exc:
                    candidate_error = RuntimeError(f"{candidate_error}; deep_copy={deep_copy_exc}")

        # Primary self-heal path: unpack bundled site-packages archive (fully offline).
        if site_archive.exists():
            try:
                with zipfile.ZipFile(site_archive, "r") as zf:
                    zf.extractall(user_site_path)
                _activate_user_site(user_site_path, user_site_candidates)
                _clear_import_cache()
                _verify_runtime_imports()
                return
            except Exception as archive_exc:
                candidate_error = RuntimeError(f"{candidate_error}; archive_extract={archive_exc}")

        # Secondary self-heal path: unpack wheels directly (works without pip).
        if wheel_candidates:
            try:
                for wheel in wheel_candidates:
                    with zipfile.ZipFile(wheel, "r") as zf:
                        zf.extractall(user_site_path)
                _activate_user_site(user_site_path, user_site_candidates)
                _clear_import_cache()
                _verify_runtime_imports()
                return
            except Exception as wheel_exc:
                candidate_error = RuntimeError(f"{candidate_error}; wheel_extract={wheel_exc}")

        if importlib.util.find_spec("pip") is None:
            attempt_errors.append(f"user_site={user_site}; err={candidate_error}; pip_available=False")
            continue

        if python_exe.exists() and wheelhouse.exists():
            env = os.environ.copy()
            env["PYTHONUTF8"] = "1"
            env["PYTHONNOUSERSITE"] = "1"
            result = subprocess.run(
                [
                    str(python_exe),
                    "-m",
                    "pip",
                    "install",
                    "--no-index",
                    "--find-links",
                    str(wheelhouse),
                    "--target",
                    user_site,
                    "--upgrade",
                    "--force-reinstall",
                    "--ignore-installed",
                    "argostranslate==1.9.6",
                    "ctranslate2==4.7.1",
                    "sentencepiece==0.2.0",
                    "packaging==24.2",
                    "numpy==1.26.4",
                    "pyyaml==6.0.3",
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
                env=env,
            )
            if result.returncode == 0:
                _activate_user_site(user_site_path, user_site_candidates)
                _clear_import_cache()
                try:
                    _verify_runtime_imports()
                    return
                except Exception as second_exc:
                    candidate_error = RuntimeError(f"{candidate_error}; pip_import={second_exc}")
            else:
                candidate_error = RuntimeError(
                    f"{candidate_error}; pip_install_exit={result.returncode}; "
                    f"stderr={result.stderr.strip()}; stdout={result.stdout.strip()}"
                )

        attempt_errors.append(f"user_site={user_site}; err={candidate_error}")

    runtime_pkg = runtime_root / "python" / "argostranslate"
    site_pkg = runtime_root / "python" / "Lib" / "site-packages" / "argostranslate"
    fail(
        "argostranslate import failed across user-site candidates: "
        f"{' || '.join(attempt_errors)}; "
        f"runtime_pkg={runtime_pkg.exists()}; "
        f"site_pkg={site_pkg.exists()}; wheelhouse={wheelhouse.exists()}; archive={site_archive.exists()}; "
        f"bundled_argos_exists={bundled_argos.exists()}; "
        f"bundled_ctranslate_exists={bundled_ctranslate.exists()}; bundled_ctranslate_ext_exists={bundled_ctranslate_ext}; "
        f"bundled_sentencepiece_exists={bundled_sentencepiece.exists()}; bundled_sentencepiece_ext_exists={bundled_sentencepiece_ext}; "
        f"bundled_root_argos_exists={bundled_root_argos.exists()}; sys.path={sys.path}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Offline zh<->en translator")
    parser.add_argument("--source", required=True)
    parser.add_argument("--target", required=True)
    args = parser.parse_args()

    source = normalize_lang(args.source)
    target = normalize_lang(args.target)

    if (source, target) not in {("zh", "en"), ("en", "zh")}:
        fail(f"Unsupported pair: {source}->{target}")

    text = sys.stdin.read()
    if not text:
        fail("Empty input")

    try:
        bootstrap_bundled_site_packages()
    except Exception as exc:
        fail(f"offline site-packages bootstrap error: {exc}")

    try:
        bootstrap_stanza_compat()
    except Exception as exc:
        fail(f"offline stanza compat bootstrap error: {exc}")

    try:
        bootstrap_seed_home()
    except Exception as exc:
        fail(f"offline bootstrap error: {exc}")

    ensure_argostranslate_available()

    import argostranslate.translate

    try:
        installed = argostranslate.translate.get_installed_languages()
        from_lang = next((x for x in installed if normalize_lang(getattr(x, "code", "")) == source), None)
        to_lang = next((x for x in installed if normalize_lang(getattr(x, "code", "")) == target), None)
        if from_lang is None or to_lang is None:
            fail("Offline language packages not installed for zh<->en")

        translation = from_lang.get_translation(to_lang)
        translated = translation.translate(text)
        sys.stdout.write(translated)
        return 0
    except Exception as exc:
        fail(f"offline translation error: {exc}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
