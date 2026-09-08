import AppKit
import Combine

final class BootCleanupService {
    static let shared = BootCleanupService()

    private let cleanupWindowSeconds: TimeInterval = 90
    private let gracefulQuitSeconds: TimeInterval = 3
    private var isCleanupWindowActive = false
    private var processedProcessIdentifiers: Set<pid_t> = []
    private var launchCancellable: AnyCancellable?

    private init() {}

    func start() {
        var tracker = BootCleanupTracker(
            lastHandledBootIdentifier: Defaults.shared.lastHandledBootIdentifier
        )
        let currentBootIdentifier = SystemBootIdentity.current
        let shouldRunCleanup = tracker.registerLaunch(
            currentBootIdentifier: currentBootIdentifier
        )
        Defaults.shared.lastHandledBootIdentifier = tracker.lastHandledBootIdentifier

        guard Defaults.shared.quitProtectedAppsAfterRestart, shouldRunCleanup else {
            return
        }

        isCleanupWindowActive = true
        processedProcessIdentifiers.removeAll()

        launchCancellable = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .compactMap {
                $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            }
            .sink { [weak self] application in
                self?.handleApplication(application)
            }

        for application in NSWorkspace.shared.runningApplications {
            handleApplication(application)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + cleanupWindowSeconds) { [weak self] in
            self?.finishCleanupWindow()
        }

        NSLog("[MakLock] Restart cleanup window started")
    }

    private func handleApplication(_ application: NSRunningApplication) {
        let protectedBundleIdentifiers = Set(
            Defaults.shared.protectedApps
                .filter(\.isEnabled)
                .map(\.bundleIdentifier)
        )

        guard isCleanupWindowActive,
              !processedProcessIdentifiers.contains(application.processIdentifier),
              let bundleIdentifier = application.bundleIdentifier,
              BootCleanupPolicy.shouldTerminate(
                  bundleIdentifier: bundleIdentifier,
                  protectedBundleIdentifiers: protectedBundleIdentifiers,
                  excludedBundleIdentifiers: SafetyManager.systemBlacklist
              ) else {
            return
        }

        processedProcessIdentifiers.insert(application.processIdentifier)
        _ = application.terminate()

        DispatchQueue.main.asyncAfter(deadline: .now() + gracefulQuitSeconds) {
            if application.isTerminated {
                SecurityEventStore.shared.record(
                    kind: .restartCleanup,
                    action: .gracefulQuit,
                    succeeded: true,
                    affectedCount: 1
                )
                return
            }

            let forced = application.forceTerminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SecurityEventStore.shared.record(
                    kind: .restartCleanup,
                    action: .forcedQuit,
                    succeeded: forced && application.isTerminated,
                    affectedCount: 1
                )
            }
        }
    }

    private func finishCleanupWindow() {
        guard isCleanupWindowActive else { return }
        isCleanupWindowActive = false
        launchCancellable = nil
        processedProcessIdentifiers.removeAll()
        NSLog("[MakLock] Restart cleanup window finished")
    }
}
