import AppKit
import SwiftUI

/// Manages overlay window lifecycle for protected applications.
///
/// An overlay must remain visible until a trusted unlock path succeeds. In
/// particular, it must never disappear merely because time has elapsed: doing
/// so would expose the protected application without authentication.
final class OverlayWindowService {
    static let shared = OverlayWindowService()

    private var overlayWindows: [LockOverlayWindow] = []
    private var currentApp: ProtectedApp?
    private var isPasswordInputEnabled = false
    private var isTouchIDMode = false
    private var focusRecoveryGeneration = 0
    private var didHideProtectedApplication = false

    /// Callback when overlay is dismissed after successful authentication.
    /// Passes the name of the unlocked app.
    var onUnlocked: ((String) -> Void)?

    private init() {
        // Observe screen configuration changes (connect/disconnect monitors)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Show the lock overlay for a protected app on all screens.
    func show(for app: ProtectedApp) {
        // Don't show duplicate overlays
        guard overlayWindows.isEmpty else { return }

        currentApp = app
        didHideProtectedApplication = false

        createOverlayWindows(for: app)

        NSLog("[MakLock] Overlay shown for: %@", app.name)
    }

    /// Hide all overlay windows after a trusted unlock action succeeds.
    func hide() {
        // Cancel any in-progress Touch ID evaluation
        AuthenticationService.shared.cancelAuthentication()

        // Mark the app as authenticated so it won't re-lock immediately
        if let app = currentApp {
            AppMonitorService.shared.markAuthenticated(app.bundleIdentifier)
        }

        overlayWindows.forEach { $0.close() }
        overlayWindows.removeAll()
        isPasswordInputEnabled = false
        isTouchIDMode = false
        focusRecoveryGeneration += 1
        PasswordFieldFocusCoordinator.shared.clear()

        // Activate the protected app now that overlays are gone.
        // Small delay ensures overlay panels and Touch ID dialog are fully dismissed
        // before attempting to bring the app forward.
        let shouldUnhideProtectedApplication = didHideProtectedApplication
        didHideProtectedApplication = false
        if let bundleID = currentApp?.bundleIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.activateProtectedApp(
                    bundleIdentifier: bundleID,
                    shouldUnhide: shouldUnhideProtectedApplication
                )
            }
        }

