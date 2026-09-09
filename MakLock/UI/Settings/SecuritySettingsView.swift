import SwiftUI

/// Security settings tab: authentication method, backup password.
struct SecuritySettingsView: View {
    @State private var settings = Defaults.shared.appSettings
    @State private var hasBackupPassword = false
    @State private var showPasswordSheet = false
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordError: String?
    @State private var prefersPasswordUnlock = Defaults.shared.prefersPasswordUnlock
    @State private var lockOnNetworkLoss = Defaults.shared.lockOnNetworkLoss
    @State private var networkLossGraceSeconds = Defaults.shared.networkLossGraceSeconds
    @State private var lockOnDisplayChange = Defaults.shared.lockOnDisplayChange
    @State private var currentDisplays = DisplaySecurityMonitor.currentDisplays()
    @State private var trustedDisplayCount = Defaults.shared.trustedDisplayFingerprints.count
    @State private var showTrustDisplayConfirmation = false
    @State private var quitProtectedAppsAfterRestart = Defaults.shared.quitProtectedAppsAfterRestart
    @State private var passwordBruteForceProtectionEnabled = Defaults.shared.passwordBruteForceProtectionEnabled
    @State private var emergencyRestartConfiguration = EmergencyRestartRecoveryService.shared.configuration
    @State private var emergencyRestartConfigurationError: String?
    @State private var isRestoringEmergencyRestartConfiguration = false
    @State private var recentSecurityEvents: [SecurityEventRecord] = []

