#if os(macOS)
    import AppKit
    import Foundation
    import OSLog
    import SwiftUI

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "KeyboardMonitor"
    )

    struct OnKeyPressModifier: ViewModifier {
        let onKeyPress: (KeyboardShortcut) -> Void
        let enabled: Bool
        let captureShortcuts: Bool
        @AllCustomKeyboardShortcuts private var allKeyboardShortcuts: [CustomKeyboardShortcut]

        func body(content: Content) -> some View {
            if enabled {
                content.overlay(
                    KeyHandlingViewRepresentable(onKeyPress: onKeyPress, captureShortcuts: captureShortcuts, keyboardShortcuts: allKeyboardShortcuts)
                        .allowsHitTesting(false)
                )
            } else {
                content
            }
        }
    }

    extension View {
        func onKeyDown(_ onKeyPress: @escaping (KeyboardShortcut) -> Void, enabled: Bool = true, captureShortcuts: Bool = false) -> some View {
            modifier(OnKeyPressModifier(onKeyPress: onKeyPress, enabled: enabled, captureShortcuts: captureShortcuts))
        }
    }

    struct KeyHandlingViewRepresentable: NSViewRepresentable {
        var onKeyPress: (KeyboardShortcut) -> Void
        var captureShortcuts: Bool
        var keyboardShortcuts: [CustomKeyboardShortcut]

        func makeNSView(context _: Context) -> KeyHandlingView {
            KeyHandlingView(onKeyPress: onKeyPress, captureShortcuts: captureShortcuts, keyboardShorctus: keyboardShortcuts)
        }

        func updateNSView(_: KeyHandlingView, context _: Context) {}

        class KeyHandlingView: NSView {
            var onKeyPress: (KeyboardShortcut) -> Void
            var keyboardShortcuts: [CustomKeyboardShortcut]
            var observerTokens: [Any] = []
            var captureShortcuts: Bool

            init(onKeyPress: @escaping (KeyboardShortcut) -> Void, captureShortcuts: Bool, keyboardShorctus: [CustomKeyboardShortcut]) {
                self.onKeyPress = onKeyPress
                self.captureShortcuts = captureShortcuts
                self.keyboardShortcuts = keyboardShorctus
                super.init(frame: .zero)
                setupObservers()
                becomeFirstResponder()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.becomeFirstResponder()
                    NSApp.mainWindow?.makeFirstResponder(self)
                }
            }

            override func resignFirstResponder() -> Bool {
                logger.info("Asked to resign first responder. Returning false")
                return false
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override var acceptsFirstResponder: Bool { true }

            override func keyDown(with event: NSEvent) {
                if let ke = getKeyEquivalent(from: event) {
                    for shortcut in keyboardShortcuts {
                        if shortcut.key == ke.key && shortcut.modifiers == ke.modifiers {
                            logger.info("Not handling key press because found shortcut with title \(shortcut.title)")
                            super.keyDown(with: event)
                            return
                        }
                    }

                    onKeyPress(ke)
                    return
                }

                super.keyDown(with: event)
            }

            override func performKeyEquivalent(with event: NSEvent) -> Bool {
                if !captureShortcuts {
                    return false
                }
                if let ke = getKeyEquivalent(from: event) {
                    onKeyPress(ke)
                    return true
                }

                return false
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                becomeFirstResponder()
                window?.makeFirstResponder(self)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    if let self {
                        becomeFirstResponder()
                        NSApp.mainWindow?.makeFirstResponder(self)
                    }
                }
            }

            override func viewDidMoveToSuperview() {
                super.viewDidMoveToSuperview()
                becomeFirstResponder()

                window?.makeFirstResponder(self)
            }

            deinit {
                DispatchQueue.main.async{
                    for token in self.observerTokens {
                        NotificationCenter.default.removeObserver(token)
                    }
                }
            }

            private func windowDidBecomeMain() {
                window?.makeFirstResponder(self)
            }

            private func setupObservers() {
                let token = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeMainNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.windowDidBecomeMain()
                    }
                }
                observerTokens.append(token)
            }
        }
    }

    func getKeyEquivalent(from event: NSEvent) -> KeyboardShortcut? {
        guard event.type == .keyDown else { return nil }

        if let specialKey = specialKeyMapping(forKeyCode: event.keyCode) {
            return KeyboardShortcut(specialKey, modifiers: mapModifierFlags(event.modifierFlags))
        }

        let characters: String
        if let regularCharacters = event.characters(byApplyingModifiers: []) {
            characters = regularCharacters
        } else if let keyEquivalent = specialKeyMapping(forKeyCode: event.keyCode) {
            return KeyboardShortcut(keyEquivalent, modifiers: mapModifierFlags(event.modifierFlags))
        } else {
            return nil
        }

        guard let firstCharacter = characters.first else { return nil }

        let ke = KeyEquivalent(firstCharacter)

        return KeyboardShortcut(ke, modifiers: mapModifierFlags(event.modifierFlags))
    }

    private func specialKeyMapping(forKeyCode keyCode: UInt16) -> KeyEquivalent? {
        switch keyCode {
        case 123: .leftArrow
        case 124: .rightArrow
        case 125: .downArrow
        case 126: .upArrow
        case 36: .return
        case 48: .tab
        case 51: .delete
        case 53: .escape
        case 115: .home
        case 116: .pageUp
        case 119: .end
        case 121: .pageDown
        case 117: .clear

        default: nil
        }
    }

    private func mapModifierFlags(_ flags: NSEvent.ModifierFlags) -> EventModifiers {
        var modifiers = EventModifiers()

        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.capsLock) {
            modifiers.insert(.capsLock)
        }

        return modifiers
    }
#endif
