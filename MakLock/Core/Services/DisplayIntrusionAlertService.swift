import AppKit
import Combine
import SwiftUI

final class DisplayIntrusionAlertService {
    static let shared = DisplayIntrusionAlertService()

    private let model = DisplayIntrusionAlertModel()
    private var state = DisplayIntrusionAlertState()
    private var windows: [DisplayIntrusionAlertWindow] = []
    private var focusRecoveryGeneration = 0

    var onAlertStateChanged: ((Bool) -> Void)?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    var isShowing: Bool {
        !windows.isEmpty
    }

    var isConfirmedIntrusion: Bool {
        state.phase == .intrusion
    }

    func beginPotentialDisplayChange() {
        guard Defaults.shared.appSettings.isProtectionEnabled,
              Defaults.shared.lockOnDisplayChange,
              state.beginPotentialChange() == .showEvaluatingShield else {
            return
        }

        model.phase = .evaluating
        model.configurationIsTrusted = false
        model.detectedRemovedDisplayTamper = false
        model.errorMessage = nil
        refreshWindows()
        onAlertStateChanged?(true)
        NSLog("[MakLock] Display privacy shield shown while configuration is evaluated")
    }

    func observe(configuration status: DisplayConfigurationStatus) {
        guard Defaults.shared.appSettings.isProtectionEnabled,
              Defaults.shared.lockOnDisplayChange else {
            dismissForProtectionDisabled()
            return
        }

        updateModel(configuration: status)
        if !status.isTrusted {
            model.detectedRemovedDisplayTamper = false
        }

        let transition = state.observe(configuration: status)
        model.phase = state.phase

        switch transition {
        case .none:
            break
        case .showEvaluatingShield:
            refreshWindows()
            onAlertStateChanged?(true)
        case .dismissTransientShield:
            closeWindows()
            onAlertStateChanged?(false)
            NSLog("[MakLock] Display privacy shield dismissed after trusted evaluation")
        case .confirmIntrusion:
            model.errorMessage = nil
            refreshWindows()
            SecurityEventStore.shared.record(
                kind: .displayChange,
                action: .alertShown,
                succeeded: true,
                numericDetail: status.currentFingerprints.count
            )
            onAlertStateChanged?(true)
            NSLog("[MakLock] Unauthorized display alert confirmed")
        case .refreshIntrusion:
            refreshWindows()
            onAlertStateChanged?(true)
        case .awaitAuthentication:
            refreshWindowInputModes()
            focusPasswordFieldSoon()
            onAlertStateChanged?(true)
            NSLog("[MakLock] Trusted display setup restored; alert awaits authentication")
        }
    }

    func confirmHistoricalTamper(configuration status: DisplayConfigurationStatus) {
        guard Defaults.shared.appSettings.isProtectionEnabled,
              Defaults.shared.lockOnDisplayChange else {
            dismissForProtectionDisabled()
            return
        }

        updateModel(configuration: status)
        let transition = state.confirmStructuralTamper()
        model.phase = state.phase
        model.detectedRemovedDisplayTamper = true
        model.errorMessage = nil
        model.restartErrorMessage = nil

        switch transition {
        case .confirmIntrusion:
            SecurityEventStore.shared.record(
                kind: .displayChange,
                action: .tamperDetected,
                succeeded: true,
                numericDetail: status.currentFingerprints.count
            )
        case .refreshIntrusion:
            break
        case .none,
             .showEvaluatingShield,
             .dismissTransientShield,
             .awaitAuthentication:
            assertionFailure("Unexpected display tamper transition")
        }

        refreshWindows()
        onAlertStateChanged?(true)
        NSLog("[MakLock] Historical display tamper alert confirmed")
    }

    func dismissForProtectionDisabled() {
        guard isShowing || state.phase != .hidden else { return }
        state.reset()
        model.phase = .hidden
        model.errorMessage = nil
        model.detectedRemovedDisplayTamper = false
        closeWindows()
        onAlertStateChanged?(false)
    }

