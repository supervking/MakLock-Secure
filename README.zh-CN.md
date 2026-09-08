<p align="center">
  <img src="Resources/icon.png" width="128" height="128" alt="MakLock 图标">
</p>

<h1 align="center">MakLock Secure</h1>

<p align="center">
  具备持续认证锁定层的中英文 macOS 应用加锁工具。
</p>

<p align="center">
  简体中文 · <a href="README.md">English</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/平台-macOS%2013%2B-black?style=flat-square" alt="平台">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square" alt="Swift">
  <a href="LICENSE"><img src="https://img.shields.io/badge/许可证-MIT-white?style=flat-square" alt="许可证"></a>
  <a href="https://github.com/supervking/MakLock-Secure/releases/latest"><img src="https://img.shields.io/github/v/release/supervking/MakLock-Secure?style=flat-square&label=版本" alt="版本"></a>
  <a href="https://github.com/supervking/MakLock-Secure/releases"><img src="https://img.shields.io/github/downloads/supervking/MakLock-Secure/total?style=flat-square&color=34C759&label=下载" alt="下载"></a>
</p>

## 下载

请从 [GitHub Releases](https://github.com/supervking/MakLock-Secure/releases/latest) 下载当前版本。

推荐下载 `MakLock-1.3.0-macos-universal.dmg` 拖拽安装包：它支持 macOS 13 及以上版本，并同时支持 Apple Silicon 和 Intel Mac。打开 DMG 后，将 `MakLock.app` 拖入“应用程序”即可；ZIP 仍作为备用下载包保留。

> 当前发布包使用 ad-hoc 本地签名，尚未经过 Apple 公证。首次打开时，macOS 可能要求你在“系统设置 → 隐私与安全性”中确认打开。请在打开前核对发布页提供的 SHA-256 校验文件。

## MakLock Secure 是什么？

MakLock Secure 是基于 [MakLock](https://github.com/dutkiewiczmaciej/MakLock) 的独立维护版本。它可通过 Touch ID、Apple Watch 接近解锁或备用密码保护指定 macOS 应用；当受保护应用被打开或切换到前台时，MakLock 会显示锁定层，直到认证成功。

## 1.1.1 的安全改进

- 锁定层不会再因闲置计时而自动消失。
- 正式发布版本不包含可直接关闭锁定层的全局快捷键。
- 已关闭应用内自动更新，避免已验证版本被静默替换。
- 应用界面提供英文与简体中文。

## 功能

- Touch ID 认证，并提供备用密码
- 可选 Apple Watch 接近解锁
- 覆盖多显示器的全屏锁定层
- 闲置超时（最长可设为 2 小时）或 Mac 休眠后重新锁定
- 可为指定受保护应用启用自动关闭
- 首次启动引导与菜单栏设置
- 英文、简体中文界面
- 应用内语言选择：跟随系统、English 或简体中文
- 密码优先的锁定界面：适合远程或纯键盘 Mac，密码框自动聚焦，按 Return 即可提交解锁
- 长时间锁定、远程会话焦点变化或其他窗口抢走焦点后，点击密码框会自动恢复键盘输入
- 可选断网保护：所有联网探测连续失败 1、2 或 5 分钟后锁定受保护应用
- 可选显示器保护：可信显示器指纹集合变化时立即锁定，仅分辨率变化不会触发

网络恢复后不会自动解锁。显示器指纹可以检测普通的新增、拔除和替换，但如果硬件能完整复制可信显示器的 EDID，macOS 可能无法区分。

- 可选重启清理：Mac 真正重启后的单次 90 秒保护期内，关闭系统自动恢复的受保护应用；远程控制和系统应用始终排除
- macOS 用户会话恢复或屏幕唤醒后重新聚焦密码框，远程用户无需点击即可直接输入
- 密码错误依次限制 2 秒、4 秒、30 秒和 5 分钟；30 分钟内第五次错误后封锁密码解锁 3 小时
- 安全记录只保存最近 12 小时的非敏感事件，最多 200 条

密码封锁状态保存在 macOS Keychain 中，重启 MakLock 或 Mac 都不会清除。密码封锁期间仍可使用 Touch ID 或 Apple Watch。

## 免费与商业方案对比

MakLock Secure 可免费下载，源码采用 MIT 许可证。下表是于 **2026-08-17** 核验的价格与公开功能范围快照，并非独立安全评测；商业软件的功能、价格和 App Store 各地区售价都可能变化。

| | MakLock Secure | AppLocker | Cisdem AppCrypt for Mac |
|---|---|---|---|
| 价格／使用方式 | 免费下载；MIT 开源 | 免费下载，含 App 内购买；美国 App Store 显示为 $2.99／月、$11.99／年或 $17.99 终身版 | 3 天完整功能试用；厂商 1 台 Mac 报价为 $19.99／年或 $39.99 一次性购买 |
| 已公开的应用加锁方式 | Touch ID、Apple Watch 接近解锁或备用密码 | 密码、Touch ID、Bluetooth ID 或 Network ID | 密码加锁，并提供应用允许列表模式 |
| 已公开的其他范围 | 单应用锁定层、闲置／休眠后锁定、可选自动关闭 | 访问记录 | 网站拦截、计划任务和自动重新锁定 |
| 源码可用性 | 是——本仓库 | 引用的 App Store 页面未说明 | 引用的厂商页面未说明 |

资料来源：[AppLocker 美国 App Store 页面](https://apps.apple.com/us/app/applocker-passcode-lock-apps/id1132845904?platform=mac)、[Cisdem AppCrypt 功能与试用说明](https://www.cisdem.com/appcrypt.html) 与 [Cisdem AppCrypt for Mac 价格页](https://www.cisdem.com/appcrypt-mac/buy.html)。购买前请以厂商当期条款和售价为准。

## 安装步骤

1. 从 [Releases](https://github.com/supervking/MakLock-Secure/releases/latest) 下载最新版 DMG。
2. 将 DMG 与发布页的 `.sha256` 校验文件进行比对。
3. 打开 DMG，把 `MakLock.app` 拖到“应用程序”。
4. 打开 MakLock，先设置备用密码，再添加需要保护的应用。

如需切换界面语言，请打开“设置 → 通用 → 语言”，选择“跟随系统”、“English”或“简体中文”，再点“重新启动 MakLock”。

远程或纯键盘 Mac 默认启用“设置 → 安全性 → 锁定时优先使用密码”：锁定层会自动聚焦密码框，输入密码后按 Return 即可解锁。如偏好原来的 Touch ID 优先流程，可关闭此开关。

## 从源码构建

```bash
git clone https://github.com/supervking/MakLock-Secure.git
cd MakLock-Secure
xcodebuild -project MakLock.xcodeproj -scheme MakLock -configuration Release CODE_SIGNING_ALLOWED=NO build
```

需要 Xcode 15 或更新版本，以及 macOS 13 或更新版本。

## 安全边界

MakLock 保护的是当前 macOS 账户内的应用访问，不能替代独立 macOS 用户账户、FileVault 或系统锁屏。请妥善保管备用密码，离开电脑时仍应锁定 macOS。

## 致谢与许可证

本独立维护版本基于 Maciej Dutkiewicz 的原始 [MakLock 项目](https://github.com/dutkiewiczmaciej/MakLock)。原始版权声明与 [MIT 许可证](LICENSE) 均已保留。
