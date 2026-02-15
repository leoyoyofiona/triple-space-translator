# 中文三空格翻英文（macOS）

## App 介绍文案

### 三连空格，中文秒变英文：我做了个全局翻译小工具

谁懂啊家人们😭 用国外AI大模型真的太费劲儿了。  
明明中文思路很顺畅，非要先写中文→复制→翻译→粘贴，思路全被打断。

被逼无奈自己做了个翻译小工具，直接封神✅

✨ 用法巨简单，零门槛上手  
任意输入框打中文，0.5秒内连按3次空格❗️  
中文直接秒变英文，自动替换原文，不用多走一步。

🌍 适配所有高频场景

- ChatGPT / Claude 等英文AI对话（最顺手）
- 微信、浏览器、文档快速输出英文
- 再也不用来回切换翻译网站，省出超多时间

💻 关键是！Windows / macOS 都能用。  
打英文再也不用硬憋，思路不中断真的太香了👏

---

这是一个 macOS 普通窗口 App：
- 在任意 App 输入框输入中文
- 0.5 秒内快速连按 3 次空格
- 自动把当前输入框内容翻译成英文并替换

## 运行方式

1. 用 Xcode 打开目录 `/Users/leo/Downloads/打字中英文双显`（作为 Swift Package 打开即可）。
2. 选择可执行目标 `TripleSpaceTranslatorApp`，运行到 `My Mac`。
3. 在主界面点击授权按钮，开启：
   - Accessibility
   - Input Monitoring
4. 授权后建议重启一次 App。

## 下载地址（macOS / Windows）

- GitHub Releases 总入口：
  - https://github.com/leoyoyofiona/triple-space-translator/releases

- macOS 下载（当前版本 `v1.0.4`）：
  - DMG（推荐安装）：https://github.com/leoyoyofiona/triple-space-translator/releases/download/v1.0.4/TripleSpaceTranslator-macOS26-universal-1.0.4.dmg
  - ZIP（便携）：https://github.com/leoyoyofiona/triple-space-translator/releases/download/v1.0.4/TripleSpaceTranslator-macOS26-universal-1.0.4.zip

- Windows 下载（当前稳定版 `v1.0.2`）：
  - EXE 安装包：https://github.com/leoyoyofiona/triple-space-translator/releases/download/v1.0.2/TripleSpaceTranslator-Setup-1.0.2.exe

- 找不到直链时：
  - 打开 Releases 页面，按系统下载对应文件：
  - macOS：`TripleSpaceTranslator-macOS26-universal-*.dmg` 或 `*.zip`
  - Windows：`TripleSpaceTranslator-Setup-*.exe`

- 自动打包工作流：
  - macOS：`.github/workflows/build-macos-installer.yml`
  - Windows：`.github/workflows/build-windows-installer.yml`

## 实现说明

- 全局按键监听：`CGEvent.tapCreate`（listen only）
- 触发条件：0.5 秒内 3 次空格
- 文本读写：Accessibility API（`kAXFocusedUIElementAttribute` + `kAXValueAttribute`）
- 翻译引擎：系统 `Translation.framework`（目标语言英文）

## 已知限制

- 某些 App 的输入控件不支持 AX 值写入，可能替换失败。
- 首次使用某个语言对时，系统可能需要下载语言资源。
- 为避免误覆盖：触发到翻译完成期间，如果你继续输入，当前轮次会自动取消替换。

## Windows 版本

- Windows stable source is in:
  - `/Users/leo/Downloads/打字中英文双显/windows/TripleSpaceTranslator.Win`
- Build/distribution guide:
  - `/Users/leo/Downloads/打字中英文双显/windows/README-Windows.md`
- Installer script (Inno Setup):
  - `/Users/leo/Downloads/打字中英文双显/windows/installer/build-installer.ps1`
- GitHub one-click installer workflow:
  - `/Users/leo/Downloads/打字中英文双显/.github/workflows/build-windows-installer.yml`
