import Foundation

/// Authentication methods supported by MakLock.
enum AuthMethod: String, Codable, CaseIterable {
    /// Touch ID biometric authentication.
    case touchID

    /// Backup password stored in Keychain.
    case password
}

enum PasswordSetupValidation: Equatable {
    case valid
    case empty
    case tooShort
    case surroundingWhitespace
    case mismatch

    var localizedMessage: String? {
        switch self {
        case .valid:
            return nil
        case .empty:
            return String(localized: "Password cannot be empty.")
        case .tooShort:
            return String(localized: "Password must be at least 4 characters.")
        case .surroundingWhitespace:
            return String(localized: "Password cannot begin or end with spaces.")
        case .mismatch:
            return String(localized: "Passwords do not match.")
        }
    }
}

enum PasswordSetupPolicy {
    static func validate(password: String, confirmation: String) -> PasswordSetupValidation {
        guard !password.isEmpty else { return .empty }
        guard password.count >= 4 else { return .tooShort }
        guard password == password.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .surroundingWhitespace
        }
        guard password == confirmation else { return .mismatch }
        return .valid
    }
}

enum PasswordRecoveryPolicy {
    static func isEligible(
        isPrimaryDisplay: Bool,
        displayProtectionEnabled: Bool,
        displayStatus: DisplayConfigurationStatus
    ) -> Bool {
        guard isPrimaryDisplay else { return false }
        return !displayProtectionEnabled || displayStatus.isTrusted
    }
}

enum PasswordAuthenticationResolution: Equatable {
    case authenticated
    case recordMismatch
    case failure(AuthError)
}

enum PasswordAuthenticationPolicy {
    static func resolve(
        verification: PasswordVerificationResult
    ) -> PasswordAuthenticationResolution {
        switch verification {
        case .match:
            return .authenticated
        case .mismatch:
            return .recordMismatch
        case .notFound:
            return .failure(.noPasswordSet)
        case .accessFailure:
            return .failure(.passwordStorageUnavailable)
        case .decodeFailure:
            return .failure(.passwordDataInvalid)
        }
    }
}

struct PasswordRecoveryAuthorization: Equatable {
    fileprivate let id: UUID
    let expiresAt: TimeInterval
}

struct PasswordRecoveryAuthorizationState {
    private(set) var activeAuthorization: PasswordRecoveryAuthorization?

    mutating func issue(now: TimeInterval, lifetime: TimeInterval) -> PasswordRecoveryAuthorization {
        let authorization = PasswordRecoveryAuthorization(
            id: UUID(),
            expiresAt: now + lifetime
        )
        activeAuthorization = authorization
        return authorization
    }

    mutating func isValid(
        _ authorization: PasswordRecoveryAuthorization,
        now: TimeInterval
    ) -> Bool {
        guard activeAuthorization == authorization else {
            return false
        }
        guard now <= authorization.expiresAt else {
            activeAuthorization = nil
            return false
        }
        return true
    }

    mutating func invalidate(_ authorization: PasswordRecoveryAuthorization) {
        if activeAuthorization == authorization {
            activeAuthorization = nil
        }
    }
}

/// Result of an authentication attempt.
enum AuthResult: Equatable {
    case success
    case failure(AuthError)
    case cancelled
}

/// Authentication errors.
enum AuthError: Error, LocalizedError, Equatable {
    case biometryNotAvailable
    case biometryNotEnrolled
    case biometryLockout
    case wrongPassword
    case passwordRetryAfter(Int)
    case passwordLocked(Int)
    case noPasswordSet
    case passwordStorageUnavailable
    case passwordDataInvalid
    case passwordRecoveryUnavailable
    case passwordRecoveryExpired
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
        case .passwordStorageUnavailable:
            return String(localized: "The app password could not be accessed. No failed attempt was recorded.")
        case .passwordDataInvalid:
            return String(localized: "The stored app password is invalid. Use password recovery to replace it.")
        case .passwordRecoveryUnavailable:
            return String(localized: "Password recovery is available only on the primary trusted display.")
        case .passwordRecoveryExpired:
            return String(localized: "Password recovery authorization expired. Authenticate again.")
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
