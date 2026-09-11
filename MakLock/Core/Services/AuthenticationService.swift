import AppKit
import LocalAuthentication
import Foundation

protocol PasswordAttemptLimiting {
    func currentDecision() -> PasswordAccessDecision
    func recordFailure() -> PasswordAccessDecision
    func recordBlockedAttempt(remainingSeconds: Int)
    func resetAfterSuccessfulPassword()
}

enum PasswordRecoveryAuthorizationResult: Equatable {
    case authorized(PasswordRecoveryAuthorization)
    case failure(AuthError)
    case cancelled
}

enum PasswordRecoveryResetResult: Equatable {
    case success
    case validationFailure(PasswordSetupValidation)
    case failure(AuthError)
}

final class PasswordRecoveryService {
    static let shared = PasswordRecoveryService()

    private let authenticationService: AuthenticationService
    private let passwordStore: PasswordStoring
    private let passwordAttemptLimiter: PasswordAttemptLimiting
    private let now: () -> TimeInterval
    private var authorizationState = PasswordRecoveryAuthorizationState()
    private let authorizationLifetime: TimeInterval = 120

    init(
        authenticationService: AuthenticationService = .shared,
        passwordStore: PasswordStoring = KeychainManager.shared,
        passwordAttemptLimiter: PasswordAttemptLimiting = PasswordAttemptLimiter.shared,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.authenticationService = authenticationService
        self.passwordStore = passwordStore
        self.passwordAttemptLimiter = passwordAttemptLimiter
        self.now = now
    }

    func isEligible(presentedDisplayID: CGDirectDisplayID?) -> Bool {
        guard let presentedDisplayID,
              let mainScreen = NSScreen.main ?? NSScreen.screens.first,
              let mainDisplayID = DisplaySecurityMonitor.descriptor(for: mainScreen)?.displayID else {
            return false
        }

        return PasswordRecoveryPolicy.isEligible(
            isPrimaryDisplay: presentedDisplayID == mainDisplayID,
            displayProtectionEnabled: Defaults.shared.lockOnDisplayChange,
            displayStatus: DisplaySecurityMonitor.currentConfigurationStatus()
        )
    }

    func authorize(
        presentedDisplayID: CGDirectDisplayID?,
        completion: @escaping (PasswordRecoveryAuthorizationResult) -> Void
    ) {
        guard isEligible(presentedDisplayID: presentedDisplayID) else {
            completion(.failure(.passwordRecoveryUnavailable))
            return
        }

        authenticationService.authenticateWithSystemFallback(
            reason: String(localized: "Reset MakLock App Password with Mac Login")
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                guard self.isEligible(presentedDisplayID: presentedDisplayID) else {
                    completion(.failure(.passwordRecoveryUnavailable))
                    return
                }
                completion(.authorized(self.authorizationState.issue(
                    now: self.now(),
                    lifetime: self.authorizationLifetime
                )))
            case .failure(let error):
                completion(.failure(error))
            case .cancelled:
                completion(.cancelled)
            }
        }
    }

    func resetPassword(
        _ password: String,
        confirmation: String,
        authorization: PasswordRecoveryAuthorization,
        presentedDisplayID: CGDirectDisplayID?
    ) -> PasswordRecoveryResetResult {
        let validation = PasswordSetupPolicy.validate(
            password: password,
            confirmation: confirmation
        )
        guard validation == .valid else {
            return .validationFailure(validation)
        }
        guard isEligible(presentedDisplayID: presentedDisplayID) else {
            authorizationState.invalidate(authorization)
            return .failure(.passwordRecoveryUnavailable)
        }
        guard authorizationState.isValid(authorization, now: now()) else {
            return .failure(.passwordRecoveryExpired)
        }

        switch passwordStore.savePassword(password) {
        case .saved:
            authorizationState.invalidate(authorization)
            passwordAttemptLimiter.resetAfterSuccessfulPassword()
            Defaults.shared.isBackupPasswordSet = true
            AppMonitorService.shared.clearAllAuthentications()
            SecurityEventStore.shared.record(
                kind: .passwordRecovery,
                action: .passwordReset,
                succeeded: true
            )
            NSLog("[MakLock] App password reset after macOS owner authentication")
            return .success
        case .encodingFailure:
            return .failure(.passwordDataInvalid)
        case .accessFailure(let status):
            NSLog("[MakLock] App password reset Keychain update failed: %d", status)
            return .failure(.passwordStorageUnavailable)
        }
    }

    func cancel(_ authorization: PasswordRecoveryAuthorization?) {
        guard let authorization else { return }
        authorizationState.invalidate(authorization)
    }
}

extension PasswordAttemptLimiter: PasswordAttemptLimiting {}

/// Handles Touch ID and password authentication.
final class AuthenticationService {
    static let shared = AuthenticationService()

    /// Whether a Touch ID evaluation is currently in progress.
    private(set) var isAuthenticating = false

    /// The active LAContext — kept so it can be cancelled on overlay dismiss.
    private var activeContext: LAContext?
    private var activeRequestID: UUID?
    private var activeCompletion: ((AuthResult) -> Void)?
    private var authenticationTimeout: DispatchWorkItem?

    private let passwordStore: PasswordStoring
    private let passwordAttemptLimiter: PasswordAttemptLimiting
    private let isPasswordBruteForceProtectionEnabled: () -> Bool
    private let makeContext: () -> LAContext
    private let authenticationTimeoutSeconds: TimeInterval

