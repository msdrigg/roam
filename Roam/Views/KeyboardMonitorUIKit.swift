#if !os(macOS) && !os(tvOS)
    import Foundation
    import OSLog
    import SwiftUI
    import UIKit

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "KeyboardMonitor"
    )

    struct OnKeyPressModifier: ViewModifier {
        let onKeyPress: (KeyboardShortcut) -> Void
        let onKeyboardShortcut: ((CustomKeyboardShortcut.Key) -> Void)?
        let enabled: Bool
        @FocusState private var isFocused: Bool

        @AllCustomKeyboardShortcuts private var allKeyboardShortcuts: [CustomKeyboardShortcut]

        func body(content: Content) -> some View {
            if !enabled {
                return AnyView(content)
            }

            return AnyView(KeyPressableContainer(content: content, onKeyPress: onKeyPress, onKeyboardShortcut: onKeyboardShortcut, keyboardShortcuts: allKeyboardShortcuts))
        }
    }

    extension View {
        func onKeyDown(_ onKeyPress: @escaping (KeyboardShortcut) -> Void, onKeyboardShortcut: ((CustomKeyboardShortcut.Key) -> Void)? = nil, enabled: Bool = true) -> some View {
            modifier(OnKeyPressModifier(onKeyPress: onKeyPress, onKeyboardShortcut: onKeyboardShortcut, enabled: enabled))
        }
    }

    private struct KeyPressableContainer<Content: View>: UIViewControllerRepresentable {
        let content: Content
        let onKeyPress: (KeyboardShortcut) -> Void
        let onKeyboardShortcut: ((CustomKeyboardShortcut.Key) -> Void)?
        let keyboardShortcuts: [CustomKeyboardShortcut]

        @MainActor func makeUIViewController(context: Context) -> KeyPressableViewController<Content> {
            let viewController = KeyPressableViewController<Content>()
            viewController.onKeyPress = onKeyPress
            viewController.onKeyboardShortcut = onKeyboardShortcut
            if viewController.onKeyboardShortcut != nil {
                viewController.keyboardShortcuts = keyboardShortcuts
            } else {
                viewController.keyboardShortcuts = nil
            }

            let hostingController = UIHostingController(rootView: content)
            viewController.addChild(hostingController)
            viewController.view.addSubview(hostingController.view)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: viewController.view.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor)
            ])
            hostingController.didMove(toParent: viewController)
            viewController.hostingController = hostingController

            return viewController
        }

        func updateUIViewController(_ uiViewController: KeyPressableViewController<Content>, context: Context) {
            uiViewController.keyboardShortcuts = keyboardShortcuts
            uiViewController.onKeyPress = onKeyPress
            uiViewController.onKeyboardShortcut = onKeyboardShortcut
            if uiViewController.onKeyboardShortcut == nil {
                uiViewController.keyboardShortcuts = nil
            }
            if let hc = uiViewController.hostingController {
                hc.rootView = content
            }
        }
    }

    private class KeyPressableViewController<Content: View>: UIViewController {
        var onKeyPress: ((KeyboardShortcut) -> Void)?
        var onKeyboardShortcut: ((CustomKeyboardShortcut.Key) -> Void)?
        var keyboardShortcuts: [CustomKeyboardShortcut]?

        weak var hostingController: UIHostingController<Content>?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }

        override var keyCommands: [UIKeyCommand]? {
            let commands = keyboardShortcuts?.compactMap { ks in
                ks.getUIKeyCommand(action: #selector(handleKeyPress(_:)))
            }
            return commands
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                if let key = press.key, let ke = getKeyEquivalent(key) {
                    for shortcut in keyboardShortcuts ?? [] {
                        if shortcut.key == ke.key && shortcut.modifiers == ke.modifiers {
                            logger.info("Not handling key press because found shortcut with title \(shortcut.title, privacy: .public)")
                            super.pressesBegan(presses, with: event)
                            return
                        }
                    }
                    logger.info("Handling key press \(ke.key.printableRepresentation, privacy: .public)")
                    onKeyPress?(ke)
                    handled = true
                }
            }

            if !handled {
                super.pressesBegan(presses, with: event)
            }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        }

        @objc func handleKeyPress(_ command: UIKeyCommand) {
            logger.info("Getting keyboard shortcut \(command.title, privacy: .public) \(String(describing: command.input), privacy: .public)")
            if let key = CustomKeyboardShortcut.Key(rawValue: command.title) {
                onKeyboardShortcut?(key)
            }
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            becomeFirstResponder()
        }

        override func resignFirstResponder() -> Bool {
            return false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }
    }

    @MainActor
    func getKeyEquivalent(_ key: UIKey) -> KeyboardShortcut? {
        if let specialKey = specialKeyMapping(key: key) {
            return KeyboardShortcut(specialKey, modifiers: mapModifierFlags(key.modifierFlags))
        }

        guard let firstCharacter = key.characters.first else {
            return nil
        }

        let ke = KeyEquivalent(firstCharacter)
        return KeyboardShortcut(ke, modifiers: mapModifierFlags(key.modifierFlags))
    }

    @MainActor
    private func specialKeyMapping(key: UIKey) -> KeyEquivalent? {
        switch key.keyCode {
        case UIKeyboardHIDUsage.keyboardLeftArrow: .leftArrow
        case UIKeyboardHIDUsage.keyboardRightArrow: .rightArrow
        case UIKeyboardHIDUsage.keyboardDownArrow: .downArrow
        case UIKeyboardHIDUsage.keyboardUpArrow: .upArrow
        case UIKeyboardHIDUsage.keyboardReturnOrEnter: .return
        case UIKeyboardHIDUsage.keyboardTab: .tab
        case UIKeyboardHIDUsage.keyboardDeleteOrBackspace: .delete
        case UIKeyboardHIDUsage.keyboardEscape: .escape
        case UIKeyboardHIDUsage.keyboardHome: .home
        case UIKeyboardHIDUsage.keyboardPageUp: .pageUp
        case UIKeyboardHIDUsage.keyboardEnd: .end
        case UIKeyboardHIDUsage.keyboardPageDown: .pageDown
        case UIKeyboardHIDUsage.keyboardClear: .clear
        default: nil
        }
    }

    private func mapModifierFlags(_ flags: UIKeyModifierFlags) -> EventModifiers {
        var modifiers = EventModifiers()

        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.alternate) {
            modifiers.insert(.option)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.alphaShift) {
            modifiers.insert(.capsLock)
        }

        return modifiers
    }
#endif
