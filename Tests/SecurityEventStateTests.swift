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
        displayConfigurationCountsUnexpectedAndMissingDisplays()
        displayConfigurationCountsMissingTrustedDisplays()
        structuralTamperSignalsAreCoalescedUntilEvaluation()
        consumingStructuralTamperResetsTheLatch()
        potentialDisplayChangeShowsEvaluatingShield()
        trustedEvaluationDismissesTransientShield()
        rapidDisplayConnectionRemainsAfterTrustedEvaluation()
        repeatedStructuralTamperRefreshesConfirmedIncident()
        unconfiguredBaselineDismissesTransientShield()
        confirmedIntrusionRemainsAfterDisplayRemoval()
        connectedUntrustedDisplayCannotBeAuthenticatedAway()
        restoredDisplayConfigurationCanBeAuthenticated()
        repeatedDisplayCallbacksDoNotRestartConfirmedIncident()
        thresholdTriggersOnlyOnceUntilRecovery()
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

    private static func displayConfigurationCountsUnexpectedAndMissingDisplays() {
        let status = DisplayConfigurationStatus(
            currentFingerprints: ["trusted-display", "unknown-display", "unknown-display"],
            trustedFingerprints: ["trusted-display"]
        )

        precondition(!status.isTrusted)
        precondition(status.unexpectedDisplayCount == 2)
        precondition(status.missingTrustedDisplayCount == 0)
    }

    private static func displayConfigurationCountsMissingTrustedDisplays() {
        let status = DisplayConfigurationStatus(
            currentFingerprints: ["trusted-display"],
            trustedFingerprints: ["trusted-display", "trusted-secondary"]
        )

        precondition(!status.isTrusted)
        precondition(status.unexpectedDisplayCount == 0)
        precondition(status.missingTrustedDisplayCount == 1)
    }

    private static func structuralTamperSignalsAreCoalescedUntilEvaluation() {
        var latch = DisplayStructuralTamperLatch()

        precondition(latch.observeStructuralChange())
        precondition(!latch.observeStructuralChange())
        precondition(latch.hasPendingTamper)
    }

    private static func consumingStructuralTamperResetsTheLatch() {
        var latch = DisplayStructuralTamperLatch()
        _ = latch.observeStructuralChange()

        precondition(latch.consume())
        precondition(!latch.consume())
        precondition(!latch.hasPendingTamper)
    }

    private static func potentialDisplayChangeShowsEvaluatingShield() {
        var state = DisplayIntrusionAlertState()

        precondition(state.beginPotentialChange() == .showEvaluatingShield)
        precondition(state.phase == .evaluating)
    }

    private static func trustedEvaluationDismissesTransientShield() {
        var state = DisplayIntrusionAlertState()
        _ = state.beginPotentialChange()

        precondition(state.observe(configuration: trustedDisplayStatus()) == .dismissTransientShield)
        precondition(state.phase == .hidden)
    }

    private static func rapidDisplayConnectionRemainsAfterTrustedEvaluation() {
        var state = DisplayIntrusionAlertState()
        _ = state.beginPotentialChange()

        precondition(state.confirmStructuralTamper() == .confirmIntrusion)
        precondition(state.observe(configuration: trustedDisplayStatus()) == .awaitAuthentication)
        precondition(state.phase == .intrusion)
        precondition(state.authenticate(configuration: trustedDisplayStatus()))
        precondition(state.phase == .hidden)
    }

    private static func repeatedStructuralTamperRefreshesConfirmedIncident() {
        var state = DisplayIntrusionAlertState()

        precondition(state.confirmStructuralTamper() == .confirmIntrusion)
        precondition(state.confirmStructuralTamper() == .refreshIntrusion)
        precondition(state.phase == .intrusion)
    }

    private static func unconfiguredBaselineDismissesTransientShield() {
        var state = DisplayIntrusionAlertState()
        _ = state.beginPotentialChange()
        let unconfigured = DisplayConfigurationStatus(
            currentFingerprints: ["current-display"],
            trustedFingerprints: []
        )

        precondition(state.observe(configuration: unconfigured) == .dismissTransientShield)
        precondition(state.phase == .hidden)
    }

    private static func confirmedIntrusionRemainsAfterDisplayRemoval() {
        var state = DisplayIntrusionAlertState()
        _ = state.beginPotentialChange()
        _ = state.observe(configuration: untrustedDisplayStatus())

        precondition(state.observe(configuration: trustedDisplayStatus()) == .awaitAuthentication)
        precondition(state.phase == .intrusion)
    }

    private static func connectedUntrustedDisplayCannotBeAuthenticatedAway() {
        var state = DisplayIntrusionAlertState()
        _ = state.observe(configuration: untrustedDisplayStatus())

        precondition(!state.authenticate(configuration: untrustedDisplayStatus()))
        precondition(state.phase == .intrusion)
    }

    private static func restoredDisplayConfigurationCanBeAuthenticated() {
        var state = DisplayIntrusionAlertState()
        _ = state.observe(configuration: untrustedDisplayStatus())
        _ = state.observe(configuration: trustedDisplayStatus())

        precondition(state.authenticate(configuration: trustedDisplayStatus()))
        precondition(state.phase == .hidden)
    }

    private static func repeatedDisplayCallbacksDoNotRestartConfirmedIncident() {
        var state = DisplayIntrusionAlertState()
        _ = state.observe(configuration: untrustedDisplayStatus())

        precondition(state.beginPotentialChange() == .none)
        precondition(state.observe(configuration: untrustedDisplayStatus()) == .refreshIntrusion)
        precondition(state.phase == .intrusion)
    }

    private static func trustedDisplayStatus() -> DisplayConfigurationStatus {
        DisplayConfigurationStatus(
            currentFingerprints: ["trusted-display"],
            trustedFingerprints: ["trusted-display"]
        )
    }

    private static func untrustedDisplayStatus() -> DisplayConfigurationStatus {
        DisplayConfigurationStatus(
            currentFingerprints: ["trusted-display", "unknown-display"],
            trustedFingerprints: ["trusted-display"]
        )
    }

    private static func thresholdTriggersOnlyOnceUntilRecovery() {
        var latch = ThresholdTriggerLatch()
        precondition(!latch.observe(hasReachedThreshold: false))
        precondition(latch.observe(hasReachedThreshold: true))
        precondition(!latch.observe(hasReachedThreshold: true))
        precondition(!latch.observe(hasReachedThreshold: false))
        precondition(latch.observe(hasReachedThreshold: true))
    }
}
