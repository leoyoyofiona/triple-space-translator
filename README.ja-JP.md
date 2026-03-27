# Triple Space Translator

<div align="center">
  <p><strong>スペースを 3 回。中国語と英語をその場で切り替え。</strong></p>
  <p>
    <a href="README.md">English</a> ·
    <a href="README.zh-CN.md">简体中文</a> ·
    <a href="README.ja-JP.md">日本語</a>
  </p>
  <p>
    <a href="https://github.com/leoyoyofiona/triple-space-translator/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/leoyoyofiona/triple-space-translator?display_name=tag"></a>
    <a href="https://github.com/leoyoyofiona/triple-space-translator/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/leoyoyofiona/triple-space-translator/total"></a>
    <a href="https://github.com/leoyoyofiona/triple-space-translator/actions/workflows/build-macos-installer.yml"><img alt="Build macOS" src="https://github.com/leoyoyofiona/triple-space-translator/actions/workflows/build-macos-installer.yml/badge.svg"></a>
    <a href="https://github.com/leoyoyofiona/triple-space-translator/actions/workflows/build-windows-installer.yml"><img alt="Build Windows" src="https://github.com/leoyoyofiona/triple-space-translator/actions/workflows/build-windows-installer.yml/badge.svg"></a>
  </p>
</div>

![Round-trip Demo](assets/screenshots/demo-roundtrip.gif)

Triple Space Translator は、AI チャット、検索ボックス、エディタ向けのバイリンガル入力ツールです。  
中国語または英語を入力したあと、`0.5 秒` 以内に `Space` を `3 回` 押すと、その場で翻訳して置き換えます。もう一度 3 回押すと、前の言語に戻せます。

## 使いどころ

- 母語で考えたまま入力し、必要な瞬間だけ英語に切り替えたい
- コピー、翻訳サイト、貼り付けの往復をなくしたい
- ChatGPT、Claude、Grok、Gemini など海外 AI ツールをもっと自然に使いたい

## クイックプレビュー

| 中国語入力 | 3 回スペース後 |
|---|---|
| ![Chinese input](assets/screenshots/demo-zh-input.png) | ![English output](assets/screenshots/demo-en-output.png) |

## Windows 設定画面

![Windows API settings](assets/screenshots/windows/windows-ui-api-settings.png)

## 対応状況

| プラットフォーム | 状況 | 翻訳方式 |
|---|---|---|
| macOS | 利用可能 | Apple `Translation.framework` |
| Windows | 利用可能 | 現在の安定版はオンライン API 翻訳 |
| Windows オフラインモード | 開発中 | Argos ベースの同梱モデルを調整中 |
| iPhone キーボード MVP | 実験段階 | 別プロジェクトとして案内 |

## ダウンロード

- Latest release: [github.com/leoyoyofiona/triple-space-translator/releases/latest](https://github.com/leoyoyofiona/triple-space-translator/releases/latest)
- Releases: [github.com/leoyoyofiona/triple-space-translator/releases](https://github.com/leoyoyofiona/triple-space-translator/releases)
- macOS: `DMG` または `ZIP`
- Windows: `EXE` インストーラー

## メモ

- 一部のアプリや保護された入力欄では、直接置換が制限されることがあります。
- macOS と iOS では、初回の言語ペア使用時に Apple の言語リソースがダウンロードされる場合があります。
- Windows の安定版は現在 API 翻訳が中心で、多少の遅延があります。
- Windows の同梱オフラインモデルはまだ開発中です。

## ガイド

- Windows guide: [windows/README-Windows.md](windows/README-Windows.md)
- iOS keyboard MVP: [ios/README-iOS.md](ios/README-iOS.md)
