#!/usr/bin/env python3
import argparse
import os
import pathlib
import shutil
import subprocess
import sys


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
        runtime_root = pathlib.Path(__file__).resolve().parent
        python_exe = runtime_root / "python" / "python.exe"
        wheelhouse = runtime_root / "wheelhouse"
        user_site = os.environ.get("TST_OFFLINE_USER_SITE", "").strip()
        if not user_site:
            user_site = str(pathlib.Path(os.path.expanduser("~")) / ".triple-space-translator" / "site-packages")

        if python_exe.exists() and wheelhouse.exists():
            pathlib.Path(user_site).mkdir(parents=True, exist_ok=True)
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
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
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
            f"site_pkg={site_pkg.exists()}; wheelhouse={wheelhouse.exists()}; "
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
