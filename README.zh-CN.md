# Triple Space Translator（中文说明）

语言: [English](README.md) | **中文**

在任意输入框输入中文或英文后，在 `0.5 秒` 内连按 `3 次空格`，即可原位翻译并替换。
再次连按三空格，可回切到上一轮语言。

## 产品介绍

Triple Space Translator 是一个“不中断思路”的双语输入助手。
适合聊天框、搜索框、文档编辑等场景：

- 先按自己的语言快速输入
- 三空格即时翻译并替换
- 不用复制/粘贴，不打断表达节奏

当前重点能力：

- macOS：使用系统 Translation.framework
- Windows：默认内置离线模型（开箱即用，无需 API key，无需联网）
- 双向回切：
  - 中文 -> 英文 -> 中文
  - 英文 -> 中文 -> 英文

## 效果展示

翻译前（中文输入）：

![翻译前中文输入](assets/screenshots/demo-zh-input.png)

翻译后（英文替换）：

![翻译后英文输出](assets/screenshots/demo-en-output.png)

## 这个 App 解决什么问题

在 ChatGPT / Claude / Grok / Gemini 等国际 AI 模型场景下，很多时候英文输入能获得更稳定的理解和输出。  
这个工具让你保留中文思考习惯：先中文快速输入，再三空格一键替换成英文。

## 功能特性

- 三空格触发（`0.5 秒`，Windows 可配置）
- 双向回切翻译：
  - 中文 -> 英文 -> 中文
  - 英文 -> 中文 -> 英文
- 常见输入框文本替换
- 提供 macOS + Windows 安装包
- 仓库内含 iOS 自定义键盘 MVP
- 翻译引擎：
  - macOS / iOS：Apple 系统 Translation.framework
  - Windows 首次安装默认：内置离线模型（无需网络、无需 API key）
  - Windows：OpenAI 或 LibreTranslate（支持 Docker 本地一键模式）

## 下载地址

- Releases 总入口：
  - [https://github.com/leoyoyofiona/triple-space-translator/releases](https://github.com/leoyoyofiona/triple-space-translator/releases)
- 最新安装包（`DMG/ZIP/EXE`）请直接在 Releases 页面下载。

## 各平台说明

- Windows 详细说明：
  - `windows/README-Windows.md`
- iOS 自定义键盘 MVP 说明：
  - `ios/README-iOS.md`

## macOS 本地运行

1. 用 Xcode 以 Swift Package 方式打开本项目目录。
2. 运行可执行目标 `TripleSpaceTranslatorApp`（`My Mac`）。
3. 在 App 界面授权：
   - Accessibility
   - Input Monitoring
4. 首次授权后建议重启 App。

## 注意事项

- 部分 App / 输入控件可能限制直接替换。
- macOS / iOS 首次语言对翻译可能触发 Apple 语言资源下载。
- Windows 某些受保护应用中，如替换失败可尝试管理员权限运行。

## 自动打包流程

- macOS 打包工作流：
  - `.github/workflows/build-macos-installer.yml`
- Windows 安装包工作流：
  - `.github/workflows/build-windows-installer.yml`
