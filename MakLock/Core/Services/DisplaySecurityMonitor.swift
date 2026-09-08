import AppKit
import CoreGraphics

struct DisplayDescriptor: Hashable, Identifiable {
    let displayID: CGDirectDisplayID
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32
    let identityComponent: String
    let isBuiltIn: Bool
    let name: String

    var id: String { fingerprint }

    var fingerprint: String {
        "\(vendorID):\(productID):\(identityComponent):\(isBuiltIn ? 1 : 0)"
    }
}

private func displaySecurityCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    let monitor = Unmanaged<DisplaySecurityMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.scheduleEvaluation()
}

final class DisplaySecurityMonitor {
    static let shared = DisplaySecurityMonitor()

    var onUntrustedDisplayChange: (() -> Void)?

    private var isStarted = false
    private var pendingEvaluation: DispatchWorkItem?
    private var trustTracker = DisplayTrustTracker()
    private var callbackContext: UnsafeMutableRawPointer?

    private init() {}

    func reloadSettings() {
        if Defaults.shared.lockOnDisplayChange {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard !isStarted else {
            evaluateCurrentDisplays()
            return
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard CGDisplayRegisterReconfigurationCallback(displaySecurityCallback, context) == .success else {
            NSLog("[MakLock] Failed to register display security callback")
            return
        }

        callbackContext = context
        isStarted = true
        trustTracker.reset()
        evaluateCurrentDisplays()
        NSLog("[MakLock] Display security monitor started")
    }

    func stop() {
        pendingEvaluation?.cancel()
        pendingEvaluation = nil

        if let callbackContext {
            CGDisplayRemoveReconfigurationCallback(displaySecurityCallback, callbackContext)
        }

        callbackContext = nil
        isStarted = false
        trustTracker.reset()
        NSLog("[MakLock] Display security monitor stopped")
    }

    func trustCurrentDisplays() {
        let displays = Self.currentDisplays()
        Defaults.shared.trustedDisplayFingerprints = displays.map(\.fingerprint).sorted()
        trustTracker.reset()
        NSLog("[MakLock] Trusted display baseline updated (%d displays)", displays.count)
    }

    func scheduleEvaluation() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isStarted else { return }
            self.pendingEvaluation?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                self?.evaluateCurrentDisplays()
            }
            self.pendingEvaluation = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
        }
    }

    static func currentDisplays() -> [DisplayDescriptor] {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            return []
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
            return []
        }

        return displayIDs.prefix(Int(displayCount)).map { displayID in
            DisplayDescriptor(
                displayID: displayID,
                vendorID: CGDisplayVendorNumber(displayID),
                productID: CGDisplayModelNumber(displayID),
                serialNumber: CGDisplaySerialNumber(displayID),
                identityComponent: stableIdentityComponent(for: displayID),
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                name: screenName(for: displayID)
            )
        }
    }

    private func evaluateCurrentDisplays() {
        guard Defaults.shared.lockOnDisplayChange else { return }

        let current = Self.currentDisplays().map(\.fingerprint)
        let trusted = Defaults.shared.trustedDisplayFingerprints
        guard trustTracker.observe(current: current, trusted: trusted) else { return }

        NSLog("[MakLock] Untrusted display configuration detected")
        onUntrustedDisplayChange?()
    }

    private static func screenName(for displayID: CGDirectDisplayID) -> String {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first(where: { screen in
            (screen.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value == displayID
        })?.localizedName ?? String(localized: "Unknown Display")
    }

    private static func stableIdentityComponent(for displayID: CGDirectDisplayID) -> String {
        let serialNumber = CGDisplaySerialNumber(displayID)
        if serialNumber != 0 {
            return String(serialNumber)
        }

        guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return "display-\(displayID)"
        }

        let uuid = unmanagedUUID.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }
}
