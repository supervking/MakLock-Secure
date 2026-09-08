import Foundation

/// Authentication methods supported by MakLock.
enum AuthMethod: String, Codable, CaseIterable {
    /// Touch ID biometric authentication.
    case touchID

    /// Backup password stored in Keychain.
    case password
}

/// Result of an authentication attempt.
enum AuthResult {
    case success
    case failure(AuthError)
    case cancelled
}

/// Authentication errors.
enum AuthError: Error, LocalizedError {
    case biometryNotAvailable
    case biometryNotEnrolled
    case biometryLockout
    case wrongPassword
    case passwordRetryAfter(Int)
    case passwordLocked(Int)
    case noPasswordSet
    case systemError(String)

    var errorDescription: String? {
        switch self {
        case .biometryNotAvailable:
            return String(localized: "Touch ID is not available on this Mac.")
        case .biometryNotEnrolled:
            return String(localized: "No fingerprints are enrolled in Touch ID.")
        case .biometryLockout:
            return String(localized: "Touch ID is locked. Use your password instead.")
        case .wrongPassword:
            return String(localized: "Incorrect password. Please try again.")
        case .passwordRetryAfter(let remainingSeconds):
            return String.localizedStringWithFormat(
                NSLocalizedString("Incorrect password. Try again in %lld seconds.", comment: "Password retry delay"),
                Int64(remainingSeconds)
            )
        case .passwordLocked(let remainingSeconds):
            return String.localizedStringWithFormat(
                NSLocalizedString("Password unlock is locked for %@.", comment: "Password lockout remaining duration"),
                Self.formattedDuration(seconds: remainingSeconds)
            )
        case .noPasswordSet:
            return String(localized: "No backup password has been set. Go to Settings → Security.")
        case .systemError(let message):
            return message
        }
    }

    private static func formattedDuration(seconds: Int) -> String {
        if seconds >= 3600 {
            let hours = Int(ceil(Double(seconds) / 3600))
            return String.localizedStringWithFormat(
                NSLocalizedString("%lld h", comment: "Duration in hours"),
                Int64(hours)
            )
        }

        if seconds >= 60 {
            let minutes = Int(ceil(Double(seconds) / 60))
            return String.localizedStringWithFormat(
                NSLocalizedString("%lld min", comment: "Duration in minutes"),
                Int64(minutes)
            )
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("%lld sec", comment: "Duration in seconds"),
            Int64(max(1, seconds))
        )
    }
}
