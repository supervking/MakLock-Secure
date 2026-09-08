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
    }

    @objc private func handleSessionAvailable(_ notification: Notification) {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
}
