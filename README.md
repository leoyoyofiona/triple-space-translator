# 中文三空格翻英文（macOS）

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

## macOS 安装包下载（GitHub）

- 下载页面（Release）：
  - https://github.com/leoyoyofiona/triple-space-translator/releases
- macOS 安装包文件名：
  - `TripleSpaceTranslator-macOS26-universal-<version>.dmg`
  - `TripleSpaceTranslator-macOS26-universal-<version>.zip`
- 自动打包工作流：
  - `.github/workflows/build-macos-installer.yml`

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
