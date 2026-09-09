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
