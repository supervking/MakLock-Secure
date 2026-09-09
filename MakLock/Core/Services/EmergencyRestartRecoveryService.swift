import AppKit
import CryptoKit
import Foundation

final class EmergencyRestartRecoveryService {
    static let shared = EmergencyRestartRecoveryService()

    private var state: EmergencyRestartRecoveryState
    private(set) var configuration: EmergencyRestartRecoveryConfiguration
    private var hasProcessedCurrentLaunch = false

    private init() {
        configuration = (
            Defaults.shared.emergencyRestartConfiguration
        ).normalized
        state = Defaults.shared.emergencyRestartState
        NSLog(
            "[MakLock] Emergency restart recovery configuration: %@",
            configuration.isEnabled ? "enabled" : "disabled"
        )
    }

    @discardableResult
    func updateConfiguration(
        _ configuration: EmergencyRestartRecoveryConfiguration
    ) -> Bool {
        let normalized = configuration.normalized
        Defaults.shared.emergencyRestartConfiguration = normalized
        guard Defaults.shared.synchronizeEmergencyRestartState(),
              Defaults.shared.emergencyRestartConfiguration == normalized else {
            NSLog("[MakLock] Failed to save emergency restart recovery configuration")
            return false
        }

        self.configuration = normalized
        if !normalized.isEnabled {
            state.invalidate()
            persistState()
        }
        return true
    }

    var isRecoveryEnabled: Bool {
        effectiveConfiguration.isEnabled
    }

    func processCurrentLaunch(configuration status: DisplayConfigurationStatus) {
        guard !hasProcessedCurrentLaunch else { return }
        hasProcessedCurrentLaunch = true

        let digest = Self.displayDigest(status.currentFingerprints)
        let now = Date().timeIntervalSince1970
        let previousState = state
        let configuration = effectiveConfiguration
        let outcome = state.processLaunch(
            now: now,
            currentBootIdentifier: SystemBootIdentity.current,
            currentBootStartedAt: now - ProcessInfo.processInfo.systemUptime,
            displayDigest: digest,
            isUntrustedDisplayConfiguration: status.isConfigured && !status.isTrusted,
            configuration: configuration
        )
        if state != previousState {
            persistState()
        }

        switch outcome {
        case .idle, .waitingForRestart, .bypassActive:
            break
        case .reset:
            SecurityEventStore.shared.record(
                kind: .emergencyRestartRecovery,
                action: .recoveryReset,
                succeeded: true
            )
        case .progressed:
            terminateProtectedApplications()
            SecurityEventStore.shared.record(
                kind: .emergencyRestartRecovery,
                action: .recoveryProgressed,
                succeeded: true
            )
            NSLog("[MakLock] Emergency restart recovery advanced")
        case .activated:
            terminateProtectedApplications()
            SecurityEventStore.shared.record(
                kind: .emergencyRestartRecovery,
                action: .recoveryActivated,
                succeeded: true
            )
            NSLog("[MakLock] Emergency display alert recovery activated for current boot")
        }
    }

    func prepareAlertRestart(
        configuration status: DisplayConfigurationStatus
    ) -> Bool {
        let prepared = state.prepareRestart(
            now: Date().timeIntervalSince1970,
            currentBootIdentifier: SystemBootIdentity.current,
            displayDigest: Self.displayDigest(status.currentFingerprints),
            isUntrustedDisplayConfiguration: status.isConfigured && !status.isTrusted,
            configuration: effectiveConfiguration
        )

        if prepared, !persistState() {
            state.cancelPendingRestart(currentBootIdentifier: SystemBootIdentity.current)
            persistState()
            return false
        }

        terminateProtectedApplications()
        SecurityEventStore.shared.record(
            kind: .emergencyRestartRecovery,
            action: .restartRequested,
            succeeded: true,
            numericDetail: status.currentFingerprints.count
        )
        return prepared
    }

    func cancelPendingRestart() {
        state.cancelPendingRestart(currentBootIdentifier: SystemBootIdentity.current)
        persistState()
        SecurityEventStore.shared.record(
            kind: .emergencyRestartRecovery,
            action: .restartFailed,
            succeeded: false
        )
    }

    func shouldSuppressDisplayAlert(
        configuration status: DisplayConfigurationStatus
    ) -> Bool {
        guard effectiveConfiguration.isEnabled else {
            invalidateRecoveryState()
            return false
        }

        let previousState = state
        let shouldSuppress = state.isBypassActive(
            currentBootIdentifier: SystemBootIdentity.current,
            displayDigest: Self.displayDigest(status.currentFingerprints),
            isUntrustedDisplayConfiguration: status.isConfigured && !status.isTrusted
        )
        if state != previousState {
            persistState()
        }
        return shouldSuppress
    }

    func invalidateForTrustedDisplayConfiguration() {
        invalidateRecoveryState()
    }

    func invalidateRecoveryState() {
        let previousState = state
        state.invalidate()
        guard state != previousState else { return }
        persistState()
        SecurityEventStore.shared.record(
            kind: .emergencyRestartRecovery,
            action: .recoveryReset,
            succeeded: true
        )
    }

    private func terminateProtectedApplications() {
        AppMonitorService.shared.clearAllAuthentications()
        OverlayWindowService.shared.dismissWithoutAuthentication()

        let protectedBundleIdentifiers = Set(
            Defaults.shared.protectedApps
                .filter(\.isEnabled)
                .map(\.bundleIdentifier)
        )
        var terminatedCount = 0

        for application in NSWorkspace.shared.runningApplications {
            guard let bundleIdentifier = application.bundleIdentifier,
                  protectedBundleIdentifiers.contains(bundleIdentifier),
                  !SafetyManager.isBlacklisted(bundleIdentifier) else {
                continue
            }

            if application.forceTerminate() {
                terminatedCount += 1
            }
        }

        if terminatedCount > 0 {
            SecurityEventStore.shared.record(
                kind: .emergencyRestartRecovery,
                action: .forcedQuit,
                succeeded: true,
                affectedCount: terminatedCount
            )
        }
    }

    private var effectiveConfiguration: EmergencyRestartRecoveryConfiguration {
        var effective = configuration
        effective.isEnabled = effective.isEnabled
            && Defaults.shared.appSettings.isProtectionEnabled
            && Defaults.shared.lockOnDisplayChange
        return effective
    }

    @discardableResult
    private func persistState() -> Bool {
        Defaults.shared.emergencyRestartState = state
        let saved = Defaults.shared.synchronizeEmergencyRestartState()
            && Defaults.shared.emergencyRestartState == state
        if !saved {
            NSLog("[MakLock] Failed to save emergency restart recovery state")
        }
        return saved
    }

    private static func displayDigest(_ fingerprints: [String]) -> String {
        let normalized = fingerprints.sorted().joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

final class SystemRestartService {
    static let shared = SystemRestartService()

    private init() {}

    func requestRestart(completion: @escaping (Bool) -> Void) {
        guard let script = NSAppleScript(
            source: "tell application \"System Events\" to restart"
        ) else {
            completion(false)
            return
        }

        DispatchQueue.main.async {
            var error: NSDictionary?
            _ = script.executeAndReturnError(&error)
            completion(error == nil)
        }
    }
}