    func dismissForEmergencyRecovery() {
        guard isShowing || state.phase != .hidden else { return }
        state.reset()
        model.phase = .hidden
        model.errorMessage = nil
        model.detectedRemovedDisplayTamper = false
        model.restartErrorMessage = nil
        model.isRestarting = false
        closeWindows()
        onAlertStateChanged?(false)
        NSLog("[MakLock] Display alert suppressed by emergency restart recovery")
    }

    func requestSystemRestart() {
        guard state.phase == .intrusion, !model.isRestarting else { return }

        let status = DisplaySecurityMonitor.currentConfigurationStatus()
        guard status.isConfigured, !status.isTrusted else {
            model.restartErrorMessage = String(
                localized: "Restart is available only while an unauthorized display alert is active."
            )
            return
        }

        model.isRestarting = true
        model.restartErrorMessage = nil
        let recoveryService = EmergencyRestartRecoveryService.shared
        let recoveryWasEnabled = recoveryService.isRecoveryEnabled
        let recoveryWasPrepared = recoveryService.prepareAlertRestart(
            configuration: status
        )
        guard !recoveryWasEnabled || recoveryWasPrepared else {
            model.isRestarting = false
            model.restartErrorMessage = String(
                localized: "Secure restart recovery state could not be saved. Contact the computer owner."
            )
            return
        }
        let requestedFromBootIdentifier = SystemBootIdentity.current
        setRestartRequestMode(true)

        SystemRestartService.shared.requestRestart { [weak self] accepted in
            guard let self else { return }
            guard accepted else {
                EmergencyRestartRecoveryService.shared.cancelPendingRestart()
                self.model.isRestarting = false
                self.model.restartErrorMessage = String(
                    localized: "The restart request failed. Contact the computer owner."
                )
                self.setRestartRequestMode(false)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                guard let self,
                      self.model.isRestarting,
                      SystemBootIdentity.current == requestedFromBootIdentifier else {
                    return
                }
                EmergencyRestartRecoveryService.shared.cancelPendingRestart()
                self.model.isRestarting = false
                self.model.restartErrorMessage = String(
                    localized: "The restart did not begin. Contact the computer owner."
                )
                self.setRestartRequestMode(false)
            }
        }
    }

    func authenticateWithPassword(_ password: String) -> AuthResult {
        let status = DisplaySecurityMonitor.currentConfigurationStatus()
        guard status.isTrusted else {
            return .failure(.systemError(String(
                localized: "Display configuration is still untrusted. Disconnect the unauthorized display first."
            )))
        }

        let result = AuthenticationService.shared.authenticateWithPassword(password)
        if case .success = result {
            completeAuthentication()
        }
        return result
    }

    func authenticateWithSystemPassword() {
        guard !AuthenticationService.shared.isAuthenticating,
              !model.isSystemAuthenticationInProgress else { return }
        let status = DisplaySecurityMonitor.currentConfigurationStatus()
        guard status.isTrusted else {
            model.errorMessage = String(
                localized: "Display configuration is still untrusted. Disconnect the unauthorized display first."
            )
            return
        }

        model.isSystemAuthenticationInProgress = true
        setSystemAuthenticationMode(true)
        AuthenticationService.shared.authenticateWithSystemFallback(
            reason: String(localized: "Restore desktop after unauthorized display alert")
        ) { [weak self] result in
            guard let self else { return }
            self.model.isSystemAuthenticationInProgress = false
            self.setSystemAuthenticationMode(false)

            switch result {
            case .success:
                self.completeAuthentication()
            case .failure(let error):
                self.model.errorMessage = error.localizedDescription
            case .cancelled:
                self.focusPasswordFieldSoon()
            }
        }
    }

