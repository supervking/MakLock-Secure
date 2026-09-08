import Foundation

final class PasswordAttemptLimiter {
    static let shared = PasswordAttemptLimiter()

    private let lock = NSLock()
    private var state: PasswordAttemptState

    private init() {
        state = KeychainManager.shared.loadPasswordAttemptState() ?? PasswordAttemptState()
    }

    func currentDecision() -> PasswordAccessDecision {
        lock.lock()
        defer { lock.unlock() }

        let previousState = state
        let decision = state.decision(
            nowWallTime: Date().timeIntervalSince1970,
            nowUptime: ProcessInfo.processInfo.systemUptime,
            bootIdentifier: SystemBootIdentity.current
        )
        if state != previousState {
            persistState()
        }
        return decision
    }

    func recordFailure() -> PasswordAccessDecision {
        lock.lock()
        defer { lock.unlock() }

        let decision = state.recordFailure(
            nowWallTime: Date().timeIntervalSince1970,
            nowUptime: ProcessInfo.processInfo.systemUptime,
            bootIdentifier: SystemBootIdentity.current
        )
        persistState()

        switch decision {
        case .allowed:
            break
        case .delayed(let remainingSeconds):
            SecurityEventStore.shared.record(
                kind: .passwordFailure,
                action: .retryDelayed,
                succeeded: false,
                numericDetail: remainingSeconds
            )
        case .locked(let remainingSeconds):
            SecurityEventStore.shared.record(
                kind: .passwordLockout,
                action: .passwordBlocked,
                succeeded: true,
                numericDetail: remainingSeconds
            )
        }

        return decision
    }

    func recordBlockedAttempt(remainingSeconds: Int) {
        SecurityEventStore.shared.record(
            kind: .blockedPasswordAttempt,
            action: .passwordBlocked,
            succeeded: true,
            numericDetail: remainingSeconds
        )
    }

    func resetAfterSuccessfulPassword() {
        lock.lock()
        defer { lock.unlock() }
        state.recordSuccess()
        KeychainManager.shared.deletePasswordAttemptState()
    }

    private func persistState() {
        guard !KeychainManager.shared.savePasswordAttemptState(state) else { return }
        NSLog("[MakLock] Failed to persist password attempt state")
    }
}
