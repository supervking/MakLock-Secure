import AppKit
import SwiftUI

@main
enum PasswordFieldInteractionTests {
    static func main() {
        _ = NSApplication.shared
        var boundText = "previous value"
        var submitted: [String] = []
        let view = FocusableSecureField(
            text: Binding(get: { boundText }, set: { boundText = $0 }),
            placeholder: "App password",
            isEnabled: true,
            onSubmit: { submitted.append(boundText) },
            onInteraction: {}
        )
        let coordinator = view.makeCoordinator()
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 40)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let renderedField = findField(host) else {
            preconditionFailure("Native secure field must render")
        }
        precondition(renderedField.cell?.sendsActionOnEndEditing == false,
                     "Changing focus must not submit the password")
        let field = NSSecureTextField()
        field.stringValue = "fresh synthetic value"
        coordinator.submit(field)
        precondition(submitted == ["fresh synthetic value"], "Submission must use current native field text")
        AuthenticationService.shared.isAuthenticating = true
        PasswordFieldFocusCoordinator.shared.register(field)
        precondition(!PasswordFieldFocusCoordinator.shared.focusPrimaryField())
        AuthenticationService.shared.isAuthenticating = false
        PasswordFieldFocusCoordinator.shared.unregister(field)
        print("Password field interaction tests passed")
    }

    static func findField(_ view: NSView) -> NSSecureTextField? {
        if let field = view as? NSSecureTextField { return field }
        for child in view.subviews {
            if let field = findField(child) { return field }
        }
        return nil
    }
}

final class AuthenticationService {
    static let shared = AuthenticationService()
    var isAuthenticating = false
}
