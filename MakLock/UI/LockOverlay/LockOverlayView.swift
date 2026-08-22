import SwiftUI

/// The lock overlay UI: blur background with centered authentication card.
/// Password-first is the default; Touch ID remains an optional fallback.
struct LockOverlayView: View {
    let appName: String
    let bundleIdentifier: String
    let isPrimary: Bool
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var showPasswordInput = Defaults.shared.prefersPasswordUnlock
    @State private var authState: AuthState = .authenticating
    @State private var errorMessage: String?

    private enum AuthState {
        case authenticating
        case waitingForUser
    }

    var body: some View {
        ZStack {
            // Blur background
            BlurView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            // Dark tint
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            if showPasswordInput {
                PasswordInputView(
                    onSuccess: {
                        onDismiss()
                    },
                    onCancel: {
                        showPasswordInput = false
                        authState = .waitingForUser
                    },
                    showsTouchIDFallback: isPrimary && AuthenticationService.shared.isTouchIDAvailable,
                    onUseTouchID: {
                        showPasswordInput = false
                        attemptTouchID()
                    }
                )
                .transition(.opacity)
            } else {
                // Unlock card
                VStack(spacing: 20) {
                    // App icon
                    AppIconView(bundleIdentifier: bundleIdentifier, size: 64)

                    // Title
                    Text("\(appName) is Locked")
                        .font(MakLockTypography.largeTitle)
                        .foregroundColor(MakLockColors.textPrimary)

                    if authState == .authenticating {
                        // Touch ID in progress
                        ProgressView()
                            .controlSize(.regular)
                            .padding(.top, 4)

                        Text("Authenticating...")
                            .font(MakLockTypography.body)
                            .foregroundColor(MakLockColors.textSecondary)
                    } else {
                        // Touch ID failed or cancelled — show options
                        if let errorMessage {
                            Text(errorMessage)
                                .font(MakLockTypography.caption)
                                .foregroundColor(MakLockColors.error)
                        }

                        PrimaryButton("Try Again", icon: "touchid") {
                            attemptTouchID()
                        }
                        .padding(.top, 4)

                        SecondaryButton("Use Password Instead") {
                            OverlayWindowService.shared.enableKeyboardInput()
                            withAnimation(MakLockAnimations.standard) {
                                showPasswordInput = true
                            }
                        }
                    }

                    // Dev mode skip button
                    #if DEBUG
                    Button("Skip (Dev)") {
                        onDismiss()
                    }
                    .font(MakLockTypography.caption)
                    .foregroundColor(MakLockColors.error)
                    .padding(.top, 8)
                    #endif
                }
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(MakLockColors.cardDark)
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
                )
                .scaleEffect(isVisible ? 1.0 : 0.9)
                .opacity(isVisible ? 1.0 : 0.0)
                .transition(.opacity)
            }
        }
        .onAppear {
            withAnimation(MakLockAnimations.overlayAppear) {
                isVisible = true
            }
            if Defaults.shared.prefersPasswordUnlock {
                // Password-first is designed for remote and keyboard-only Macs.
                // The primary overlay becomes key so PasswordInputView can focus its field.
                if isPrimary {
                    OverlayWindowService.shared.enableKeyboardInput()
                }
            } else if isPrimary {
                // Only the primary screen triggers Touch ID (prevents duplicate system prompts).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    attemptTouchID()
                }
            }
        }
    }

    private func attemptTouchID() {
        authState = .authenticating
        errorMessage = nil

        // Lower overlay level and pass through mouse so system Touch ID dialog gets full focus
        OverlayWindowService.shared.setTouchIDMode(true)

        AuthenticationService.shared.authenticateWithTouchID(
            reason: String(localized: "Unlock \(appName)")
        ) { result in
            // Restore overlay level and mouse capture
            OverlayWindowService.shared.setTouchIDMode(false)

            switch result {
            case .success:
                onDismiss()
            case .failure(let error):
                authState = .waitingForUser
                errorMessage = error.localizedDescription
            case .cancelled:
                authState = .waitingForUser
            }
        }
    }
}
