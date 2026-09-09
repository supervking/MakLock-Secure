import Foundation

enum PasswordAccessDecision: Equatable {
    case allowed
    case delayed(remainingSeconds: Int)
    case locked(remainingSeconds: Int)
}

struct PasswordAttemptState: Codable, Equatable {
    static let failureWindowSeconds: TimeInterval = 30 * 60
    static let lockoutSeconds: TimeInterval = 3 * 60 * 60
    static let retryDelays: [TimeInterval] = [2, 4, 30, 5 * 60]

    var failureTimestamps: [TimeInterval] = []
    var retryUntilWallTime: TimeInterval?
    var retryStartedAtUptime: TimeInterval?
    var retryDuration: TimeInterval?
    var lockoutUntilWallTime: TimeInterval?
    var lockoutStartedAtUptime: TimeInterval?
    var timerBootIdentifier: String?

    mutating func decision(
        nowWallTime: TimeInterval,
        nowUptime: TimeInterval,
        bootIdentifier: String
    ) -> PasswordAccessDecision {
        if let remaining = remainingSeconds(
            wallDeadline: lockoutUntilWallTime,
            monotonicStart: lockoutStartedAtUptime,
            duration: Self.lockoutSeconds,
            nowWallTime: nowWallTime,
            nowUptime: nowUptime,
            currentBootIdentifier: bootIdentifier
        ), remaining > 0 {
            return .locked(remainingSeconds: remaining)
        }

        lockoutUntilWallTime = nil
        lockoutStartedAtUptime = nil

        if let retryDuration,
           let remaining = remainingSeconds(
               wallDeadline: retryUntilWallTime,
               monotonicStart: retryStartedAtUptime,
               duration: retryDuration,
               nowWallTime: nowWallTime,
               nowUptime: nowUptime,
               currentBootIdentifier: bootIdentifier
           ), remaining > 0 {
            return .delayed(remainingSeconds: remaining)
        }

        retryUntilWallTime = nil
        retryStartedAtUptime = nil
        retryDuration = nil
        return .allowed
    }

    mutating func recordFailure(
        nowWallTime: TimeInterval,
        nowUptime: TimeInterval,
        bootIdentifier: String
    ) -> PasswordAccessDecision {
        pruneFailures(nowWallTime: nowWallTime)
        failureTimestamps.append(nowWallTime)
        timerBootIdentifier = bootIdentifier

        if failureTimestamps.count >= 5 {
            retryUntilWallTime = nil
            retryStartedAtUptime = nil
            retryDuration = nil
            lockoutUntilWallTime = nowWallTime + Self.lockoutSeconds
            lockoutStartedAtUptime = nowUptime
            return .locked(remainingSeconds: Int(Self.lockoutSeconds))
        }

        let delay = Self.retryDelays[failureTimestamps.count - 1]
        retryUntilWallTime = nowWallTime + delay
        retryStartedAtUptime = nowUptime
        retryDuration = delay
        return .delayed(remainingSeconds: Int(delay))
    }

    mutating func recordSuccess() {
        self = PasswordAttemptState()
    }

    mutating func pruneFailures(nowWallTime: TimeInterval) {
        failureTimestamps = failureTimestamps.filter {
            nowWallTime - $0 <= Self.failureWindowSeconds
        }
    }

    private func remainingSeconds(
        wallDeadline: TimeInterval?,
        monotonicStart: TimeInterval?,
        duration: TimeInterval,
        nowWallTime: TimeInterval,
        nowUptime: TimeInterval,
        currentBootIdentifier: String
    ) -> Int? {
        guard let wallDeadline else { return nil }

        var remaining = wallDeadline - nowWallTime
        if timerBootIdentifier == currentBootIdentifier,
           let monotonicStart {
            remaining = max(remaining, duration - max(0, nowUptime - monotonicStart))
        }

        return Int(ceil(max(0, remaining)))
    }
}

struct BootCleanupTracker: Equatable {
    var lastHandledBootIdentifier: String?

    mutating func registerLaunch(currentBootIdentifier: String) -> Bool {
        guard let lastHandledBootIdentifier else {
            self.lastHandledBootIdentifier = currentBootIdentifier
            return false
        }

        guard lastHandledBootIdentifier != currentBootIdentifier else {
            return false
        }

        self.lastHandledBootIdentifier = currentBootIdentifier
        return true
    }
}