        currentApp = nil
        NSLog("[MakLock] Overlay dismissed")
    }

    /// Dismiss all overlays when protection is intentionally disabled or an app is closed.
    func dismissAll() {
        hide()
    }

    /// Whether an overlay is currently displayed.
    var isShowing: Bool {
        !overlayWindows.isEmpty
    }

    /// Bundle identifier of the currently locked app (if any).
    var currentBundleIdentifier: String? {
        currentApp?.bundleIdentifier
    }

    /// Display name of the currently locked app (if any).
    var currentAppName: String? {
        currentApp?.name
    }

    /// During Touch ID: pass through mouse events so system dialog gets interaction.
    /// After auth: restore mouse capture for overlay blocking.
    func setTouchIDMode(_ active: Bool) {
        isTouchIDMode = active
        if active {
            isPasswordInputEnabled = false
            focusRecoveryGeneration += 1
        }
        for window in overlayWindows {
            window.ignoresMouseEvents = active
        }
    }

    /// Enable key window status on overlay windows (needed for password input).
    func enableKeyboardInput() {
        isPasswordInputEnabled = true
        isTouchIDMode = false
        setTouchIDMode(false)
        hideProtectedApplicationForPasswordInput()
        for window in overlayWindows {
            window.setPasswordInputMode(true)
            window.orderFront(nil)
        }

        _ = makePasswordWindowKeyAndFocusField()
        DispatchQueue.main.async { [weak self] in
            _ = self?.makePasswordWindowKeyAndFocusField()
        }
    }

    func disableKeyboardInput() {
        isPasswordInputEnabled = false
        focusRecoveryGeneration += 1
        PasswordFieldFocusCoordinator.shared.clear()
        for window in overlayWindows {
            window.setPasswordInputMode(false)
        }
    }

    @discardableResult
    func restorePasswordFocusAfterSessionActivation(
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        guard isShowing, isPasswordInputEnabled, !isTouchIDMode else {
            return false
        }

        focusRecoveryGeneration += 1
        let generation = focusRecoveryGeneration
        let delays = [0.0, 0.5, 1.5, 3.0, 5.0]
        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      generation == self.focusRecoveryGeneration,
                      self.isShowing,
                      self.isPasswordInputEnabled,
                      !self.isTouchIDMode else {
                    return
                }
                let succeeded = self.makePasswordWindowKeyAndFocusField()

                if index == delays.count - 1 {
                    completion(succeeded)
                }
            }
        }
        return true
    }

    private func makePasswordWindowKeyAndFocusField() -> Bool {
        guard isShowing, isPasswordInputEnabled, !isTouchIDMode else { return false }

        let primaryWindow = primaryOverlayWindow()

        NSApp.activate(ignoringOtherApps: true)
        primaryWindow?.makeKeyAndOrderFront(nil)
        return PasswordFieldFocusCoordinator.shared.focusPrimaryField()
    }

    private func primaryOverlayWindow() -> LockOverlayWindow? {
        let primaryScreen = NSScreen.main ?? NSScreen.screens.first
        return overlayWindows.first { window in
            window.screen?.frame == primaryScreen?.frame
        } ?? overlayWindows.first
    }

    // MARK: - Screen Management

    @objc private func screensDidChange(_ notification: Notification) {
        guard !overlayWindows.isEmpty else { return }

        let screens = NSScreen.screens

        // Reposition existing windows to match current screens (don't recreate to avoid re-triggering Touch ID)
        for (index, window) in overlayWindows.enumerated() {
            if index < screens.count {
                window.reposition(to: screens[index])
            }
        }

        // Close excess windows if screens were removed
        while overlayWindows.count > screens.count {
            overlayWindows.removeLast().close()
        }

        // Add new windows for new screens (only blur, no Touch ID trigger)
        if let app = currentApp {
            for screenIndex in overlayWindows.count..<screens.count {
                let window = LockOverlayWindow(for: screens[screenIndex])
                let overlayView = LockOverlayView(
                    appName: app.name,
                    bundleIdentifier: app.bundleIdentifier,
                    isPrimary: false,
                    onDismiss: { [weak self] in
                        let name = self?.currentApp?.name ?? "app"
                        self?.hide()
                        self?.onUnlocked?(name)
                    }
                )
                window.contentView = NSHostingView(rootView: overlayView)
                window.orderFront(nil)
                overlayWindows.append(window)
            }
        }

        NSLog("[MakLock] Overlays repositioned for screen change (%d screens)", screens.count)
    }

    private func createOverlayWindows(for app: ProtectedApp) {
        let primaryScreen = NSScreen.main ?? NSScreen.screens.first

        for screen in NSScreen.screens {
            let window = LockOverlayWindow(for: screen)
            let isPrimary = (screen == primaryScreen)

            let overlayView = LockOverlayView(
                appName: app.name,
                bundleIdentifier: app.bundleIdentifier,
                isPrimary: isPrimary,
                onDismiss: { [weak self] in
                    let name = self?.currentApp?.name ?? "app"
                    self?.hide()
                    self?.onUnlocked?(name)
                }
            )

            window.contentView = NSHostingView(rootView: overlayView)
            // Don't make key or activate — system Touch ID dialog needs focus
            window.orderFront(nil)
            overlayWindows.append(window)
        }

        if Defaults.shared.prefersPasswordUnlock {
            enableKeyboardInput()
        }
    }

    // MARK: - App Window Management

    /// Bring the protected app to the foreground after successful auth.
    /// Only activates if the app is already running — never launches a closed app.
    private func hideProtectedApplicationForPasswordInput() {
        guard !didHideProtectedApplication,
              let bundleIdentifier = currentApp?.bundleIdentifier,
              let application = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == bundleIdentifier
              }),
              !application.isHidden else {
            return
        }

        didHideProtectedApplication = application.hide()
        if didHideProtectedApplication {
            NSLog("[MakLock] Protected app hidden while password overlay is active")
        }
    }

    private func activateProtectedApp(
        bundleIdentifier: String,
        shouldUnhide: Bool
    ) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            NSLog("[MakLock] App not running, skipping activation: %@", bundleIdentifier)
            return
        }

        if shouldUnhide {
            app.unhide()
        }
        app.activate()
        NSLog("[MakLock] Activated app: %@", bundleIdentifier)
    }

}
