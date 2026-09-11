import AppKit
import Combine
import SwiftUI

/// Password fallback input view shown in the lock overlay.
struct PasswordInputView: View {
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var shakeOffset: CGFloat = 0
    @State private var passwordAccessDecision: PasswordAccessDecision = .allowed
    @State private var isPasswordRecoveryActive = false

    private let accessRefreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    let onSuccess: () -> Void
    let onCancel: () -> Void
    let showsTouchIDFallback: Bool
    let onUseTouchID: () -> Void
    let showsPasswordRecovery: Bool
    let presentedDisplayID: CGDirectDisplayID?
    let onRecoveryAuthenticationModeChanged: (Bool) -> Void

    @StateObject private var capsLockMonitor = CapsLockMonitor()

    var body: some View {
        VStack(spacing: 16) {
            if !isPasswordRecoveryActive {
                Text("Enter App Password")
                    .font(MakLockTypography.title)
                    .foregroundColor(MakLockColors.textPrimary)

                FocusableSecureField(
                    text: $password,
                    placeholder: String(localized: "MakLock App Password"),
                    isEnabled: !isPasswordInputBlocked,
                    onSubmit: verifyPassword,
                    onInteraction: focusPasswordField
                )
                .frame(width: 240, height: 24)
                .offset(x: shakeOffset)

                if let visibleErrorMessage {
                    Text(visibleErrorMessage)
                        .font(MakLockTypography.caption)
                        .foregroundColor(MakLockColors.error)
                }

                if capsLockMonitor.isEnabled {
                    Text("Caps Lock is on.")
                        .font(MakLockTypography.caption)
                        .foregroundColor(MakLockColors.error)
                }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(MakLockColors.textPrimary)

                    PrimaryButton("Unlock") {
                        verifyPassword()
                    }
                    .disabled(isPasswordInputBlocked)
                }

                if showsTouchIDFallback {
                    SecondaryButton("Use Touch ID Instead") {
                        onUseTouchID()
                    }
                }
            }

            if showsPasswordRecovery {
                PasswordRecoveryControls(
                    presentedDisplayID: presentedDisplayID,
                    onAuthenticationModeChanged: onRecoveryAuthenticationModeChanged,
                    onFlowActiveChanged: { active in
                        isPasswordRecoveryActive = active
                        password = ""
                        errorMessage = nil
                        if !active {
                            DispatchQueue.main.async { focusPasswordField() }
                        }
                    }
                )
                .id("password-recovery-controls")
            }
        }
        .padding(32)
        .environment(\.colorScheme, .dark)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MakLockColors.cardDark)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        )
        .onAppear {
            refreshPasswordAccessDecision()
            focusPasswordField()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            focusPasswordField()
        }
        .onReceive(accessRefreshTimer) { _ in
            refreshPasswordAccessDecision()
        }
    }

    private func verifyPassword() {
        refreshPasswordAccessDecision()
        guard !isPasswordInputBlocked else { return }

        let result = AuthenticationService.shared.authenticateWithPassword(password)

        switch result {
        case .success:
            onSuccess()
        case .failure(let error):
            errorMessage = error.localizedDescription
            password = ""
            triggerShake()
            refreshPasswordAccessDecision()
            focusPasswordField()
        case .cancelled:
            break
        }
    }

    private func triggerShake() {
        withAnimation(Animation.default.speed(4)) {
            shakeOffset = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(Animation.default.speed(4)) {
                shakeOffset = -10
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(Animation.default.speed(4)) {
                shakeOffset = 0
            }
        }
    }

    private func focusPasswordField() {
        guard !isPasswordInputBlocked, !isPasswordRecoveryActive,
              !AuthenticationService.shared.isAuthenticating else {
            return
        }
        OverlayWindowService.shared.enableKeyboardInput()
    }

    private var isPasswordInputBlocked: Bool {
        passwordAccessDecision != .allowed
    }

    private var visibleErrorMessage: String? {
        switch passwordAccessDecision {
        case .allowed:
            return errorMessage
        case .delayed(let remainingSeconds):
            return AuthError.passwordRetryAfter(remainingSeconds).localizedDescription
        case .locked(let remainingSeconds):
            return AuthError.passwordLocked(remainingSeconds).localizedDescription
        }
    }

    private func refreshPasswordAccessDecision() {
        guard !AuthenticationService.shared.isAuthenticating, !isPasswordRecoveryActive else { return }
        let previousDecision = passwordAccessDecision
        passwordAccessDecision = Defaults.shared.passwordBruteForceProtectionEnabled
            ? PasswordAttemptLimiter.shared.currentDecision()
            : .allowed

        if previousDecision != .allowed, passwordAccessDecision == .allowed {
            errorMessage = nil
            focusPasswordField()
        }
    }
}

