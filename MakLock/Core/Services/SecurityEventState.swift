import Foundation

enum SecurityLockReason: String {
    case networkLoss
    case displayChange
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