struct EmergencyRestartRecoveryConfiguration: Codable, Equatable {
    static let defaultRestartCount = 5
    static let defaultWindowSeconds = 5 * 60

    var isEnabled = false
    var requiredRestartCount = defaultRestartCount
    var windowSeconds = defaultWindowSeconds

    var normalized: EmergencyRestartRecoveryConfiguration {
        EmergencyRestartRecoveryConfiguration(
            isEnabled: isEnabled,
            requiredRestartCount: min(9, max(3, requiredRestartCount)),
            windowSeconds: min(15 * 60, max(3 * 60, windowSeconds))
        )
    }
}

enum EmergencyRestartLaunchOutcome: Equatable {
    case idle
    case waitingForRestart
    case reset
    case progressed(completed: Int, remaining: Int)
    case activated
    case bypassActive
}

struct EmergencyRestartRecoveryState: Codable, Equatable {
    private(set) var sequenceStartedAt: TimeInterval?
    private(set) var completedRestartCount = 0
    private(set) var pendingRestartBootIdentifier: String?
    private(set) var pendingRestartRequestedAt: TimeInterval?
    private(set) var sequenceDisplayDigest: String?
    private(set) var bypassBootIdentifier: String?
    private(set) var bypassDisplayDigest: String?

    mutating func prepareRestart(
        now: TimeInterval,
        currentBootIdentifier: String,
        displayDigest: String,
        isUntrustedDisplayConfiguration: Bool,
        configuration: EmergencyRestartRecoveryConfiguration
    ) -> Bool {
        let configuration = configuration.normalized
        guard configuration.isEnabled,
              isUntrustedDisplayConfiguration,
              !displayDigest.isEmpty else {
            return false
        }

        if !isSequenceValid(
            now: now,
            displayDigest: displayDigest,
            configuration: configuration
        ) {
            resetSequence()
            sequenceStartedAt = now
            sequenceDisplayDigest = displayDigest
        }

        pendingRestartBootIdentifier = currentBootIdentifier
        pendingRestartRequestedAt = now
        return true
    }

    mutating func cancelPendingRestart(currentBootIdentifier: String) {
        guard pendingRestartBootIdentifier == currentBootIdentifier else { return }
        pendingRestartBootIdentifier = nil
        pendingRestartRequestedAt = nil
    }

    mutating func processLaunch(
        now: TimeInterval,
        currentBootIdentifier: String,
        currentBootStartedAt: TimeInterval,
        displayDigest: String,
        isUntrustedDisplayConfiguration: Bool,
        configuration: EmergencyRestartRecoveryConfiguration
    ) -> EmergencyRestartLaunchOutcome {
        let configuration = configuration.normalized
        let hadRecoveryState = hasRecoveryState

        guard configuration.isEnabled,
              isUntrustedDisplayConfiguration,
              !displayDigest.isEmpty else {
            invalidate()
            return hadRecoveryState ? .reset : .idle
        }

        if isBypassActive(
            currentBootIdentifier: currentBootIdentifier,
            displayDigest: displayDigest,
            isUntrustedDisplayConfiguration: true
        ) {
            return .bypassActive
        }

        guard let pendingBootIdentifier = pendingRestartBootIdentifier,
              let requestedAt = pendingRestartRequestedAt,
              let startedAt = sequenceStartedAt,
              let expectedDisplayDigest = sequenceDisplayDigest else {
            if sequenceStartedAt != nil,
               !isSequenceValid(
                   now: now,
                   displayDigest: displayDigest,
                   configuration: configuration
               ) {
                resetSequence()
                return .reset
            }
            return .idle
        }

        guard pendingBootIdentifier != currentBootIdentifier else {
            return .waitingForRestart
        }

        let restartBeganPromptly = currentBootStartedAt >= requestedAt - 5
            && currentBootStartedAt <= requestedAt + 60
        let completedInsideWindow = now >= startedAt
            && now - startedAt <= TimeInterval(configuration.windowSeconds)
        let requestPrecedesLaunch = now >= requestedAt
        let displayMatches = displayDigest == expectedDisplayDigest

        guard restartBeganPromptly,
              completedInsideWindow,
              requestPrecedesLaunch,
              displayMatches else {
            resetSequence()
            return .reset
        }

        completedRestartCount += 1
        pendingRestartBootIdentifier = nil
        pendingRestartRequestedAt = nil

        if completedRestartCount >= configuration.requiredRestartCount {
            bypassBootIdentifier = currentBootIdentifier
            bypassDisplayDigest = displayDigest
            resetSequence()
            return .activated
        }

        return .progressed(
            completed: completedRestartCount,
            remaining: configuration.requiredRestartCount - completedRestartCount
        )
    }

