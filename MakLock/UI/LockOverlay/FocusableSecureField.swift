import AppKit
import SwiftUI

final class PasswordFieldFocusCoordinator {
    static let shared = PasswordFieldFocusCoordinator()

    private let fields = NSHashTable<NSSecureTextField>.weakObjects()

    private init() {}

    func register(_ field: NSSecureTextField) {
        fields.add(field)
    }

    func unregister(_ field: NSSecureTextField) {
        fields.remove(field)
    }

    @discardableResult
    func focusPrimaryField() -> Bool {
        guard !AuthenticationService.shared.isAuthenticating else { return false }
        let primaryScreen = NSScreen.main ?? NSScreen.screens.first
        let field = fields.allObjects.first(where: {
            $0.window?.screen?.frame == primaryScreen?.frame
        }) ?? fields.allObjects.first

        guard let field,
              field.isEnabled,
              !field.isHidden,
              let window = field.window else {
            return false
        }

        if window.isKeyWindow, let editor = field.currentEditor(), window.firstResponder === editor {
            return true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard window.makeFirstResponder(field) else { return false }

        let firstResponder = window.firstResponder
        return firstResponder === field || firstResponder === field.currentEditor()
    }

    func clear() {
        fields.removeAllObjects()
    }
}

private final class FocusRecoveringSecureTextField: NSSecureTextField {
    var onInteraction: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onInteraction?()
        super.mouseDown(with: event)
    }
}

struct FocusableSecureField: NSViewRepresentable {
    @Binding var text: String

    let placeholder: String
    let isEnabled: Bool
    let onSubmit: () -> Void
    let onInteraction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = FocusRecoveringSecureTextField()
        field.placeholderString = placeholder
        field.isBezeled = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.cell?.sendsActionOnEndEditing = false
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit)
        field.onInteraction = onInteraction
        PasswordFieldFocusCoordinator.shared.register(field)
        return field
    }

    func updateNSView(_ field: NSSecureTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder
        field.isEnabled = isEnabled
        (field as? FocusRecoveringSecureTextField)?.onInteraction = onInteraction

        PasswordFieldFocusCoordinator.shared.register(field)
    }

    static func dismantleNSView(_ field: NSSecureTextField, coordinator: Coordinator) {
        PasswordFieldFocusCoordinator.shared.unregister(field)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableSecureField

        init(_ parent: FocusableSecureField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSecureTextField else { return }
            parent.text = field.stringValue
        }

        @objc func submit(_ sender: NSSecureTextField) {
            parent.text = sender.stringValue
            parent.onSubmit()
        }
    }
}
