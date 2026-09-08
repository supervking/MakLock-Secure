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
                        trustCurrentDisplays()
                    }

                    Text("Adding, removing, or replacing a display locks protected apps immediately. Resolution-only changes are ignored.")
                        .font(MakLockTypography.caption)
                        .foregroundColor(.secondary)
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
            refreshDisplayStatus()
        }
        .sheet(isPresented: $showPasswordSheet) {
            passwordSheet
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

    private func refreshDisplayStatus() {
        currentDisplays = DisplaySecurityMonitor.currentDisplays()
        trustedDisplayCount = Defaults.shared.trustedDisplayFingerprints.count
    }
}
