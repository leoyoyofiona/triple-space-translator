#!/usr/bin/env python3
import argparse
import os
import pathlib
import shutil
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
    candidates = [
        python_root / "Lib" / "site-packages",
        python_root,
        python_root / "python311.zip",
    ]

    for path in candidates:
        if path.exists():
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

    try:
        import argostranslate.translate
    except Exception as exc:  # pragma: no cover
        fail(f"argostranslate import failed: {exc}; sys.path={sys.path}")

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