    private static let eventDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        Form {
            Section {
                Toggle("Require authentication on app launch", isOn: $settings.requireAuthOnLaunch)
                    .toggleStyle(.goldSwitch)
                    .onChange(of: settings.requireAuthOnLaunch) { _ in
                        Defaults.shared.appSettings = settings
                    }

                Toggle("Require authentication on app switch", isOn: $settings.requireAuthOnActivate)
                    .toggleStyle(.goldSwitch)
                    .onChange(of: settings.requireAuthOnActivate) { _ in
                        Defaults.shared.appSettings = settings
                    }
            }

            Section("Touch ID") {
                HStack {
                    Image(systemName: "touchid")
                        .font(.system(size: 20))
                        .foregroundColor(AuthenticationService.shared.isTouchIDAvailable ? MakLockColors.success : MakLockColors.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AuthenticationService.shared.isTouchIDAvailable ? "Touch ID Available" : "Touch ID Not Available")
                            .font(MakLockTypography.body)
                        if !AuthenticationService.shared.isTouchIDAvailable {
                            Text("Touch ID is not configured on this Mac. Use a backup password instead.")
                                .font(MakLockTypography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Unlock Screen") {
                Toggle("Prefer password on lock screen", isOn: $prefersPasswordUnlock)
                    .toggleStyle(.goldSwitch)
                    .onChange(of: prefersPasswordUnlock) { enabled in
                        Defaults.shared.prefersPasswordUnlock = enabled
                    }

                Text("Show and focus the password field first. Press Return to unlock after entering the correct password.")
                    .font(MakLockTypography.caption)
                    .foregroundColor(.secondary)
            }

            Section("Security Events") {
                Toggle("Lock after internet connection is lost", isOn: $lockOnNetworkLoss)
                    .toggleStyle(.goldSwitch)
                    .onChange(of: lockOnNetworkLoss) { enabled in
                        Defaults.shared.lockOnNetworkLoss = enabled
                        NetworkSecurityMonitor.shared.reloadSettings()
                    }

                if lockOnNetworkLoss {
                    Picker("Network loss delay", selection: $networkLossGraceSeconds) {
                        ForEach([60, 120, 300], id: \.self) { seconds in
                            Text(networkDelayLabel(seconds: seconds))
                                .tag(seconds)
                        }
                    }
                    .onChange(of: networkLossGraceSeconds) { seconds in
                        Defaults.shared.networkLossGraceSeconds = seconds
                    }

                    Text("All connectivity probes must fail continuously before protected apps are locked. Reconnecting never unlocks them automatically.")
                        .font(MakLockTypography.caption)
                        .foregroundColor(.secondary)
                }

                Toggle("Lock when the trusted display setup changes", isOn: $lockOnDisplayChange)
                    .toggleStyle(.goldSwitch)
                    .onChange(of: lockOnDisplayChange) { enabled in
                        if enabled && Defaults.shared.trustedDisplayFingerprints.isEmpty {
                            trustCurrentDisplays()
                        }
                        Defaults.shared.lockOnDisplayChange = enabled
                        DisplaySecurityMonitor.shared.reloadSettings()
                        if !enabled {
                            DisplayIntrusionAlertService.shared.dismissForProtectionDisabled()
                            emergencyRestartConfiguration.isEnabled = false
                        }
                    }

                if lockOnDisplayChange {
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("Current displays: %@", comment: "Current display names"),
                        currentDisplaySummary
                    ))
                    .font(MakLockTypography.caption)

                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("%lld trusted display fingerprints", comment: "Trusted display fingerprint count"),
                        Int64(trustedDisplayCount)
                    ))
                    .font(MakLockTypography.caption)
                    .foregroundColor(.secondary)

                    Button("Trust Current Display Setup") {
                        authenticateBeforeTrustingDisplays()
                    }

                    Text("Adding, removing, mirroring, or replacing a display immediately hides the desktop and locks protected apps. The silent red alert remains until the trusted setup returns and you authenticate.")
                        .font(MakLockTypography.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Advanced Protection") {
                Toggle("Quit protected apps after Mac restart", isOn: $quitProtectedAppsAfterRestart)
                    .toggleStyle(.goldSwitch)
                    .onChange(of: quitProtectedAppsAfterRestart) { enabled in
                        Defaults.shared.quitProtectedAppsAfterRestart = enabled
                    }

                Text("After a real Mac restart, automatically restored protected apps are closed during a 90-second startup window. Remote access and system apps are never targeted.")
                    .font(MakLockTypography.caption)
                    .foregroundColor(.secondary)

                Toggle("Block password guessing", isOn: $passwordBruteForceProtectionEnabled)
                    .toggleStyle(.goldSwitch)
                    .onChange(of: passwordBruteForceProtectionEnabled) { enabled in
                        Defaults.shared.passwordBruteForceProtectionEnabled = enabled
                    }

                Text("Five wrong passwords within 30 minutes block password unlock for 3 hours. Touch ID and Apple Watch remain available.")
                    .font(MakLockTypography.caption)
                    .foregroundColor(.secondary)
            }

            Section("Emergency Display Recovery") {
                Toggle(
                    "Enable hidden restart recovery",
                    isOn: $emergencyRestartConfiguration.isEnabled
                )
                .toggleStyle(.goldSwitch)
                .disabled(!lockOnDisplayChange)
                .onChange(of: emergencyRestartConfiguration.isEnabled) { _ in
                    guard !isRestoringEmergencyRestartConfiguration else { return }
                    saveEmergencyRestartConfiguration()
                }

                if emergencyRestartConfiguration.isEnabled {
                    Picker(
                        "Required completed restarts",
                        selection: $emergencyRestartConfiguration.requiredRestartCount
                    ) {
                        ForEach(3...9, id: \.self) { restartCount in
                            Text(String.localizedStringWithFormat(
                                NSLocalizedString("%lld restarts", comment: "Emergency restart count"),
                                Int64(restartCount)
                            ))
                            .tag(restartCount)
                        }
                    }
                    .onChange(of: emergencyRestartConfiguration.requiredRestartCount) { _ in
                        guard !isRestoringEmergencyRestartConfiguration else { return }
                        saveEmergencyRestartConfiguration()
                    }

                    Picker(
                        "Completion window",
                        selection: $emergencyRestartConfiguration.windowSeconds
                    ) {
                        ForEach([180, 300, 600, 900], id: \.self) { seconds in
                            Text(networkDelayLabel(seconds: seconds))
                                .tag(seconds)
                        }
                    }
                    .onChange(of: emergencyRestartConfiguration.windowSeconds) { _ in
                        guard !isRestoringEmergencyRestartConfiguration else { return }
                        saveEmergencyRestartConfiguration()
                    }
                }

                Text("Only real restarts requested from the unauthorized-display alert can advance recovery. The alert never shows the configured count, time window, or progress.")
                    .font(MakLockTypography.caption)
                    .foregroundColor(.secondary)

                if let emergencyRestartConfigurationError {
                    Text(emergencyRestartConfigurationError)
                        .font(MakLockTypography.caption)
                        .foregroundColor(MakLockColors.error)
                }
            }

            Section("Recent Security Events — 12 Hours") {
                if recentSecurityEvents.isEmpty {
                    Text("No security events in the last 12 hours")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(recentSecurityEvents) { event in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: event.succeeded ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .foregroundColor(event.succeeded ? MakLockColors.success : MakLockColors.locked)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(eventTitle(event.kind))
                                    .font(MakLockTypography.body)
                                Text(eventSummary(event))
                                    .font(MakLockTypography.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(Self.eventDateFormatter.string(from: event.timestamp))
                                .font(MakLockTypography.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section("Backup Password") {
                if hasBackupPassword {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(MakLockColors.success)
                        Text("Backup password is set")
                            .font(MakLockTypography.body)
                    }

                    Button("Change Password...") {
                        resetPasswordFields()
                        showPasswordSheet = true
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(MakLockColors.locked)
                        Text("No backup password set")
                            .font(MakLockTypography.body)
                    }

                    Text("A backup password lets you unlock apps when Touch ID is unavailable.")
                        .font(MakLockTypography.caption)
                        .foregroundColor(.secondary)

                    Button("Set Password...") {
                        resetPasswordFields()
                        showPasswordSheet = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            hasBackupPassword = KeychainManager.shared.hasPassword()
            emergencyRestartConfiguration = EmergencyRestartRecoveryService.shared.configuration
            refreshDisplayStatus()
            recentSecurityEvents = SecurityEventStore.shared.recentRecords()
        }
        .sheet(isPresented: $showPasswordSheet) {
            passwordSheet
        }
        .confirmationDialog(
            "Trust Current Display Setup?",
            isPresented: $showTrustDisplayConfirmation,
            titleVisibility: .visible
        ) {
            Button("Trust Current Display Setup", role: .destructive) {
                trustCurrentDisplays()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only trust this setup when every connected display is under your control.")
        }
    }

    // MARK: - Password Sheet

    private var passwordSheet: some View {
        VStack(spacing: 16) {
            Text(hasBackupPassword ? "Change Password" : "Set Backup Password")
                .font(MakLockTypography.title)

            SecureField("New Password", text: $newPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            SecureField("Confirm Password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            if let passwordError {
                Text(passwordError)
                    .font(MakLockTypography.caption)
                    .foregroundColor(MakLockColors.error)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showPasswordSheet = false
                }

                PrimaryButton("Save") {
                    savePassword()
                }
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    private func savePassword() {
        guard !newPassword.isEmpty else {
            passwordError = String(localized: "Password cannot be empty.")
            return
        }

        guard newPassword.count >= 4 else {
            passwordError = String(localized: "Password must be at least 4 characters.")
            return
        }

        guard newPassword == confirmPassword else {
            passwordError = String(localized: "Passwords do not match.")
            return
        }

        let saved = KeychainManager.shared.savePassword(newPassword)
        if saved {
            Defaults.shared.isBackupPasswordSet = true
            hasBackupPassword = true
            showPasswordSheet = false
        } else {
            passwordError = String(localized: "Failed to save password. Please try again.")
        }
    }

    private func resetPasswordFields() {
        newPassword = ""
        confirmPassword = ""
        passwordError = nil
    }

    private var currentDisplaySummary: String {
        guard !currentDisplays.isEmpty else {
            return String(localized: "No Displays")
        }
        return currentDisplays.map(\.name).joined(separator: ", ")
    }

    private func networkDelayLabel(seconds: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("%lld min", comment: "Network loss delay in minutes"),
            Int64(seconds / 60)
        )
    }

    private func trustCurrentDisplays() {
        DisplaySecurityMonitor.shared.trustCurrentDisplays()
        refreshDisplayStatus()
    }

    private func authenticateBeforeTrustingDisplays() {
        AuthenticationService.shared.authenticateWithSystemFallback(
            reason: String(localized: "Authorize trusted display change")
        ) { result in
            if case .success = result {
                showTrustDisplayConfirmation = true
            }
        }
    }

    private func refreshDisplayStatus() {
        currentDisplays = DisplaySecurityMonitor.currentDisplays()
        trustedDisplayCount = Defaults.shared.trustedDisplayFingerprints.count
    }

    private func saveEmergencyRestartConfiguration() {
        let requestedConfiguration = emergencyRestartConfiguration.normalized
        guard requestedConfiguration != EmergencyRestartRecoveryService.shared.configuration else {
            emergencyRestartConfigurationError = nil
            return
        }
        if EmergencyRestartRecoveryService.shared.updateConfiguration(requestedConfiguration) {
            emergencyRestartConfiguration = EmergencyRestartRecoveryService.shared.configuration
            emergencyRestartConfigurationError = nil
        } else {
            isRestoringEmergencyRestartConfiguration = true
            emergencyRestartConfiguration = EmergencyRestartRecoveryService.shared.configuration
            emergencyRestartConfigurationError = String(
                localized: "Failed to save emergency restart recovery settings."
            )
            DispatchQueue.main.async {
                isRestoringEmergencyRestartConfiguration = false
            }
        }
    }

    private func eventTitle(_ kind: SecurityEventKind) -> LocalizedStringKey {
        switch kind {
        case .protectedAppActivation:
            return "Protected app activated"
        case .networkLoss:
            return "Internet connection lost"
        case .displayChange:
            return "Display setup changed"
        case .restartCleanup:
            return "Restart cleanup"
        case .idleTimeout:
            return "Idle timeout"
        case .sleep:
            return "Mac sleep"
        case .watchOutOfRange:
            return "Apple Watch out of range"
        case .passwordFailure:
            return "Wrong password"
        case .passwordLockout:
            return "Password locked"
        case .blockedPasswordAttempt:
            return "Blocked password attempt"
        case .sessionFocusRecovery:
            return "Password focus restored"
        case .emergencyRestartRecovery:
            return "Emergency restart recovery"
        }
    }

    private func eventSummary(_ event: SecurityEventRecord) -> String {
        if let numericDetail = event.numericDetail {
            return String.localizedStringWithFormat(
                NSLocalizedString("Security action: %@ · value: %lld", comment: "Security event action and numeric detail"),
                localizedAction(event.action),
                Int64(numericDetail)
            )
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("Security action: %@ · affected: %lld", comment: "Security event action and affected app count"),
            localizedAction(event.action),
            Int64(event.affectedCount)
        )
    }

    private func localizedAction(_ action: SecurityEventAction) -> String {
        switch action {
        case .locked:
            return String(localized: "Locked")
        case .alertShown:
            return String(localized: "Alert shown")
        case .alertDismissed:
            return String(localized: "Alert dismissed")
        case .gracefulQuit:
            return String(localized: "Quit")
        case .forcedQuit:
            return String(localized: "Force Quit")
        case .retryDelayed:
            return String(localized: "Retry delayed")
        case .passwordBlocked:
            return String(localized: "Password blocked")
        case .focusRestored:
            return String(localized: "Focus restored")
        case .restartRequested:
            return String(localized: "Restart requested")
        case .restartFailed:
            return String(localized: "Restart failed")
        case .recoveryProgressed:
            return String(localized: "Recovery progressed")
        case .recoveryActivated:
            return String(localized: "Recovery activated")
        case .recoveryReset:
            return String(localized: "Recovery reset")
        }
    }
}
