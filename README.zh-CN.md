# Triple Space Translator（中文说明）

语言: [English](README.md) | **中文**

先输入中文，在 `0.5 秒` 内连按 `3 次空格`，自动替换成英文。
再次连按三空格，可以回切到上一轮语言结果。

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
  - Windows：OpenAI 或 LibreTranslate（支持 Docker 本地一键模式）
  - Windows 首次安装默认：公共 LibreTranslate（无需 API key）

## 新增：回切翻译

现在支持在同一输入框内连续来回切换：

- 输入中文，三空格 -> 英文
- 再三空格 -> 回到中文
- 输入英文，三空格 -> 中文
- 再三空格 -> 回到英文

## 下载地址

- Releases 总入口：
  - [https://github.com/leoyoyofiona/triple-space-translator/releases](https://github.com/leoyoyofiona/triple-space-translator/releases)
- macOS（最新已发布包，当前 `v1.0.5`）：
  - [DMG](https://github.com/leoyoyofiona/triple-space-translator/releases/download/v1.0.5/TripleSpaceTranslator-macOS26-universal-1.0.5.dmg)
  - [ZIP](https://github.com/leoyoyofiona/triple-space-translator/releases/download/v1.0.5/TripleSpaceTranslator-macOS26-universal-1.0.5.zip)
- Windows（当前稳定安装包 `v1.0.2`）：
  - [EXE](https://github.com/leoyoyofiona/triple-space-translator/releases/download/v1.0.2/TripleSpaceTranslator-Setup-1.0.2.exe)

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