    @discardableResult
    func focusPasswordField() -> Bool {
        guard isShowing,
              !AuthenticationService.shared.isAuthenticating,
              !model.isSystemAuthenticationInProgress,
              state.phase == .intrusion,
              model.configurationIsTrusted,
              KeychainManager.shared.hasPassword(),
              let inputWindow = authenticationWindow() else {
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        inputWindow.makeKeyAndOrderFront(nil)
        return DisplayAlertFocusCoordinator.shared.focusField()
    }

    @discardableResult
    func restoreFocusAfterSessionActivation(
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        guard isShowing, state.phase == .intrusion,
              !AuthenticationService.shared.isAuthenticating,
              !model.isSystemAuthenticationInProgress else { return false }

        focusRecoveryGeneration += 1
        let generation = focusRecoveryGeneration
        let delays = [0.0, 0.5, 1.5, 3.0, 5.0]
        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      generation == self.focusRecoveryGeneration,
                      !AuthenticationService.shared.isAuthenticating,
                      !self.model.isSystemAuthenticationInProgress,
                      self.isShowing,
                      self.state.phase == .intrusion else {
                    return
                }

                let succeeded: Bool
                if self.model.configurationIsTrusted && KeychainManager.shared.hasPassword() {
                    succeeded = self.focusPasswordField()
                } else {
                    self.bringAlertWindowsForward()
                    succeeded = true
                }

                if index == delays.count - 1 {
                    completion(succeeded)
                }
            }
        }
        return true
    }

    private func completeAuthentication() {
        let status = DisplaySecurityMonitor.currentConfigurationStatus()
        updateModel(configuration: status)
        guard state.authenticate(configuration: status) else {
            model.errorMessage = String(
                localized: "Display configuration is still untrusted. Disconnect the unauthorized display first."
            )
            refreshWindows()
            return
        }

        SecurityEventStore.shared.record(
            kind: .displayChange,
            action: .alertDismissed,
            succeeded: true,
            numericDetail: status.currentFingerprints.count
        )
        model.phase = .hidden
        model.errorMessage = nil
        model.detectedRemovedDisplayTamper = false
        closeWindows()
        onAlertStateChanged?(false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            _ = OverlayWindowService.shared.restorePasswordFocusAfterSessionActivation { _ in }
        }
    }

    private func updateModel(configuration status: DisplayConfigurationStatus) {
        model.currentDisplayCount = status.currentFingerprints.count
        model.unexpectedDisplayCount = status.unexpectedDisplayCount
        model.missingTrustedDisplayCount = status.missingTrustedDisplayCount
        model.configurationIsTrusted = status.isTrusted
    }

    private func refreshWindows() {
        closeWindows(resetFocusGeneration: false)

        let authenticationScreen = preferredAuthenticationScreen()
        for screen in NSScreen.screens {
            let allowsAuthentication = screen == authenticationScreen
            let window = DisplayIntrusionAlertWindow(for: screen)
            window.setAllowsKeyStatus(allowsAuthentication)
            window.contentView = NSHostingView(rootView: DisplayIntrusionAlertView(
                model: model,
                allowsAuthentication: allowsAuthentication,
                presentedDisplayID: DisplaySecurityMonitor.descriptor(for: screen)?.displayID
            ))
            window.orderFront(nil)
            windows.append(window)
        }

        bringAlertWindowsForward()
        if model.phase == .intrusion && model.configurationIsTrusted {
            focusPasswordFieldSoon()
        }
    }

    private func refreshWindowInputModes() {
        let authenticationScreen = preferredAuthenticationScreen()
        for window in windows {
            window.setAllowsKeyStatus(window.screen == authenticationScreen)
            window.orderFront(nil)
        }
        bringAlertWindowsForward()
    }

    private func preferredAuthenticationScreen() -> NSScreen? {
        let trustedFingerprints = Set(Defaults.shared.trustedDisplayFingerprints)
        let trustedScreens = NSScreen.screens.filter { screen in
            guard let descriptor = DisplaySecurityMonitor.descriptor(for: screen) else {
                return false
            }
            return trustedFingerprints.contains(descriptor.fingerprint)
        }

        if let mainScreen = NSScreen.main, trustedScreens.contains(mainScreen) {
            return mainScreen
        }
        return trustedScreens.first ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func authenticationWindow() -> DisplayIntrusionAlertWindow? {
        let targetScreen = preferredAuthenticationScreen()
        return windows.first { $0.screen == targetScreen } ?? windows.first
    }

    private func focusPasswordFieldSoon() {
        DispatchQueue.main.async { [weak self] in
            _ = self?.focusPasswordField()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            _ = self?.focusPasswordField()
        }
    }

    private func bringAlertWindowsForward() {
        guard !AuthenticationService.shared.isAuthenticating,
              !model.isSystemAuthenticationInProgress else { return }
        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.orderFrontRegardless() }
        authenticationWindow()?.makeKeyAndOrderFront(nil)
    }

    private func setSystemAuthenticationMode(_ active: Bool) {
        windows.forEach { $0.setSystemAuthenticationMode(active) }
        if !active {
            bringAlertWindowsForward()
        }
    }

    func setPasswordRecoveryAuthenticationMode(_ active: Bool) {
        model.isSystemAuthenticationInProgress = active
        focusRecoveryGeneration += 1
        setSystemAuthenticationMode(active)
        if !active, isShowing {
            focusPasswordFieldSoon()
        }
    }

    private func setRestartRequestMode(_ active: Bool) {
        windows.forEach { $0.setRestartRequestMode(active) }
        if !active {
            bringAlertWindowsForward()
        }
    }

    private func closeWindows(resetFocusGeneration: Bool = true) {
        if resetFocusGeneration {
            focusRecoveryGeneration += 1
        }
        DisplayAlertFocusCoordinator.shared.clear()
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    @objc private func screensDidChange(_ notification: Notification) {
        guard isShowing else { return }
        refreshWindows()
    }
}

