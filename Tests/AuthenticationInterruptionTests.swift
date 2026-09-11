import AppKit
import LocalAuthentication

@main
enum AuthenticationInterruptionTests {
    static func main() {
        let context = ControlledContext()
        let service = AuthenticationService(passwordStore: InertPasswordStore(), passwordAttemptLimiter: CountingLimiter(), makeContext: { context })
        var results: [AuthResult] = []
        service.authenticateWithSystemFallback(reason: "Recovery validation") { results.append($0) }
        precondition(service.isAuthenticating)
        service.cancelAuthentication()
        precondition(!service.isAuthenticating)
        precondition(results == [.cancelled], "Cancel must restore the caller even when macOS never replies")
        context.reply?(true, nil)
        drainMainQueue()
        precondition(results == [.cancelled], "Late success must not unlock after cancellation")
        staleReplyCannotEndNextRequest()
        timeoutRestoresCaller()
        storageFailuresNeverCountAsMismatch()
        print("Authentication interruption tests passed")
    }

    static func drainMainQueue() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    }

    static func staleReplyCannotEndNextRequest() {
        let first = ControlledContext()
        let second = ControlledContext()
        var contexts = [first, second]
        let service = AuthenticationService(passwordStore: InertPasswordStore(), passwordAttemptLimiter: CountingLimiter(), makeContext: { contexts.removeFirst() })
        var results: [AuthResult] = []
        service.authenticateWithSystemFallback(reason: "First") { results.append($0) }
        service.cancelAuthentication()
        service.authenticateWithSystemFallback(reason: "Second") { results.append($0) }
        first.reply?(true, nil)
        drainMainQueue()
        precondition(service.isAuthenticating)
        precondition(results == [.cancelled])
        second.reply?(false, LAError(.systemCancel))
        drainMainQueue()
        precondition(!service.isAuthenticating)
        precondition(results == [.cancelled, .cancelled])
    }

    static func timeoutRestoresCaller() {
        let context = ControlledContext()
        let service = AuthenticationService(passwordStore: InertPasswordStore(), passwordAttemptLimiter: CountingLimiter(), makeContext: { context }, authenticationTimeoutSeconds: 0.01)
        var results: [AuthResult] = []
        service.authenticateWithSystemFallback(reason: "Timeout") { results.append($0) }
        drainMainQueue()
        precondition(!service.isAuthenticating)
        precondition(results == [.cancelled])
        context.reply?(true, nil)
        drainMainQueue()
        precondition(results == [.cancelled])
    }

    static func storageFailuresNeverCountAsMismatch() {
        let store = InertPasswordStore()
        let limiter = CountingLimiter()
        let service = AuthenticationService(passwordStore: store, passwordAttemptLimiter: limiter)
        for outcome: PasswordVerificationResult in [.notFound, .decodeFailure, .accessFailure(-34018)] {
            store.outcome = outcome
            _ = service.authenticateWithPassword("synthetic value")
        }
        precondition(limiter.failures == 0)
        store.outcome = .mismatch
        _ = service.authenticateWithPassword("synthetic value")
        precondition(limiter.failures == 1)
    }
}

final class InertPasswordStore: PasswordStoring {
    var outcome: PasswordVerificationResult = .mismatch
    func savePassword(_ password: String) -> PasswordSaveResult { .saved }
    func verifyPassword(_ password: String) -> PasswordVerificationResult { outcome }
}
final class CountingLimiter: PasswordAttemptLimiting {
    var failures = 0
    func currentDecision() -> PasswordAccessDecision { .allowed }
    func recordFailure() -> PasswordAccessDecision { failures += 1; return .allowed }
    func recordBlockedAttempt(remainingSeconds: Int) {}
    func resetAfterSuccessfulPassword() {}
}

final class ControlledContext: LAContext {
    var reply: ((Bool, Error?) -> Void)?
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool { true }
    override func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping (Bool, Error?) -> Void) {
        self.reply = reply
    }
    override func invalidate() {}
}

// External application boundaries are inert; the authentication service is real.
final class Defaults {
    static let shared = Defaults()
    var passwordBruteForceProtectionEnabled = true
    var lockOnDisplayChange = true
    var isBackupPasswordSet = false
}
final class AppMonitorService {
    static let shared = AppMonitorService()
    func clearAllAuthentications() {}
}
final class DisplaySecurityMonitor {
    struct Descriptor { let displayID: CGDirectDisplayID }
    static func descriptor(for screen: NSScreen) -> Descriptor? { nil }
    static func currentConfigurationStatus() -> DisplayConfigurationStatus {
        DisplayConfigurationStatus(currentFingerprints: [], trustedFingerprints: [])
    }
}
final class SecurityEventStore {
    static let shared = SecurityEventStore()
    func record(kind: SecurityEventKind, action: SecurityEventAction, succeeded: Bool, numericDetail: Int? = nil) {}
}
