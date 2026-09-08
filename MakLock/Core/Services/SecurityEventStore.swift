import Foundation

final class SecurityEventStore {
    static let shared = SecurityEventStore()

    private let lock = NSLock()

    private init() {}

    func record(
        kind: SecurityEventKind,
        action: SecurityEventAction,
        succeeded: Bool,
        affectedCount: Int = 0,
        numericDetail: Int? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        var records = SecurityEventRetention.retained(
            Defaults.shared.securityEventRecords,
            now: now
        )
        records.append(SecurityEventRecord(
            timestamp: now,
            kind: kind,
            action: action,
            succeeded: succeeded,
            affectedCount: max(0, affectedCount),
            numericDetail: numericDetail
        ))
        Defaults.shared.securityEventRecords = SecurityEventRetention.retained(records, now: now)
    }

    func recentRecords() -> [SecurityEventRecord] {
        lock.lock()
        defer { lock.unlock() }

        let retained = SecurityEventRetention.retained(
            Defaults.shared.securityEventRecords,
            now: Date()
        )
        Defaults.shared.securityEventRecords = retained
        return retained.reversed()
    }
}
