#!/usr/bin/env python3
import argparse
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
        import argostranslate.translate
    except Exception as exc:  # pragma: no cover
        fail(f"argostranslate import failed: {exc}")

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
