<p align="center">
  <img src="Resources/icon-maclock.png" width="128" height="128" alt="Maclock Secure MacOS icon">
</p>

<h1 align="center">Maclock Secure MacOS</h1>

<p align="center">
  Open-source macOS app locking for remote-computer privacy and shoulder-surfing protection.
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文：MAC锁屏加密应用</a> · English
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-black?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square" alt="Swift">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-white?style=flat-square" alt="License"></a>
  <a href="https://github.com/supervking/MakLock-Secure/releases/latest"><img src="https://img.shields.io/github/v/release/supervking/MakLock-Secure?style=flat-square&label=release" alt="Release"></a>
  <a href="https://github.com/supervking/MakLock-Secure/releases"><img src="https://img.shields.io/github/downloads/supervking/MakLock-Secure/total?style=flat-square&color=34C759&label=downloads" alt="Downloads"></a>
</p>

## Download

Download [Maclock Secure MacOS 1.5.3](https://github.com/supervking/MakLock-Secure/releases/tag/v1.5.3) for macOS 13 or later:

- [Universal DMG](https://github.com/supervking/MakLock-Secure/releases/download/v1.5.3/Maclock-Secure-MacOS-1.5.3-universal.dmg) — recommended drag-and-drop installer
- [Universal ZIP](https://github.com/supervking/MakLock-Secure/releases/download/v1.5.3/Maclock-Secure-MacOS-1.5.3-universal.zip) — alternative package
- SHA-256 files are published beside both downloads

The application is distributed as an ad-hoc-signed, non-notarized universal build for Apple Silicon and Intel Macs. Verify the SHA-256 file before opening it. macOS may require first-launch approval in **System Settings → Privacy & Security**.

## What it protects

Maclock Secure MacOS places an authentication overlay over selected applications whenever they launch or return to the foreground. It is designed for shared Macs, unattended remote workstations, and computers that remain signed in while their owner is away.

| Situation | Protection |
|---|---|
| Someone opens a protected app locally | A full-screen password or Touch ID challenge covers its contents |
| A remote-control connection drops | Optional network-loss protection locks protected apps after a bounded delay |
| The Mac becomes idle or sleeps | Protected apps are locked; selected apps can optionally close |
| A display is added, removed, mirrored, or replaced | The desktop is hidden and a persistent red owner-authentication alert is shown |
| A display is connected and removed quickly | The structural event remains latched in the alert and 12-hour security history |
| A remote session regains focus | Password input regains keyboard focus without sending keystrokes to the protected app |

### Remote-computer privacy and anti-peeping

The recommended remote-work profile is password-first locking, network-loss protection, trusted-display protection, idle locking, and a backup password stored in the macOS Keychain. Together these controls reduce casual local viewing of chat, browser, messaging, password, and administration applications on an unattended Mac.

The product protects application visibility inside the current signed-in macOS account. It does **not** encrypt a remote-desktop protocol, block privileged screenshots, defeat an administrator or root user, replace FileVault, or replace the macOS login screen.

See the [complete Simplified Chinese screenshot gallery](README.zh-CN.md#应用页面截图).

## Current security features

### Authentication and application locking

- Backup-password authentication with password-first remote and keyboard-only operation
- Touch ID when macOS reports an enrolled biometric sensor or paired Touch ID keyboard
- Optional Apple Watch proximity unlock with wrist-state checks
- Authentication on application launch and/or foreground activation
- Full-screen overlays across all connected displays
- Native AppKit secure password input with verified keyboard focus
- Owner-authenticated password recovery from the primary trusted lock screen
- Keychain access errors are reported separately and never counted as wrong-password attempts
- Interrupted macOS authentication restores lock-screen input without requiring a restart
- No release-build skip button or global overlay-dismiss shortcut

### Remote, idle, and session protection

- Idle timeout from 1 minute to 2 hours
- Locking when the Mac sleeps or the Apple Watch leaves range
- Optional per-application auto-close after inactivity
- Optional network-loss locking after all probes fail continuously for 1, 2, or 5 minutes
- Network recovery never unlocks protected applications automatically
- Session-focus recovery for remote-control reconnects and screen wake

### Display privacy and emergency recovery

- Trusted-display fingerprints for detecting ordinary additions, removals, replacements, mirroring, and unmirroring
- Immediate desktop shielding followed by a persistent red alert, silent macOS notification, and red menu-bar state
- Brief connect-then-disconnect events remain latched even if the trusted topology returns before evaluation finishes
- Resolution, refresh-rate, display-sleep, and desktop-shape-only changes are excluded from structural tamper alerts
- Owner-configured hidden restart recovery can bypass only the display-wide alert after the complete validated sequence; protected apps remain closed and authenticated separately
- Optional one-time post-restart cleanup for automatically restored protected applications

### Local state and evidence

- Backup password and password-attempt throttling are stored in the macOS Keychain
- Progressive retry delays and a 3-hour password lockout after five failures within 30 minutes
- Non-sensitive security events are retained locally for 12 hours, capped at 200 records
- English and Simplified Chinese interface with an in-app language selector

## Installation

1. Download the latest DMG and its `.sha256` file.
2. Verify the checksum.
3. Open the DMG and drag `MakLock.app` to `Applications`.
4. Approve first launch in **System Settings → Privacy & Security** if macOS requests it.
5. Set a backup password before adding protected applications.

For an unattended remote Mac, enable **Prefer password on lock screen**, **Lock after internet connection is lost**, **Lock when the trusted display setup changes**, and an appropriate idle timeout.

## Compatibility

- macOS 13 or later
- Apple Silicon and Intel Macs
- Touch ID is optional; desktop Macs require a compatible paired Touch ID keyboard
- Apple Watch is optional
- No cloud account or subscription is required

## Build from source

```bash
git clone https://github.com/supervking/MakLock-Secure.git
cd MakLock-Secure
xcodebuild -project MakLock.xcodeproj -scheme MakLock -configuration Release CODE_SIGNING_ALLOWED=NO build
```

Requires Xcode 15 or later. The stable bundle identifier remains `com.makmak.MakLock` for settings and Keychain compatibility.

## Security boundaries

Maclock Secure MacOS is an application-access control inside an active user session. A user with administrator/root access, physical access sufficient to alter the operating system, or screen-capture privileges may bypass application-level controls. Passive display splitters or hardware that perfectly clones a trusted display's EDID may also be indistinguishable to macOS. Use a separate macOS account, FileVault, system screen locking, secured remote-access credentials, and physical access controls where appropriate.

## Attribution and license

This independent maintenance release is based on the original [MakLock project](https://github.com/dutkiewiczmaciej/MakLock) by Maciej Dutkiewicz. The original copyright notice and the [MIT License](LICENSE) are retained.
