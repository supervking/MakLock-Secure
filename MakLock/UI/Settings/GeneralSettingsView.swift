import AppKit
import SwiftUI
import ServiceManagement

/// General settings tab: launch at login, idle auto-lock, sleep auto-lock.
struct GeneralSettingsView: View {
    @State private var settings = Defaults.shared.appSettings
    @AppStorage("languageOverride") private var languageOverride = AppLanguage.followSystem.rawValue
    @State private var languageRestartRequired = false
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        Form {
            Section {
                Toggle("Launch MakLock at login", isOn: $settings.launchAtLogin)
                    .toggleStyle(.goldSwitch)

                Toggle("Lock apps when Mac sleeps", isOn: $settings.lockOnSleep)
                    .toggleStyle(.goldSwitch)
            }

            Section {
                Toggle("Lock apps after idle timeout", isOn: $settings.lockOnIdle)
                    .toggleStyle(.goldSwitch)

                if settings.lockOnIdle {
                    HStack {
                        Text("Timeout:")
                        Slider(
                            value: Binding(
                                get: { Double(settings.idleTimeoutMinutes) },
                                set: { newValue in
                                    let minutes = Int(newValue)
                                    settings.idleTimeoutMinutes = minutes
                                    var current = Defaults.shared.appSettings
                                    current.idleTimeoutMinutes = minutes
                                    Defaults.shared.appSettings = current
                                    if settings.lockOnIdle {
                                        IdleMonitorService.shared.startMonitoring()
                                    }
                                }
                            ),
                            in: 1...30,
                            step: 1
                        )
                        Text(String.localizedStringWithFormat(
                            NSLocalizedString("%lld min", comment: "Idle timeout in minutes"),
                            Int64(settings.idleTimeoutMinutes)
                        ))
                            .frame(width: 50, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            }

            Section {
                Picker("Language", selection: $languageOverride) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title)
                            .tag(language.rawValue)
                    }
                }

                if languageRestartRequired {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Language changes apply after restarting MakLock.")
                            .font(MakLockTypography.caption)
                            .foregroundColor(MakLockColors.textSecondary)

                        PrimaryButton("Restart MakLock", icon: "arrow.clockwise") {
                            restartMakLock()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                HStack {
                    Text("Auto-close timeout:")
                    Slider(
                        value: Binding(
                            get: { Double(settings.inactiveCloseMinutes) },
                            set: { newValue in
                                let minutes = Int(newValue)
                                settings.inactiveCloseMinutes = minutes
                                var current = Defaults.shared.appSettings
                                current.inactiveCloseMinutes = minutes
                                Defaults.shared.appSettings = current
                            }
                        ),
                        in: 1...60,
                        step: 1
                    )
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("%lld min", comment: "Auto-close timeout in minutes"),
                        Int64(settings.inactiveCloseMinutes)
                    ))
                        .frame(width: 50, alignment: .trailing)
                        .monospacedDigit()
                }

                Text("Apps with the timer icon enabled will quit after this period of inactivity.")
                    .font(MakLockTypography.caption)
                    .foregroundColor(MakLockColors.textSecondary)
            }

            Section {
                Text("Automatic in-app updates are disabled to preserve verified security fixes.")
                    .font(MakLockTypography.caption)
                    .foregroundColor(MakLockColors.textSecondary)

                HStack(spacing: 8) {
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("MakLock %@ (%@)  ·  Made by MakMak", comment: "Application version and attribution"),
                        version,
                        build
                    ))
                        .foregroundColor(MakLockColors.textSecondary)
                    Link(destination: URL(string: "https://github.com/supervking/MakLock-Secure")!) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right.square")
                            Text("GitHub")
                        }
                        .foregroundColor(MakLockColors.gold)
                    }
                }
                .font(MakLockTypography.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: settings.launchAtLogin) { _ in save() }
        .onChange(of: settings.lockOnSleep) { _ in save() }
        .onChange(of: settings.lockOnIdle) { _ in save() }
        .onChange(of: languageOverride) { selection in
            AppLanguage.apply(selection)
            languageRestartRequired = true
        }
    }

    private func save() {
        Defaults.shared.appSettings = settings

        // Start or stop idle monitoring based on toggle
        if settings.lockOnIdle {
            IdleMonitorService.shared.startMonitoring()
        } else {
            IdleMonitorService.shared.stopMonitoring()
        }

        // Auto-close service is always running if any app has autoClose enabled
        // (started in AppDelegate, timeout changes take effect on next timer)

        // Register or unregister launch at login
        updateLaunchAtLogin(enabled: settings.launchAtLogin)
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[MakLock] Failed to update login item: %@", error.localizedDescription)
        }
    }

    private func restartMakLock() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                NSLog("[MakLock] Failed to restart after language change: %@", error.localizedDescription)
                return
            }

            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

private enum AppLanguage: String, CaseIterable, Identifiable {
    case followSystem
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .followSystem:
            "Follow System"
        case .english:
            "English"
        case .simplifiedChinese:
            "Simplified Chinese"
        }
    }

    static func apply(_ selection: String) {
        switch Self(rawValue: selection) ?? .followSystem {
        case .followSystem:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .simplifiedChinese:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }
}