private final class DisplayIntrusionAlertModel: ObservableObject {
    @Published var phase: DisplayIntrusionAlertPhase = .hidden
    @Published var configurationIsTrusted = false
    @Published var currentDisplayCount = 0
    @Published var unexpectedDisplayCount = 0
    @Published var missingTrustedDisplayCount = 0
    @Published var errorMessage: String?
    @Published var isSystemAuthenticationInProgress = false
    @Published var isRestarting = false
    @Published var restartErrorMessage: String?
    @Published var detectedRemovedDisplayTamper = false
}

private final class DisplayIntrusionAlertWindow: NSPanel {
    private var allowsKeyStatus = false

    init(for screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = Self.alertLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = true
        backgroundColor = .systemRed
        ignoresMouseEvents = false
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { allowsKeyStatus }
    override var canBecomeMain: Bool { false }

    func setAllowsKeyStatus(_ allowed: Bool) {
        allowsKeyStatus = allowed
        becomesKeyOnlyIfNeeded = !allowed
    }

    func setSystemAuthenticationMode(_ active: Bool) {
        level = active ? .screenSaver : Self.alertLevel
        ignoresMouseEvents = active
    }

    func setRestartRequestMode(_ active: Bool) {
        level = active ? .screenSaver : Self.alertLevel
        ignoresMouseEvents = false
    }

    private static let alertLevel = NSWindow.Level(
        rawValue: NSWindow.Level.screenSaver.rawValue + 1
    )
}

private struct DisplayIntrusionAlertView: View {
    @ObservedObject var model: DisplayIntrusionAlertModel
    let allowsAuthentication: Bool
    let presentedDisplayID: CGDirectDisplayID?
    @State private var isPasswordRecoveryActive = false

    var body: some View {
        ZStack {
            Color(red: 0.62, green: 0.02, blue: 0.04)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 84, weight: .bold))
                    .foregroundColor(.white)

                Text("Security Alert")
                    .font(.system(size: 44, weight: .black))
                    .foregroundColor(.white)

                if model.phase == .evaluating {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Checking display security...")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                } else {
                    Text(alertTitle)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)

                    Text(primaryWarning)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Protected apps are locked and desktop content is hidden.")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))

                    Text(displaySummary)
                        .font(.headline.monospacedDigit())
                        .foregroundColor(.white.opacity(0.85))

