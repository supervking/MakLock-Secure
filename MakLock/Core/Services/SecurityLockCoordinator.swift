import AppKit

final class SecurityLockCoordinator {
    static let shared = SecurityLockCoordinator()

    var onLockRequired: ((ProtectedApp, SecurityLockReason) -> Void)?

    private init() {}

    func lockProtectedApps(reason: SecurityLockReason) {
        DispatchQueue.main.async { [weak self] in
            guard Defaults.shared.appSettings.isProtectionEnabled else { return }

            AppMonitorService.shared.clearAllAuthentications()

            guard !OverlayWindowService.shared.isShowing,
                  let target = self?.runningLockTarget() else {
                return
            }

            NSLog("[MakLock] Security event lock requested: %@", reason.rawValue)
            self?.onLockRequired?(target, reason)
        }
    }

    private func runningLockTarget() -> ProtectedApp? {
        let protectedApps = Defaults.shared.protectedApps.filter(\.isEnabled)
        let runningApplications = NSWorkspace.shared.runningApplications
        let runningBundleIdentifiers = Set(runningApplications.compactMap(\.bundleIdentifier))

        if let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           let frontmostProtectedApp = protectedApps.first(where: {
               $0.bundleIdentifier == frontmostBundleIdentifier
           }) {
            return frontmostProtectedApp
        }

        return protectedApps.first(where: {
            runningBundleIdentifiers.contains($0.bundleIdentifier)
        })
    }
}
