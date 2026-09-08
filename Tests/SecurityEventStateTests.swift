import Foundation

@main
enum SecurityEventStateTests {
    static func main() {
        networkOutageRequiresFullGracePeriod()
        networkRecoveryResetsOutage()
        networkOutageTriggersOnlyOnce()
        trustedDisplayDoesNotTrigger()
        missingTrustedBaselineDoesNotTrigger()
        removingTrustedDisplayTriggersImmediately()
        changedDisplayTriggersImmediatelyAndOnce()
        duplicateTrustedFingerprintTriggersImmediately()
        secondUnknownDisplayChangeTriggersAgain()
        returningToTrustedDisplayResetsMismatch()
        print("Security event state tests passed")
    }

    private static func networkOutageRequiresFullGracePeriod() {
        var tracker = NetworkOutageTracker()
        precondition(!tracker.observe(isOnline: false, now: 100, graceSeconds: 60))
        precondition(!tracker.observe(isOnline: false, now: 159, graceSeconds: 60))
        precondition(tracker.observe(isOnline: false, now: 160, graceSeconds: 60))
    }

    private static func networkRecoveryResetsOutage() {
        var tracker = NetworkOutageTracker()
        precondition(!tracker.observe(isOnline: false, now: 200, graceSeconds: 60))
        precondition(!tracker.observe(isOnline: true, now: 230, graceSeconds: 60))
        precondition(!tracker.observe(isOnline: false, now: 260, graceSeconds: 60))
        precondition(!tracker.observe(isOnline: false, now: 319, graceSeconds: 60))
        precondition(tracker.observe(isOnline: false, now: 320, graceSeconds: 60))
    }

    private static func networkOutageTriggersOnlyOnce() {
        var tracker = NetworkOutageTracker()
        precondition(!tracker.observe(isOnline: false, now: 400, graceSeconds: 60))
        precondition(tracker.observe(isOnline: false, now: 460, graceSeconds: 60))
        precondition(!tracker.observe(isOnline: false, now: 520, graceSeconds: 60))
    }

    private static func trustedDisplayDoesNotTrigger() {
        var tracker = DisplayTrustTracker()
        let trusted = ["6821:14400:1649256262:0"]
        precondition(!tracker.observe(current: trusted, trusted: trusted))
    }

    private static func missingTrustedBaselineDoesNotTrigger() {
        var tracker = DisplayTrustTracker()
        let current = ["6821:14400:1649256262:0"]
        precondition(!tracker.observe(current: current, trusted: []))
    }

    private static func removingTrustedDisplayTriggersImmediately() {
        var tracker = DisplayTrustTracker()
        let trusted = ["6821:14400:1649256262:0"]
        precondition(tracker.observe(current: [], trusted: trusted))
    }

    private static func changedDisplayTriggersImmediatelyAndOnce() {
        var tracker = DisplayTrustTracker()
        let trusted = ["6821:14400:1649256262:0"]
        let changed = ["1552:22136:99887766:0"]
        precondition(tracker.observe(current: changed, trusted: trusted))
        precondition(!tracker.observe(current: changed, trusted: trusted))
    }

    private static func duplicateTrustedFingerprintTriggersImmediately() {
        var tracker = DisplayTrustTracker()
        let fingerprint = "6821:14400:1649256262:0"
        precondition(tracker.observe(
            current: [fingerprint, fingerprint],
            trusted: [fingerprint]
        ))
    }

    private static func secondUnknownDisplayChangeTriggersAgain() {
        var tracker = DisplayTrustTracker()
        let trusted = ["6821:14400:1649256262:0"]
        let firstChanged = ["1552:22136:99887766:0"]
        let secondChanged = ["4268:9029:55443322:0"]
        precondition(tracker.observe(current: firstChanged, trusted: trusted))
        precondition(tracker.observe(current: secondChanged, trusted: trusted))
    }

    private static func returningToTrustedDisplayResetsMismatch() {
        var tracker = DisplayTrustTracker()
        let trusted = ["6821:14400:1649256262:0"]
        let changed = ["1552:22136:99887766:0"]
        precondition(tracker.observe(current: changed, trusted: trusted))
        precondition(!tracker.observe(current: trusted, trusted: trusted))
        precondition(tracker.observe(current: changed, trusted: trusted))
    }
}
