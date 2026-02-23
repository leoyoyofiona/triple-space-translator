# Triple Space Translator（中文说明）

语言: [English](README.md) | **中文**

在任意输入框输入中文或英文后，在 `0.5 秒` 内连按 `3 次空格`，即可原位翻译并替换。
再次连按三空格，可回切到上一轮语言。

## 产品介绍

Triple Space Translator 是一个“不中断思路”的双语输入助手，主打快、顺、无打断。
适合聊天框、搜索框、文档编辑等场景：

- 先按自己的语言快速输入
- 三空格即时翻译并替换
- 不用复制/粘贴，不打断表达节奏

它特别适合和国外 AI 大模型交流时的输入习惯：

- 英文提示词通常能获得更稳定的理解和输出
- 但你可以继续先用中文思考和输入，再一键切成英文

当前重点能力：

- macOS：使用系统 Translation.framework
- Windows：当前可用在线 API 翻译（需设置 API key，可能有一定延迟）
- Windows：因系统层面不像 macOS 有同等内置词典翻译通道，离线打包词典/模型功能仍在开发完善中
- 双向回切：
  - 中文 -> 英文 -> 中文
  - 英文 -> 中文 -> 英文

## 界面展示

| 中文输入 | 三空格后英文替换 |
|---|---|
| ![翻译前中文输入](assets/screenshots/demo-zh-input.png) | ![翻译后英文输出](assets/screenshots/demo-en-output.png) |

## Windows 界面预览

| 设置窗口 | 运行状态窗口 |
|---|---|
| ![Windows 设置界面](assets/screenshots/windows/windows-ui-status-1.png) | ![Windows 运行状态](assets/screenshots/windows/windows-ui-status-2.png) |

## Windows 当前翻译状态

- Windows 稳定版当前主要使用在线 API 翻译。
- 需要在应用设置中填写 API key。
- 在线翻译会受网络影响，存在一定延迟。
- 离线打包词典/模型模式仍在持续开发和完善中。

## 使用步骤

1. 在任意输入框正常输入中文或英文。
2. 在 `0.5 秒` 内连按 `3 次空格`。
3. 当前文本会立即翻译并原位替换。
4. 再连按三空格，可切回上一轮语言。

常见使用场景：

- ChatGPT / Claude / Grok / Gemini 等 AI 对话框
- 浏览器搜索框
- 微信等聊天输入框
- 便签与文档快速写作

## 下载地址

- Releases 总入口：
  - [https://github.com/leoyoyofiona/triple-space-translator/releases](https://github.com/leoyoyofiona/triple-space-translator/releases)
- 在最新 Release 中下载对应安装包：
  - macOS：`DMG / ZIP`
  - Windows：`EXE`

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
