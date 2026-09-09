import Foundation

enum SecurityLockReason: String {
    case networkLoss
    case displayChange
    case idleTimeout
    case sleep
    case watchOutOfRange

    var eventKind: SecurityEventKind {
        switch self {
        case .networkLoss:
            return .networkLoss
        case .displayChange:
            return .displayChange
        case .idleTimeout:
            return .idleTimeout
        case .sleep:
            return .sleep
        case .watchOutOfRange:
            return .watchOutOfRange
        }
    }
}

struct NetworkOutageTracker {
    private(set) var outageStartedAt: TimeInterval?
    private(set) var hasTriggered = false

    mutating func observe(
        isOnline: Bool,
        now: TimeInterval,
        graceSeconds: TimeInterval
    ) -> Bool {
        if isOnline {
            reset()
            return false
        }

        if outageStartedAt == nil {
            outageStartedAt = now
        }

        guard !hasTriggered,
              let outageStartedAt,
              now - outageStartedAt >= graceSeconds else {
            return false
        }

        hasTriggered = true
        return true
    }

    mutating func reset() {
        outageStartedAt = nil
        hasTriggered = false
    }
}

struct DisplayTrustTracker {
    private var lastTriggeredMismatch: [String]?

    mutating func observe(
        current: [String],
        trusted: [String]
    ) -> Bool {
        let normalizedCurrent = current.sorted()
        let normalizedTrusted = trusted.sorted()

        guard !normalizedTrusted.isEmpty else {
            lastTriggeredMismatch = nil
            return false
        }

        guard normalizedCurrent != normalizedTrusted else {
            lastTriggeredMismatch = nil
            return false
        }

        guard normalizedCurrent != lastTriggeredMismatch else {
            return false
        }

        lastTriggeredMismatch = normalizedCurrent
        return true
    }

    mutating func reset() {
        lastTriggeredMismatch = nil
    }
}

struct DisplayConfigurationStatus: Equatable {
    let currentFingerprints: [String]
    let trustedFingerprints: [String]

    var isConfigured: Bool {
        !trustedFingerprints.isEmpty
    }

    var isTrusted: Bool {
        isConfigured && currentFingerprints.sorted() == trustedFingerprints.sorted()
    }

    var unexpectedDisplayCount: Int {
        Self.differenceCount(source: currentFingerprints, removing: trustedFingerprints)
    }

    var missingTrustedDisplayCount: Int {
        Self.differenceCount(source: trustedFingerprints, removing: currentFingerprints)
    }

    private static func differenceCount(source: [String], removing: [String]) -> Int {
        var remainingCounts = Dictionary(grouping: removing, by: { $0 })
            .mapValues(\.count)
        var difference = 0

        for fingerprint in source {
            if let count = remainingCounts[fingerprint], count > 0 {
                remainingCounts[fingerprint] = count - 1
            } else {
                difference += 1
            }
        }

        return difference
    }
}

enum DisplayIntrusionAlertPhase: Equatable {
    case hidden
    case evaluating
    case intrusion
}

enum DisplayIntrusionAlertTransition: Equatable {
    case none
    case showEvaluatingShield
    case dismissTransientShield
    case confirmIntrusion
    case refreshIntrusion
    case awaitAuthentication
}

struct DisplayIntrusionAlertState: Equatable {
    private(set) var phase: DisplayIntrusionAlertPhase = .hidden

    mutating func beginPotentialChange() -> DisplayIntrusionAlertTransition {
        guard phase == .hidden else { return .none }
        phase = .evaluating
        return .showEvaluatingShield
    }

    mutating func observe(
        configuration status: DisplayConfigurationStatus
    ) -> DisplayIntrusionAlertTransition {
        guard status.isConfigured else {
            if phase == .evaluating {
                phase = .hidden
                return .dismissTransientShield
            }
            return .none
        }

        if status.isTrusted {
            switch phase {
            case .hidden:
                return .none
            case .evaluating:
                phase = .hidden
                return .dismissTransientShield
            case .intrusion:
                return .awaitAuthentication
            }
        }

        let wasConfirmed = phase == .intrusion
        phase = .intrusion
        return wasConfirmed ? .refreshIntrusion : .confirmIntrusion
    }

    mutating func authenticate(
        configuration status: DisplayConfigurationStatus
    ) -> Bool {
        guard phase == .intrusion, status.isTrusted else { return false }
        phase = .hidden
        return true
    }

    mutating func reset() {
        phase = .hidden
    }
}

struct ThresholdTriggerLatch {
    private(set) var hasTriggered = false

    mutating func observe(hasReachedThreshold: Bool) -> Bool {
        guard hasReachedThreshold else {
            hasTriggered = false
            return false
        }

        guard !hasTriggered else { return false }
        hasTriggered = true
        return true
    }

    mutating func reset() {
        hasTriggered = false
    }
}