                    authenticationContent
                    restartControl
                }
            }
            .multilineTextAlignment(.center)
            .padding(48)
            .frame(maxWidth: 780)
        }
    }

    @ViewBuilder
    private var restartControl: some View {
        if model.phase == .intrusion, !model.configurationIsTrusted {
            VStack(spacing: 10) {
                Button(model.isRestarting ? "Restarting..." : "Restart Mac") {
                    showRestartConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundColor(.red)
                .disabled(model.isRestarting)

                if let restartErrorMessage = model.restartErrorMessage {
                    Text(restartErrorMessage)
                        .font(.headline)
                        .foregroundColor(.yellow)
                }
            }
            .padding(.top, 10)
            .alert("Restart Mac?", isPresented: $showRestartConfirmation) {
                Button("Restart", role: .destructive) {
                    DisplayIntrusionAlertService.shared.requestSystemRestart()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Restarting closes all applications. Unsaved work may be lost.")
            }
        }
    }

    @ViewBuilder
    private var authenticationContent: some View {
        if allowsAuthentication {
            if model.configurationIsTrusted {
                VStack(spacing: 14) {
                    if !isPasswordRecoveryActive {
                        Text("Display connection restored. Enter your MakLock password to restore the desktop.")
                            .font(.headline)
                            .foregroundColor(.white)

                        if KeychainManager.shared.hasPassword() {
                            DisplayIntrusionPasswordView(model: model)
                        } else {
                            Button("Authenticate with Mac Login Password") {
                                DisplayIntrusionAlertService.shared.authenticateWithSystemPassword()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundColor(.red)
                            .disabled(model.isSystemAuthenticationInProgress)
                        }
                    }

                    PasswordRecoveryControls(
                        presentedDisplayID: presentedDisplayID,
                        onAuthenticationModeChanged: { active in
                            DisplayIntrusionAlertService.shared
                                .setPasswordRecoveryAuthenticationMode(active)
                        },
                        onFlowActiveChanged: { active in
                            isPasswordRecoveryActive = active
                            if !active {
                                DispatchQueue.main.async {
                                    _ = DisplayIntrusionAlertService.shared.focusPasswordField()
                                }
                            }
                        }
                    )
                    .id("display-password-recovery-controls")
                }
                .padding(.top, 8)
            } else {
                Text("Disconnect the unauthorized display before entering your password.")
                    .font(.title3.bold())
                    .foregroundColor(.yellow)
                    .padding(.top, 8)
            }
        } else {
            Text("Password entry is available only on the trusted display.")
                .font(.headline)
                .foregroundColor(.white.opacity(0.85))
                .padding(.top, 8)
        }
    }

    private var displaySummary: String {
        String.localizedStringWithFormat(
            NSLocalizedString(
                "Displays: %lld · unauthorized: %lld · missing trusted: %lld",
                comment: "Unauthorized display alert count summary"
            ),
            Int64(model.currentDisplayCount),
            Int64(model.unexpectedDisplayCount),
            Int64(model.missingTrustedDisplayCount)
        )
    }

    private var primaryWarning: LocalizedStringKey {
        if model.detectedRemovedDisplayTamper {
            return "An unauthorized display was connected and has been removed. Owner confirmation is required."
        }
        return model.unexpectedDisplayCount > 0
            ? "Illegal display connected. Disconnect it immediately."
            : "The trusted display setup changed. Check the display connection immediately."
    }

    private var alertTitle: LocalizedStringKey {
        model.detectedRemovedDisplayTamper
            ? "Unauthorized Display Connection Recorded"
            : "Unauthorized Display Detected"
    }

    @State private var showRestartConfirmation = false
}

private struct DisplayIntrusionPasswordView: View {
    @ObservedObject var model: DisplayIntrusionAlertModel
    @State private var password = ""
    @State private var passwordAccessDecision: PasswordAccessDecision = .allowed

    private let accessRefreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            DisplayAlertSecureField(
                text: $password,
                placeholder: String(localized: "MakLock Password"),
                isEnabled: !isPasswordInputBlocked,
                onSubmit: verifyPassword,
                onInteraction: {
                    _ = DisplayIntrusionAlertService.shared.focusPasswordField()
                }
            )
            .frame(width: 300, height: 28)

            if let visibleErrorMessage {
                Text(visibleErrorMessage)
                    .font(.headline)
                    .foregroundColor(.yellow)
            }

            Button("Confirm and Restore Desktop") {
                verifyPassword()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundColor(.red)
            .disabled(isPasswordInputBlocked)
        }
        .onAppear {
            refreshPasswordAccessDecision()
            _ = DisplayIntrusionAlertService.shared.focusPasswordField()
        }
        .onReceive(accessRefreshTimer) { _ in
            refreshPasswordAccessDecision()
        }
    }

    private func verifyPassword() {
        refreshPasswordAccessDecision()
        guard !isPasswordInputBlocked else { return }

        let result = DisplayIntrusionAlertService.shared.authenticateWithPassword(password)
        switch result {
        case .success:
            password = ""
        case .failure(let error):
            model.errorMessage = error.localizedDescription
            password = ""
            refreshPasswordAccessDecision()
            _ = DisplayIntrusionAlertService.shared.focusPasswordField()
        case .cancelled:
            break
        }
    }

    private var isPasswordInputBlocked: Bool {
        passwordAccessDecision != .allowed
    }

    private var visibleErrorMessage: String? {
        switch passwordAccessDecision {
        case .allowed:
            return model.errorMessage
        case .delayed(let remainingSeconds):
            return AuthError.passwordRetryAfter(remainingSeconds).localizedDescription
        case .locked(let remainingSeconds):
            return AuthError.passwordLocked(remainingSeconds).localizedDescription
        }
    }

    private func refreshPasswordAccessDecision() {
        guard !AuthenticationService.shared.isAuthenticating else { return }
        let previousDecision = passwordAccessDecision
        passwordAccessDecision = Defaults.shared.passwordBruteForceProtectionEnabled
            ? PasswordAttemptLimiter.shared.currentDecision()
            : .allowed

        if previousDecision != .allowed, passwordAccessDecision == .allowed {
            model.errorMessage = nil
            _ = DisplayIntrusionAlertService.shared.focusPasswordField()
        }
    }
}

private final class DisplayAlertFocusCoordinator {
    static let shared = DisplayAlertFocusCoordinator()

    private weak var field: NSSecureTextField?

    private init() {}

    func register(_ field: NSSecureTextField) {
        self.field = field
    }

    func unregister(_ field: NSSecureTextField) {
        if self.field === field {
            self.field = nil
        }
    }

    @discardableResult
    func focusField() -> Bool {
        guard let field,
              field.isEnabled,
              !field.isHidden,
              let window = field.window else {
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard window.makeFirstResponder(field) else { return false }

        let firstResponder = window.firstResponder
        return firstResponder === field || firstResponder === field.currentEditor()
    }

    func clear() {
        field = nil
    }
}

private final class DisplayAlertSecureTextField: NSSecureTextField {
    var onInteraction: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onInteraction?()
        super.mouseDown(with: event)
    }
}

private struct DisplayAlertSecureField: NSViewRepresentable {
    @Binding var text: String

    let placeholder: String
    let isEnabled: Bool
    let onSubmit: () -> Void
    let onInteraction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = DisplayAlertSecureTextField()
        field.placeholderString = placeholder
        field.isBezeled = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit)
        field.onInteraction = onInteraction
        DisplayAlertFocusCoordinator.shared.register(field)
        return field
    }

    func updateNSView(_ field: NSSecureTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder
        field.isEnabled = isEnabled
        (field as? DisplayAlertSecureTextField)?.onInteraction = onInteraction
        DisplayAlertFocusCoordinator.shared.register(field)
    }

    static func dismantleNSView(_ field: NSSecureTextField, coordinator: Coordinator) {
        DisplayAlertFocusCoordinator.shared.unregister(field)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DisplayAlertSecureField

        init(_ parent: DisplayAlertSecureField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSecureTextField else { return }
            parent.text = field.stringValue
        }

        @objc func submit() {
            parent.onSubmit()
        }
    }
}