    init(
        passwordStore: PasswordStoring = KeychainManager.shared,
        passwordAttemptLimiter: PasswordAttemptLimiting = PasswordAttemptLimiter.shared,
        isPasswordBruteForceProtectionEnabled: @escaping () -> Bool = {
            Defaults.shared.passwordBruteForceProtectionEnabled
        },
        makeContext: @escaping () -> LAContext = { LAContext() },
        authenticationTimeoutSeconds: TimeInterval = 120
    ) {
        self.passwordStore = passwordStore
        self.passwordAttemptLimiter = passwordAttemptLimiter
        self.isPasswordBruteForceProtectionEnabled = isPasswordBruteForceProtectionEnabled
        self.makeContext = makeContext
        self.authenticationTimeoutSeconds = authenticationTimeoutSeconds
    }

    func authenticateWithTouchID(reason: String = "Unlock this app", completion: @escaping (AuthResult) -> Void) {
        evaluate(policy: .deviceOwnerAuthenticationWithBiometrics, reason: reason, completion: completion)
    }

    /// Deliver completion locally; invalidate() is not a guarantee that macOS replies.
    func cancelAuthentication() {
        guard let requestID = activeRequestID else { return }
        finishAuthentication(requestID: requestID, result: .cancelled)
    }

    /// Verify the backup password.
    func authenticateWithPassword(_ password: String) -> AuthResult {
        guard !isAuthenticating else { return .cancelled }
        isAuthenticating = true
        defer { isAuthenticating = false }
        if isPasswordBruteForceProtectionEnabled() {
            switch passwordAttemptLimiter.currentDecision() {
            case .allowed:
                break
            case .delayed(let remainingSeconds):
                passwordAttemptLimiter.recordBlockedAttempt(remainingSeconds: remainingSeconds)
                return .failure(.passwordRetryAfter(remainingSeconds))
            case .locked(let remainingSeconds):
                passwordAttemptLimiter.recordBlockedAttempt(remainingSeconds: remainingSeconds)
                return .failure(.passwordLocked(remainingSeconds))
            }
        }

        let verification = passwordStore.verifyPassword(password)
        switch PasswordAuthenticationPolicy.resolve(verification: verification) {
        case .authenticated:
            passwordAttemptLimiter.resetAfterSuccessfulPassword()
            return .success
        case .failure(let error):
            if case .accessFailure(let status) = verification {
                NSLog("[MakLock] App password Keychain access failed: %d", status)
            } else if verification == .decodeFailure {
                NSLog("[MakLock] Stored app password is not valid UTF-8")
            }
            return .failure(error)
        case .recordMismatch:
            break
        }

        guard isPasswordBruteForceProtectionEnabled() else {
            return .failure(.wrongPassword)
        }

        switch passwordAttemptLimiter.recordFailure() {
        case .allowed:
            return .failure(.wrongPassword)
        case .delayed(let remainingSeconds):
            return .failure(.passwordRetryAfter(remainingSeconds))
        case .locked(let remainingSeconds):
            return .failure(.passwordLocked(remainingSeconds))
        }
    }

    func authenticateWithSystemFallback(reason: String, completion: @escaping (AuthResult) -> Void) {
        evaluate(policy: .deviceOwnerAuthentication, reason: reason, completion: completion)
    }

    private func evaluate(policy: LAPolicy, reason: String, completion: @escaping (AuthResult) -> Void) {
        guard !isAuthenticating else {
            completion(.cancelled)
            return
        }
        let context = makeContext()
        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            completion(.failure(mapLAError(error)))
            return
        }

        let requestID = UUID()
        activeRequestID = requestID
        activeContext = context
        activeCompletion = completion
        isAuthenticating = true

        let timeout = DispatchWorkItem { [weak self] in
            self?.finishAuthentication(requestID: requestID, result: .cancelled)
        }
        authenticationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + authenticationTimeoutSeconds, execute: timeout)
        context.evaluatePolicy(policy, localizedReason: reason) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let result: AuthResult
                if success {
                    result = .success
                } else if let error = error as? LAError,
                          [.userCancel, .appCancel, .systemCancel].contains(error.code) {
                    result = .cancelled
                } else {
                    result = .failure(self.mapLAError(error as NSError?))
                }
                self.finishAuthentication(requestID: requestID, result: result)
            }
        }
    }

    private func finishAuthentication(requestID: UUID, result: AuthResult) {
        guard activeRequestID == requestID else { return }
        let completion = activeCompletion
        let context = activeContext
        authenticationTimeout?.cancel()
        authenticationTimeout = nil
        activeRequestID = nil
        activeCompletion = nil
        activeContext = nil
        isAuthenticating = false
        context?.invalidate()
        completion?(result)
    }

    /// Check if Touch ID is available on this Mac.
    var isTouchIDAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    // MARK: - Private

    private func mapLAError(_ error: NSError?) -> AuthError {
        guard let error else { return .systemError("Unknown error") }

        switch LAError.Code(rawValue: error.code) {
        case .biometryNotAvailable:
            return .biometryNotAvailable
        case .biometryNotEnrolled:
            return .biometryNotEnrolled
        case .biometryLockout:
            return .biometryLockout
        default:
            return .systemError(error.localizedDescription)
        }
    }
}
