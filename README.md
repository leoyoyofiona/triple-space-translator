# Triple Space Translator

Language: **English** | [中文](README.zh-CN.md)

Type in Chinese or English, then press `Space` 3 times within `0.5s` to translate and replace in place.
Press triple-space again to toggle back to the previous language.

## Product Intro

Triple Space Translator is a global input helper for fast bilingual writing.
It keeps your thinking flow in chats, search boxes, and editors:

- write first in your natural language
- trigger translation with triple-space
- continue typing without copy/paste context switching

Current highlight:

- macOS: system translation framework
- Windows: built-in offline model by default (out-of-box, no API key, no network)
- Bidirectional round-trip toggle:
  - Chinese -> English -> Chinese
  - English -> Chinese -> English

## Demo

Before (Chinese input):

![Before Translation](assets/screenshots/demo-zh-input.png)

After (English replacement):

![After Translation](assets/screenshots/demo-en-output.png)

## Why this app

When chatting with global AI models (ChatGPT / Claude / Grok / Gemini), English prompts often produce more stable understanding and output.  
This app keeps your thinking flow: write in Chinese first, then trigger instant English replacement with triple-space.

## Features

- Triple-space trigger (`0.5s`, configurable on Windows)
- Bidirectional round-trip toggle:
  - Chinese -> English -> Chinese
  - English -> Chinese -> English
- Input replacement in common text fields
- macOS + Windows download packages
- iOS keyboard extension MVP available in repo
- Translation providers:
  - macOS / iOS: Apple Translation framework
  - Windows default first-run: built-in offline model (no network, no API key)
  - Windows: OpenAI or LibreTranslate (supports one-click local Docker mode)

## Downloads

- Releases page:
  - [https://github.com/leoyoyofiona/triple-space-translator/releases](https://github.com/leoyoyofiona/triple-space-translator/releases)
- Download latest assets from the release page (`DMG/ZIP/EXE`).

## Platform Guides

- Windows guide:
  - `windows/README-Windows.md`
- iOS keyboard MVP guide:
  - `ios/README-iOS.md`

## macOS Local Run

1. Open this folder in Xcode as a Swift Package.
2. Run executable target `TripleSpaceTranslatorApp` on `My Mac`.
3. Grant permissions in app UI:
   - Accessibility
   - Input Monitoring
4. Restart app after first permission grant.

## Notes

- Some apps/controls may block direct replacement.
- On macOS/iOS, first translation of a language pair may require Apple language resources download.
- If replacement is blocked in protected apps, try running the Windows app as Administrator.

## CI Workflows

- macOS package workflow:
  - `.github/workflows/build-macos-installer.yml`
- Windows installer workflow:
  - `.github/workflows/build-windows-installer.yml`
