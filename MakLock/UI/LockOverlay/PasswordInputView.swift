import AppKit
import Combine
import SwiftUI

/// Password fallback input view shown in the lock overlay.
struct PasswordInputView: View {
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var shakeOffset: CGFloat = 0
    @State private var passwordAccessDecision: PasswordAccessDecision = .allowed

    private let accessRefreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    let onSuccess: () -> Void
    let onCancel: () -> Void
    let showsTouchIDFallback: Bool
    let onUseTouchID: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Enter Password")
                .font(MakLockTypography.title)
                .foregroundColor(MakLockColors.textPrimary)

            FocusableSecureField(
                text: $password,
                placeholder: String(localized: "Password"),
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

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }

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
        .padding(32)
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
        guard !isPasswordInputBlocked else {
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
