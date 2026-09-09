import AppKit

final class SessionFocusService {
    static let shared = SessionFocusService()

    private var isObserving = false
    private var pendingRecovery: DispatchWorkItem?

    private init() {}

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(handleSessionAvailable),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleSessionAvailable),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleSessionAvailable),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleApplicationActivation),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func handleSessionAvailable(_ notification: Notification) {
        scheduleRecovery(after: 0.1)
    }

    @objc private func handleApplicationActivation(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.bundleIdentifier != "com.makmak.MakLock" else {
            return
        }

        scheduleRecovery(after: 0)
    }

    private func scheduleRecovery(after delay: TimeInterval) {
        pendingRecovery?.cancel()

        let workItem = DispatchWorkItem {
            guard OverlayWindowService.shared.restorePasswordFocusAfterSessionActivation(completion: { succeeded in
                SecurityEventStore.shared.record(
                    kind: .sessionFocusRecovery,
                    action: .focusRestored,
                    succeeded: succeeded
                )
            }) else {
                return
            }
        }
        pendingRecovery = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
