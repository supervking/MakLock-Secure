import Foundation

@main
enum SecurityLifecycleStateTests {
    static func main() {
        appliesProgressivePasswordDelays()
        locksPasswordForThreeHoursAfterFifthFailure()
        successfulPasswordResetsFailures()
        failuresExpireOutsideRollingWindow()
        applicationRestartDoesNotBypassLockout()
        macRestartDoesNotBypassLockout()
        wallClockRollbackDoesNotShortenSameBootLockout()
        lockoutExpiresAfterThreeHours()
        firstInstallationDoesNotRunBootCleanup()
        repeatedApplicationLaunchDoesNotRunBootCleanup()
        laterMacBootRunsCleanupOnce()
        bootCleanupTargetsOnlyProtectedNonRemoteApps()
        securityHistoryRetainsOnlyTwelveHours()
        securityHistoryCapsAtTwoHundredRecords()
        print("Security lifecycle state tests passed")
    }

    private static func appliesProgressivePasswordDelays() {
        var state = PasswordAttemptState()
        let boot = "boot-100"
        let expectedDelays = [2, 4, 30, 300]

        for (index, expectedDelay) in expectedDelays.enumerated() {
            let wallTime = TimeInterval(1_000 + index * 310)
            let uptime = TimeInterval(500 + index * 310)
            precondition(state.recordFailure(
                nowWallTime: wallTime,
                nowUptime: uptime,
                bootIdentifier: boot
            ) == .delayed(remainingSeconds: expectedDelay))
        }
    }

    private static func locksPasswordForThreeHoursAfterFifthFailure() {
        var state = PasswordAttemptState()
        let boot = "boot-200"

        for index in 0..<4 {
            _ = state.recordFailure(
                nowWallTime: TimeInterval(2_000 + index * 301),
                nowUptime: TimeInterval(900 + index * 301),
                bootIdentifier: boot
            )
        }

        precondition(state.recordFailure(
            nowWallTime: 3_204,
            nowUptime: 2_104,
            bootIdentifier: boot
        ) == .locked(remainingSeconds: 10_800))
    }

    private static func successfulPasswordResetsFailures() {
        var state = PasswordAttemptState()
        _ = state.recordFailure(nowWallTime: 4_000, nowUptime: 1_000, bootIdentifier: "boot-300")
        state.recordSuccess()
        precondition(state.failureTimestamps.isEmpty)
        precondition(state.decision(
            nowWallTime: 4_001,
            nowUptime: 1_001,
            bootIdentifier: "boot-300"
        ) == .allowed)
    }

    private static func failuresExpireOutsideRollingWindow() {
        var state = PasswordAttemptState()
        _ = state.recordFailure(nowWallTime: 5_000, nowUptime: 1_000, bootIdentifier: "boot-400")
        _ = state.recordFailure(nowWallTime: 6_801, nowUptime: 2_801, bootIdentifier: "boot-400")
        precondition(state.failureTimestamps.count == 1)
    }

    private static func applicationRestartDoesNotBypassLockout() {
        var state = lockedState(bootIdentifier: "boot-500")
        let encoded = try! JSONEncoder().encode(state)
        state = try! JSONDecoder().decode(PasswordAttemptState.self, from: encoded)
        precondition(state.decision(
            nowWallTime: 7_100,
            nowUptime: 2_100,
            bootIdentifier: "boot-500"
        ) == .locked(remainingSeconds: 10_704))
    }

    private static func wallClockRollbackDoesNotShortenSameBootLockout() {
        var state = lockedState(bootIdentifier: "boot-600")
        precondition(state.decision(
            nowWallTime: 6_500,
            nowUptime: 2_600,
            bootIdentifier: "boot-600"
        ) == .locked(remainingSeconds: 11_304))
    }

    private static func macRestartDoesNotBypassLockout() {
        var state = lockedState(bootIdentifier: "boot-550")
        precondition(state.decision(
            nowWallTime: 7_104,
            nowUptime: 10,
            bootIdentifier: "boot-551"
        ) == .locked(remainingSeconds: 10_700))
    }

