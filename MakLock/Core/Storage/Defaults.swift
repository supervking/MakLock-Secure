import Foundation

/// Centralized UserDefaults wrapper for MakLock settings.
final class Defaults {
    static let shared = Defaults()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Key: String {
        case protectedApps
        case appSettings
        case hasCompletedOnboarding
        case backupPasswordSet
        case prefersPasswordUnlock
        case lockOnNetworkLoss
        case networkLossGraceSeconds
        case lockOnDisplayChange
        case trustedDisplayFingerprints
        case quitProtectedAppsAfterRestart
        case passwordBruteForceProtectionEnabled
        case lastHandledBootIdentifier
        case securityEventRecords
    }

    private init() {}

    // MARK: - Protected Apps

    /// Persisted list of protected applications.
    var protectedApps: [ProtectedApp] {
        get {
            guard let data = defaults.data(forKey: Key.protectedApps.rawValue),
                  let apps = try? decoder.decode([ProtectedApp].self, from: data) else {
                return []
            }
            return apps
        }
        set {
            let data = try? encoder.encode(newValue)
            defaults.set(data, forKey: Key.protectedApps.rawValue)
        }
    }

    // MARK: - App Settings

    /// User preferences for MakLock behavior.
    var appSettings: AppSettings {
        get {
            guard let data = defaults.data(forKey: Key.appSettings.rawValue),
                  let settings = try? decoder.decode(AppSettings.self, from: data) else {
                return AppSettings()
            }
            return settings
        }
        set {
            let data = try? encoder.encode(newValue)
            defaults.set(data, forKey: Key.appSettings.rawValue)
        }
    }

    // MARK: - Flags

    /// Whether the user has completed first-launch onboarding.
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding.rawValue) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding.rawValue) }
    }

    /// Whether a backup password has been configured.
    var isBackupPasswordSet: Bool {
        get { defaults.bool(forKey: Key.backupPasswordSet.rawValue) }
        set { defaults.set(newValue, forKey: Key.backupPasswordSet.rawValue) }
    }

    /// Whether the lock overlay should start with a focused password field.
    /// This is intentionally stored outside AppSettings so adding it does not
    /// invalidate existing encoded AppSettings values from earlier releases.
    var prefersPasswordUnlock: Bool {
        get {
            guard defaults.object(forKey: Key.prefersPasswordUnlock.rawValue) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.prefersPasswordUnlock.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.prefersPasswordUnlock.rawValue) }
    }

    var lockOnNetworkLoss: Bool {
        get { defaults.bool(forKey: Key.lockOnNetworkLoss.rawValue) }
        set { defaults.set(newValue, forKey: Key.lockOnNetworkLoss.rawValue) }
    }

    var networkLossGraceSeconds: Int {
        get {
            guard defaults.object(forKey: Key.networkLossGraceSeconds.rawValue) != nil else {
                return 60
            }
            return min(300, max(60, defaults.integer(forKey: Key.networkLossGraceSeconds.rawValue)))
        }
        set { defaults.set(min(300, max(60, newValue)), forKey: Key.networkLossGraceSeconds.rawValue) }
    }

    var lockOnDisplayChange: Bool {
        get { defaults.bool(forKey: Key.lockOnDisplayChange.rawValue) }
        set { defaults.set(newValue, forKey: Key.lockOnDisplayChange.rawValue) }
    }

    var trustedDisplayFingerprints: [String] {
        get { defaults.stringArray(forKey: Key.trustedDisplayFingerprints.rawValue) ?? [] }
        set { defaults.set(newValue.sorted(), forKey: Key.trustedDisplayFingerprints.rawValue) }
    }

    var quitProtectedAppsAfterRestart: Bool {
        get { defaults.bool(forKey: Key.quitProtectedAppsAfterRestart.rawValue) }
        set { defaults.set(newValue, forKey: Key.quitProtectedAppsAfterRestart.rawValue) }
    }

    var passwordBruteForceProtectionEnabled: Bool {
        get { defaults.bool(forKey: Key.passwordBruteForceProtectionEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.passwordBruteForceProtectionEnabled.rawValue) }
    }

    var lastHandledBootIdentifier: String? {
        get { defaults.string(forKey: Key.lastHandledBootIdentifier.rawValue) }
        set { defaults.set(newValue, forKey: Key.lastHandledBootIdentifier.rawValue) }
    }

    var securityEventRecords: [SecurityEventRecord] {
        get {
            guard let data = defaults.data(forKey: Key.securityEventRecords.rawValue),
                  let records = try? decoder.decode([SecurityEventRecord].self, from: data) else {
                return []
            }
            return records
        }
        set {
            guard let data = try? encoder.encode(newValue) else { return }
            defaults.set(data, forKey: Key.securityEventRecords.rawValue)
        }
    }
}
