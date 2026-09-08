/// Defines applications that must never be protected by MakLock.
///
/// Protected applications can only be unlocked through the configured
/// authentication mechanism; release builds do not register a bypass shortcut.
final class SafetyManager {
    static let shared = SafetyManager()

    /// Bundle identifiers that can never be locked.
    static let systemBlacklist: Set<String> = [
        // Apple system apps
        "com.apple.Terminal",
        "com.apple.finder",
        "com.apple.ActivityMonitor",
        "com.apple.systempreferences",          // Monterey and earlier
        "com.apple.SystemSettings",              // Ventura+
        "com.apple.System-Preferences",

        // Development tools
        "com.apple.dt.Xcode",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.sublimetext.4",
        "com.jetbrains.intellij",

        // Remote access tools must remain available so security automation
        // cannot disconnect the owner from a headless Mac.
        "com.carriez.rustdesk",
        "com.splashtop.Splashtop-Streamer",
        "com.splashtop.SplashtopStreamer",
        "com.splashtop.streamer",
        "com.splashtop.SplashtopPersonal",
        "com.teamviewer.TeamViewer",
        "com.anydesk.AnyDesk",
        "com.microsoft.rdc.macos",
        "com.apple.ScreenSharing",
        "com.apple.RemoteDesktop",
        "com.google.ChromeRemoteDesktopHost",

        // MakLock itself
        "com.makmak.MakLock",
    ]

    /// Check whether an app is on the system blacklist and must never be locked.
    static func isBlacklisted(_ bundleIdentifier: String) -> Bool {
        return systemBlacklist.contains(bundleIdentifier)
    }
}