struct PasswordRecoveryControls: View {
    let presentedDisplayID: CGDirectDisplayID?
    let onAuthenticationModeChanged: (Bool) -> Void
    let onFlowActiveChanged: (Bool) -> Void

    @State private var authorization: PasswordRecoveryAuthorization?
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isAuthenticating = false
    @State private var authenticationRequestID: UUID?
    @StateObject private var capsLockMonitor = CapsLockMonitor()

    var body: some View {
        VStack(spacing: 10) {
            if let authorization {
                Text("Set a New App Password")
                    .font(MakLockTypography.body)
                    .foregroundColor(MakLockColors.textPrimary)

                SecureField("New App Password", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                SecureField("Confirm New App Password", text: $confirmation)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)

                if capsLockMonitor.isEnabled {
                    Text("Caps Lock is on.")
                        .font(MakLockTypography.caption)
                        .foregroundColor(MakLockColors.error)
                }

                HStack(spacing: 12) {
                    Button("Cancel Reset") {
                        cancelReset(authorization)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(MakLockColors.textPrimary)
                    PrimaryButton("Reset App Password") {
                        resetPassword(authorization)
                    }
                }
            } else if successMessage == nil {
                Button("Forgot App Password?") {
                    authorizeRecovery()
                }
                .buttonStyle(.link)
                .disabled(isAuthenticating)

                Text("Requires Touch ID or your Mac login password.")
                    .font(MakLockTypography.caption)
                    .foregroundColor(MakLockColors.textSecondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(MakLockTypography.caption)
                    .foregroundColor(MakLockColors.error)
            }

            if let successMessage {
                Text(successMessage)
                    .font(MakLockTypography.caption)
                    .foregroundColor(MakLockColors.success)
            }
        }
        .onDisappear {
            let shouldCancelAuthentication = isAuthenticating
            authenticationRequestID = nil
            isAuthenticating = false
            if shouldCancelAuthentication {
                AuthenticationService.shared.cancelAuthentication()
                onAuthenticationModeChanged(false)
            }
            PasswordRecoveryService.shared.cancel(authorization)
            newPassword = ""
            confirmation = ""
        }
    }

    private func authorizeRecovery() {
        guard !isAuthenticating, !AuthenticationService.shared.isAuthenticating else { return }
        let requestID = UUID()
        authenticationRequestID = requestID
        isAuthenticating = true
        errorMessage = nil
        onAuthenticationModeChanged(true)
        PasswordRecoveryService.shared.authorize(presentedDisplayID: presentedDisplayID) { result in
            guard authenticationRequestID == requestID else {
                if case .authorized(let staleAuthorization) = result {
                    PasswordRecoveryService.shared.cancel(staleAuthorization)
                }
                return
            }
            authenticationRequestID = nil
            isAuthenticating = false
            onAuthenticationModeChanged(false)
            switch result {
            case .authorized(let issuedAuthorization):
                authorization = issuedAuthorization
                successMessage = nil
                onFlowActiveChanged(true)
            case .failure(let error):
                errorMessage = error.localizedDescription
                onFlowActiveChanged(false)
            case .cancelled:
                onFlowActiveChanged(false)
            }
        }
    }

    private func resetPassword(_ authorization: PasswordRecoveryAuthorization) {
        errorMessage = nil
        switch PasswordRecoveryService.shared.resetPassword(
            newPassword,
            confirmation: confirmation,
            authorization: authorization,
            presentedDisplayID: presentedDisplayID
        ) {
        case .success:
            self.authorization = nil
            newPassword = ""
            confirmation = ""
            successMessage = String(
                localized: "App password reset. This app remains locked; unlock it with the new password."
            )
            onFlowActiveChanged(false)
        case .validationFailure(let validation):
            errorMessage = validation.localizedMessage
        case .failure(let error):
            errorMessage = error.localizedDescription
            if error == .passwordRecoveryExpired || error == .passwordRecoveryUnavailable {
                self.authorization = nil
                onFlowActiveChanged(false)
            }
        }
    }

    private func cancelReset(_ authorization: PasswordRecoveryAuthorization) {
        PasswordRecoveryService.shared.cancel(authorization)
        self.authorization = nil
        newPassword = ""
        confirmation = ""
        errorMessage = nil
        onFlowActiveChanged(false)
    }
}

final class CapsLockMonitor: ObservableObject {
    @Published private(set) var isEnabled = NSEvent.modifierFlags.contains(.capsLock)
    private var eventMonitor: Any?

    init() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            let enabled = event.modifierFlags.contains(.capsLock)
            if self?.isEnabled != enabled { self?.isEnabled = enabled }
            return event
        }
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}