    private static func lockoutExpiresAfterThreeHours() {
        var state = lockedState(bootIdentifier: "boot-650")
        precondition(state.decision(
            nowWallTime: 17_804,
            nowUptime: 12_804,
            bootIdentifier: "boot-650"
        ) == .allowed)
    }

    private static func firstInstallationDoesNotRunBootCleanup() {
        var tracker = BootCleanupTracker()
        precondition(!tracker.registerLaunch(currentBootIdentifier: "boot-700"))
    }

    private static func repeatedApplicationLaunchDoesNotRunBootCleanup() {
        var tracker = BootCleanupTracker(lastHandledBootIdentifier: "boot-800")
        precondition(!tracker.registerLaunch(currentBootIdentifier: "boot-800"))
    }

    private static func laterMacBootRunsCleanupOnce() {
        var tracker = BootCleanupTracker(lastHandledBootIdentifier: "boot-900")
        precondition(tracker.registerLaunch(currentBootIdentifier: "boot-901"))
        precondition(!tracker.registerLaunch(currentBootIdentifier: "boot-901"))
    }

    private static func bootCleanupTargetsOnlyProtectedNonRemoteApps() {
        let protected: Set<String> = ["com.acme.finance", "com.carriez.rustdesk"]
        let excluded: Set<String> = ["com.carriez.rustdesk"]

        precondition(BootCleanupPolicy.shouldTerminate(
            bundleIdentifier: "com.acme.finance",
            protectedBundleIdentifiers: protected,
            excludedBundleIdentifiers: excluded
        ))
        precondition(!BootCleanupPolicy.shouldTerminate(
            bundleIdentifier: "com.carriez.rustdesk",
            protectedBundleIdentifiers: protected,
            excludedBundleIdentifiers: excluded
        ))
        precondition(!BootCleanupPolicy.shouldTerminate(
            bundleIdentifier: "com.acme.notes",
            protectedBundleIdentifiers: protected,
            excludedBundleIdentifiers: excluded
        ))
    }

    private static func securityHistoryRetainsOnlyTwelveHours() {
        let now = Date(timeIntervalSince1970: 100_000)
        let expired = SecurityEventRecord(
            timestamp: now.addingTimeInterval(-(12 * 60 * 60) - 1),
            kind: .networkLoss,
            action: .locked,
            succeeded: true
        )
        let retained = SecurityEventRecord(
            timestamp: now.addingTimeInterval(-(12 * 60 * 60)),
            kind: .displayChange,
            action: .locked,
            succeeded: true
        )
        let future = SecurityEventRecord(
            timestamp: now.addingTimeInterval(1),
            kind: .sleep,
            action: .locked,
            succeeded: true
        )

        precondition(SecurityEventRetention.retained(
            [expired, retained, future],
            now: now
        ) == [retained])
    }

    private static func securityHistoryCapsAtTwoHundredRecords() {
        let now = Date(timeIntervalSince1970: 200_000)
        let records = (0..<220).map { index in
            SecurityEventRecord(
                timestamp: now.addingTimeInterval(TimeInterval(index - 220)),
                kind: .passwordFailure,
                action: .retryDelayed,
                succeeded: false
            )
        }
        let retained = SecurityEventRetention.retained(records, now: now)
        precondition(retained.count == 200)
        precondition(retained.first?.timestamp == records[20].timestamp)
        precondition(retained.last?.timestamp == records[219].timestamp)
    }

    private static func lockedState(bootIdentifier: String) -> PasswordAttemptState {
        var state = PasswordAttemptState()
        for index in 0..<5 {
            _ = state.recordFailure(
                nowWallTime: TimeInterval(7_000 + index),
                nowUptime: TimeInterval(2_000 + index),
                bootIdentifier: bootIdentifier
            )
        }
        return state
    }
}