    mutating func isBypassActive(
        currentBootIdentifier: String,
        displayDigest: String,
        isUntrustedDisplayConfiguration: Bool
    ) -> Bool {
        guard let bypassBootIdentifier,
              let bypassDisplayDigest else {
            return false
        }

        guard isUntrustedDisplayConfiguration,
              bypassBootIdentifier == currentBootIdentifier,
              bypassDisplayDigest == displayDigest else {
            self.bypassBootIdentifier = nil
            self.bypassDisplayDigest = nil
            return false
        }

        return true
    }

    mutating func invalidate() {
        resetSequence()
        bypassBootIdentifier = nil
        bypassDisplayDigest = nil
    }

    private var hasRecoveryState: Bool {
        sequenceStartedAt != nil
            || pendingRestartBootIdentifier != nil
            || bypassBootIdentifier != nil
    }

    private func isSequenceValid(
        now: TimeInterval,
        displayDigest: String,
        configuration: EmergencyRestartRecoveryConfiguration
    ) -> Bool {
        guard let sequenceStartedAt,
              let sequenceDisplayDigest,
              now >= sequenceStartedAt,
              now - sequenceStartedAt <= TimeInterval(configuration.windowSeconds),
              sequenceDisplayDigest == displayDigest else {
            return false
        }
        return true
    }

    private mutating func resetSequence() {
        sequenceStartedAt = nil
        completedRestartCount = 0
        pendingRestartBootIdentifier = nil
        pendingRestartRequestedAt = nil
        sequenceDisplayDigest = nil
    }
}

enum BootCleanupPolicy {
    static func shouldTerminate(
        bundleIdentifier: String,
        protectedBundleIdentifiers: Set<String>,
        excludedBundleIdentifiers: Set<String>
    ) -> Bool {
        protectedBundleIdentifiers.contains(bundleIdentifier)
            && !excludedBundleIdentifiers.contains(bundleIdentifier)
    }
}

enum SecurityEventKind: String, Codable {
    case protectedAppActivation
    case networkLoss
    case displayChange
    case restartCleanup
    case idleTimeout
    case sleep
    case watchOutOfRange
    case passwordFailure
    case passwordLockout
    case blockedPasswordAttempt
    case sessionFocusRecovery
    case emergencyRestartRecovery
}

enum SecurityEventAction: String, Codable {
    case locked
    case alertShown
    case alertDismissed
    case gracefulQuit
    case forcedQuit
    case retryDelayed
    case passwordBlocked
    case focusRestored
    case restartRequested
    case restartFailed
    case recoveryProgressed
    case recoveryActivated
    case recoveryReset
    case tamperDetected
}

struct SecurityEventRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let kind: SecurityEventKind
    let action: SecurityEventAction
    let succeeded: Bool
    let affectedCount: Int
    let numericDetail: Int?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: SecurityEventKind,
        action: SecurityEventAction,
        succeeded: Bool,
        affectedCount: Int = 0,
        numericDetail: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.action = action
        self.succeeded = succeeded
        self.affectedCount = affectedCount
        self.numericDetail = numericDetail
    }
}

enum SecurityEventRetention {
    static let retentionSeconds: TimeInterval = 12 * 60 * 60
    static let maximumRecordCount = 200

    static func retained(
        _ records: [SecurityEventRecord],
        now: Date
    ) -> [SecurityEventRecord] {
        let cutoff = now.addingTimeInterval(-retentionSeconds)
        return records
            .filter { $0.timestamp >= cutoff && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(maximumRecordCount)
    }
}
