#!/usr/bin/env python3
import argparse
import importlib.util
import os
import pathlib
import shutil
import subprocess
import sys
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
        pathlib.Path(extra_user_site) if extra_user_site else None,
        python_root / "Lib" / "site-packages",
        python_root,
        python_root / "python311.zip",
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


def ensure_argostranslate_available() -> None:
    try:
        import argostranslate.translate  # noqa: F401
        return
    except Exception as first_exc:
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
        user_site = os.environ.get("TST_OFFLINE_USER_SITE", "").strip()
        if not user_site:
            user_site = str(pathlib.Path(os.path.expanduser("~")) / ".triple-space-translator" / "site-packages")
        user_site_path = pathlib.Path(user_site)
        user_site_path.mkdir(parents=True, exist_ok=True)

        # First self-heal path: copy packaged site-packages to user-writable location.
        if bundled_argos.exists():
            try:
                shutil.copytree(bundled_site, user_site_path, dirs_exist_ok=True)
                if user_site not in sys.path:
                    sys.path.insert(0, user_site)
                import argostranslate.translate  # noqa: F401
                return
            except Exception as bundled_copy_exc:
                first_exc = RuntimeError(f"{first_exc}; bundled_copy={bundled_copy_exc}")

        # Extra fallback: locate any packaged argostranslate folder under runtime/python and copy it.
        if not bundled_argos.exists():
            matches = list((runtime_root / "python").rglob("argostranslate/__init__.py"))
            if matches:
                try:
                    source_pkg = matches[0].parent
                    shutil.copytree(source_pkg, user_site_path / "argostranslate", dirs_exist_ok=True)
                    if user_site not in sys.path:
                        sys.path.insert(0, user_site)
                    import argostranslate.translate  # noqa: F401
                    return
                except Exception as deep_copy_exc:
                    first_exc = RuntimeError(f"{first_exc}; deep_copy={deep_copy_exc}")

        # Primary self-heal path: unpack bundled site-packages archive (works fully offline, no pip required).
        if site_archive.exists():
            try:
                with zipfile.ZipFile(site_archive, "r") as zf:
                    zf.extractall(user_site_path)
                if user_site not in sys.path:
                    sys.path.insert(0, user_site)
                import argostranslate.translate  # noqa: F401
                return
            except Exception as archive_exc:
                # Continue to pip-based recovery as fallback.
                first_exc = RuntimeError(f"{first_exc}; archive_extract={archive_exc}")

        # Secondary self-heal path: unpack all available wheels directly (works without pip).
        wheel_candidates = sorted(wheelhouse.glob("*.whl")) if wheelhouse.exists() else []
        if wheel_candidates:
            try:
                for wheel in wheel_candidates:
                    with zipfile.ZipFile(wheel, "r") as zf:
                        zf.extractall(user_site_path)
                if user_site not in sys.path:
                    sys.path.insert(0, user_site)
                import argostranslate.translate  # noqa: F401
                return
            except Exception as wheel_exc:
                first_exc = RuntimeError(f"{first_exc}; wheel_extract={wheel_exc}")

        if importlib.util.find_spec("pip") is None:
            fail(
                "argostranslate import failed and pip is unavailable for self-heal: "
                f"{first_exc}; bundled_site_exists={bundled_site.exists()}; bundled_argos_exists={bundled_argos.exists()}; "
                f"bundled_ctranslate_exists={bundled_ctranslate.exists()}; bundled_ctranslate_ext_exists={bundled_ctranslate_ext}; "
                f"bundled_sentencepiece_exists={bundled_sentencepiece.exists()}; bundled_sentencepiece_ext_exists={bundled_sentencepiece_ext}; "
                f"bundled_root_argos_exists={bundled_root_argos.exists()}; "
                f"archive_exists={site_archive.exists()}; wheel_exists={bool(wheel_candidates)}; sys.path={sys.path}"
            )

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
                    "ctranslate2>=4.0,<5",
                    "sentencepiece==0.2.0",
                    "sacremoses==0.0.53",
                    "packaging",
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
                env=env,
            )
            if result.returncode != 0:
                fail(
                    "argostranslate self-heal install failed: "
                    f"exit={result.returncode}; stderr={result.stderr.strip()}; stdout={result.stdout.strip()}"
                )

            if user_site not in sys.path:
                sys.path.insert(0, user_site)

            try:
                import argostranslate.translate  # noqa: F401
                return
            except Exception as second_exc:
                fail(
                    "argostranslate import failed after self-heal: "
                    f"{second_exc}; user_site={user_site}; sys.path={sys.path}"
                )

        runtime_pkg = runtime_root / "python" / "argostranslate"
        site_pkg = runtime_root / "python" / "Lib" / "site-packages" / "argostranslate"
        fail(
            "argostranslate import failed: "
            f"{first_exc}; runtime_pkg={runtime_pkg.exists()}; "
            f"site_pkg={site_pkg.exists()}; wheelhouse={wheelhouse.exists()}; archive={site_archive.exists()}; "
            f"sys.path={sys.path}"
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
