<p align="center">
  <img src="Resources/icon.png" width="128" height="128" alt="MakLock icon">
</p>

<h1 align="center">MakLock Secure</h1>

<p align="center">
  A bilingual macOS application locker with persistent authentication overlays.
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a> · English
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-black?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square" alt="Swift">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-white?style=flat-square" alt="License"></a>
  <a href="https://github.com/supervking/MakLock-Secure/releases/latest"><img src="https://img.shields.io/github/v/release/supervking/MakLock-Secure?style=flat-square&label=release" alt="Release"></a>
  <a href="https://github.com/supervking/MakLock-Secure/releases"><img src="https://img.shields.io/github/downloads/supervking/MakLock-Secure/total?style=flat-square&color=34C759&label=downloads" alt="Downloads"></a>
</p>

## Download

Download the current package from [GitHub Releases](https://github.com/supervking/MakLock-Secure/releases/latest).

`MakLock-1.1.1-macos-universal.zip` supports macOS 13 or later on Apple Silicon and Intel Macs. Unzip it, drag `MakLock.app` to `/Applications`, then open it.

> The release is ad-hoc signed and is not Apple-notarized. On first launch, macOS may require you to confirm the app in **System Settings → Privacy & Security**. Verify the accompanying SHA-256 file before opening a downloaded package.

## What is MakLock Secure?

MakLock Secure is an independent maintenance release of [MakLock](https://github.com/dutkiewiczmaciej/MakLock). It protects selected macOS applications with Touch ID, Apple Watch proximity, or a backup password. When a protected application is activated, MakLock displays an overlay until authentication succeeds.

## Security changes in 1.1.1

- The lock overlay no longer dismisses itself after an inactivity timer.
- Release builds contain no global keyboard shortcut that dismisses a lock overlay.
- Automatic in-app updating is disabled so a verified build is not silently replaced.
- The application interface is available in English and Simplified Chinese.

## Features

- Touch ID authentication with backup-password fallback
- Optional Apple Watch proximity unlock
- Full-screen overlays across multiple displays
- Locking after an idle timeout or Mac sleep
- Optional auto-close for selected protected applications
- First-launch onboarding and menu-bar settings
- English and Simplified Chinese interface

## Installation

1. Download the latest ZIP from [Releases](https://github.com/supervking/MakLock-Secure/releases/latest).
2. Compare the ZIP with its published `.sha256` file.
3. Move `MakLock.app` to `/Applications`.
4. Open MakLock and set a backup password before adding protected applications.

## Build from source

```bash
git clone https://github.com/supervking/MakLock-Secure.git
cd MakLock-Secure
xcodebuild -project MakLock.xcodeproj -scheme MakLock -configuration Release CODE_SIGNING_ALLOWED=NO build
```

Requires Xcode 15 or later and macOS 13 or later.

## Security boundaries

MakLock protects application access within an active macOS account. It is not a replacement for a separate macOS user account, FileVault, or the macOS lock screen. Keep your backup password private and lock your Mac when leaving it unattended.

## Attribution and license

This independent maintenance release is based on the original [MakLock project](https://github.com/dutkiewiczmaciej/MakLock) by Maciej Dutkiewicz. The original copyright notice and the [MIT License](LICENSE) are retained.
