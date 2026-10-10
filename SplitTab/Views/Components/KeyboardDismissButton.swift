import SwiftUI
import UIKit

/// Keeps dismissal unobtrusive: scroll, tap outside a field, or use Done on a number pad.
private struct KeyboardDismissBehavior: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .submitLabel(.done)
            .background(KeyboardDismissBridge().frame(width: 0, height: 0))
    }
}

private struct KeyboardDismissBridge: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ view: AttachmentView, context: Context) {}

    static func dismantleUIView(_ view: AttachmentView, coordinator: Coordinator) {
        view.onWindowChange = nil
        coordinator.attach(to: nil)
    }

    final class AttachmentView: UIView {
        var onWindowChange: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private weak var numericField: UITextField?
        private var observers: [NSObjectProtocol] = []
        private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        private lazy var toolbar: UIToolbar = {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            toolbar.tintColor = UIColor(Color.splitAccent)
            toolbar.items = [
                UIBarButtonItem(systemItem: .flexibleSpace),
                UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(dismissKeyboard))
            ]
            toolbar.items?.last?.accessibilityIdentifier = "keyboard.dismiss"
            return toolbar
        }()

        func attach(to window: UIWindow?) {
            guard self.window !== window else { return }
            self.window?.removeGestureRecognizer(tap)
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            clearAccessory()
            self.window = window
            guard let window else { return }
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            observers = [
                NotificationCenter.default.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { [weak self] notification in
                    guard let field = notification.object as? UITextField else { return }
                    MainActor.assumeIsolated { self?.beganEditing(field) }
                },
                NotificationCenter.default.addObserver(forName: UITextField.textDidEndEditingNotification, object: nil, queue: .main) { [weak self] notification in
                    guard let field = notification.object as? UITextField else { return }
                    MainActor.assumeIsolated {
                        if self?.numericField === field { self?.clearAccessory() }
                    }
                }
            ]
        }

        private func beganEditing(_ field: UITextField) {
            guard field.window === window else { return }
            switch field.keyboardType {
            case .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad:
                clearAccessory()
                numericField = field
                field.inputAccessoryView = toolbar
                field.reloadInputViews()
            default:
                clearAccessory()
            }
        }

        private func clearAccessory() {
            if let field = numericField, field.inputAccessoryView === toolbar {
                field.inputAccessoryView = nil
            }
            numericField = nil
        }

        @objc private func dismissKeyboard() { window?.endEditing(true) }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                // Keep text-field focus changes and controls responsive.
                if current is UIControl || current is UITextView { return false }
                view = current.superview
            }
            return true
        }
    }
}

extension View {
    func keyboardDismissButton() -> some View { modifier(KeyboardDismissBehavior()) }
}
