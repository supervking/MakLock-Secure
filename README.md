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

`MakLock-1.3.2-macos-universal.dmg` is the recommended drag-and-drop installer for macOS 13 or later on Apple Silicon and Intel Macs. Open it and drag `MakLock.app` to `Applications`. The ZIP remains available as an alternative package.

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
- Locking after an idle timeout of up to 2 hours, or when the Mac sleeps
- Optional auto-close for selected protected applications
- First-launch onboarding and menu-bar settings
- English and Simplified Chinese interface
- In-app language selection: Follow System, English, or Simplified Chinese
- Password-first lock screen for remote and keyboard-only Macs; the password field is focused automatically and Return submits it
- Password input recovers keyboard focus after long idle periods, remote-session focus changes, or another window taking focus
- Optional locking after every internet-connectivity probe fails continuously for 1, 2, or 5 minutes
- Optional immediate locking when the trusted display fingerprint set changes; resolution-only changes are ignored

Network recovery never unlocks protected apps automatically. Display fingerprints detect ordinary monitor additions and replacements, but hardware that perfectly clones a trusted display's EDID may not be distinguishable by macOS.

- Optional restart cleanup closes automatically restored protected apps during a one-time 90-second window after a real Mac reboot; remote-access and system apps are always excluded
- Password focus is restored after the macOS user session becomes active or screens wake, so remote users can type without clicking the password field
- Password entry uses a native AppKit secure field and verifies the actual first responder instead of relying only on SwiftUI focus state
- Password mode uses an activating overlay and temporarily hides the protected app so typed secrets cannot fall through to it when macOS restores another foreground application
- Progressive password protection applies 2-second, 4-second, 30-second, and 5-minute delays, then blocks password unlock for 3 hours after five failures within 30 minutes
- Security history stores only non-sensitive events from the latest 12 hours, capped at 200 records

Password lockout state is stored in the macOS Keychain and survives MakLock restarts and Mac reboots. Touch ID and Apple Watch remain available during a password-only lockout.

## Free and commercial options

MakLock Secure is free to download and its source is available under the MIT License. The table below is a pricing-and-scope snapshot reviewed on **2026-08-17**, not an independent security evaluation. Commercial pricing and features can change, and App Store prices vary by storefront.

| | MakLock Secure | AppLocker | Cisdem AppCrypt for Mac |
|---|---|---|---|
| Price / access | Free download; MIT-licensed source | Free download with in-app purchases; the US App Store lists $2.99/month, $11.99/year, or $17.99 lifetime access | 3-day full-feature trial; the vendor's 1-Mac offer lists $19.99/year or $39.99 one-time purchase |
| Published app-lock options | Touch ID, Apple Watch proximity, or backup password | Password, Touch ID, Bluetooth ID, or Network ID | Password-protected app locking, plus app allowlist mode |
| Other published scope | Per-app overlay locking, idle/sleep locking, optional auto-close | Access history | Website blocking, schedules, and automatic re-locking |
| Source availability | Yes — this repository | Not stated on the cited App Store listing | Not stated on the cited vendor pages |

Sources: [AppLocker on the US App Store](https://apps.apple.com/us/app/applocker-passcode-lock-apps/id1132845904?platform=mac), [Cisdem AppCrypt features and trial](https://www.cisdem.com/appcrypt.html), and [Cisdem AppCrypt for Mac pricing](https://www.cisdem.com/appcrypt-mac/buy.html). Verify current terms and pricing with the vendor before purchasing.

## Installation

1. Download the latest DMG from [Releases](https://github.com/supervking/MakLock-Secure/releases/latest).
2. Compare the DMG with its published `.sha256` file.
3. Open the DMG and drag `MakLock.app` to `Applications`.
4. Open MakLock and set a backup password before adding protected applications.

To change the interface language, open **Settings → General → Language**, choose Follow System, English, or Simplified Chinese, then select **Restart MakLock**.

For remote or keyboard-only Macs, **Settings → Security → Prefer password on lock screen** is enabled by default. The password field receives focus automatically; enter the password and press Return to unlock. Disable this setting if you prefer the original Touch ID-first flow.

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
