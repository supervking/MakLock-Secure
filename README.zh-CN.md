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

推荐下载 `MakLock-1.1.1-macos-universal.dmg` 拖拽安装包：它支持 macOS 13 及以上版本，并同时支持 Apple Silicon 和 Intel Mac。打开 DMG 后，将 `MakLock.app` 拖入“应用程序”即可；ZIP 仍作为备用下载包保留。

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
- 闲置超时或 Mac 休眠后重新锁定
- 可为指定受保护应用启用自动关闭
- 首次启动引导与菜单栏设置
- 英文、简体中文界面

## 安装步骤

1. 从 [Releases](https://github.com/supervking/MakLock-Secure/releases/latest) 下载最新版 DMG。
2. 将 DMG 与发布页的 `.sha256` 校验文件进行比对。
3. 打开 DMG，把 `MakLock.app` 拖到“应用程序”。
4. 打开 MakLock，先设置备用密码，再添加需要保护的应用。

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
