#if !os(macOS)
    import Foundation
    import os.log
    import SwiftUI

    let globalMaxLengthChars = 64

    private struct StrTransformation {
        let old: String
        let new: String
    }

    @available(iOS, introduced: 17.0)
    struct KeyboardEntry: View {
        @State var str: String = ""
        @State var strSent: String = ""
        @Binding var showing: Bool
        @FocusState private var keyboardFocused: Bool

        let semaphore: AsyncSemaphore = AsyncSemaphore(value: 1)

        @State private var transformations: [StrTransformation] = []

        @EnvironmentObject var appDelegate: RoamAppDelegate
        @Environment(\.scenePhase) var scenePhase

        var texteditId: String? {
            appDelegate.ecpMonitor.textEditStatus.texteditId
        }

        var texteditText: String? {
            appDelegate.ecpMonitor.textEditStatus.text
        }

        var ecpSession: ECPWebsocketClient? {
            appDelegate.ecpMonitor.ecpClient
        }

        let onKeyPress: @Sendable (_ press: KeyEquivalent) async -> Void
        let leaving: Bool

        var body: some View {
            TextFieldContainer(String(localized: "Enter some text...", comment: "Placeholder for a text field"), text: $str, onDelete: {
                Task {
                    await onKeyPress(.delete)
                }
            }, onDone: {
                withAnimation {
                    keyboardFocused = false

                    showing = false
                }
            }, fullFeatures: texteditId != nil)
            .textSelection(.disabled)
            .focused($keyboardFocused)
            .font(.body)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(.fill.tertiary))
            .frame(height: 60)
            .task(id: scenePhase) {
                guard scenePhase == .active else {
                    return
                }
                do {
                    try await Task.sleep(duration: 0.5)
                } catch {
                    return
                }
                let listener = KeyboardListener()
                if let events = listener.events {
                    for await _ in events {
                        withAnimation {
                            keyboardFocused = false
                            showing = false
                        }
                    }
                }
            }
            .onChange(of: str) { _, str in
                if let texteditId {
                    Task {
                        do {
                            try await ecpSession?.setTextEdit(str, texteditId: texteditId)
                        } catch {
                            Log.connection.error("Error setting textedit text \(error, privacy: .public)")
                        }
                    }
                } else {
                    let strSentNow = strSent
                    Task {
                        let charDifference = str.count - strSentNow.count

                        if charDifference > 0 {
                            let startIndex = str.index(str.endIndex, offsetBy: -charDifference)
                            let newChars = str[startIndex..<str.endIndex]

                            try await semaphore.waitUnlessCancelled()
                            defer {
                                semaphore.signal()
                            }
                            do {
                                try await withTimeout(delay: 2.0) {
                                    for char in newChars.unicodeScalars {
                                        await onKeyPress(KeyEquivalent(Character(char)))
                                    }
                                }
                            } catch {
                                Log.userInteraction.warning("Couldn't send kb input within 2s")
                            }
                        }
                    }
                }
                strSent = str
            }
            .onChange(of: texteditId) {
                Log.userInteraction.notice("Text edit id changed to \(texteditId ?? "nil")")
                if texteditId != nil && (texteditText ?? "" != str) {
                    str = texteditText ?? ""
                }
            }
            .onChange(of: leaving) { _, leaving in
                if leaving {
                    withAnimation {
                        keyboardFocused = false
                        showing = false
                    }
                } else {
                    keyboardFocused = true
                }
            }
            .onAppear {
                keyboardFocused = true
                if texteditId == nil {
                    str = ""
                    strSent = ""
                } else {
                    str = texteditText ?? ""
                    strSent = texteditText ?? ""
                }
            }
        }
    }

    final class EndOnlyTextField: UITextField {
        var didDelete: (() -> Void)?
        var fullFeatures: Bool?

        override func closestPosition(to point: CGPoint) -> UITextPosition? {
            if self.fullFeatures == true {
                return super.closestPosition(to: point)
            }

            let beginning = beginningOfDocument
            let end = position(from: beginning, offset: text?.count ?? 0)
            return end
        }

        override func deleteBackward() {
            if self.fullFeatures != true {
                didDelete?()
            }
            super.deleteBackward()
        }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            if self.fullFeatures == true {
                return super.canPerformAction(action, withSender: sender)
            }
            // Disable cut, copy, paste, select, selectAll
            if action == #selector(select(_:)) || action == #selector(selectAll(_:))
            {
                return false
            }
            return super.canPerformAction(action, withSender: sender)
        }

        override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
            if self.fullFeatures == true {
                return super.selectionRects(for: range)
            }

            return []
        }

        override func caretRect(for position: UITextPosition) -> CGRect {
            if self.fullFeatures == true {
                return super.caretRect(for: position)
            }
            // Force the caret to the end of the text
            guard let endPosition = self.position(from: endOfDocument, offset: 0) else {
                return super.caretRect(for: position)
            }
            return super.caretRect(for: endPosition)
        }
    }

    struct TextFieldContainer: UIViewRepresentable {
        private var placeholder: String
        private var text: Binding<String>
        private var onDelete: () -> Void
        private var onDone: () -> Void
        private var fullFeatures: Bool

        init(
            _ placeholder: String,
            text: Binding<String>,
            onDelete: @escaping () -> Void,
            onDone: @escaping () -> Void,
            fullFeatures: Bool
        ) {
            self.placeholder = placeholder
            self.text = text
            self.onDelete = onDelete
            self.onDone = onDone
            self.fullFeatures = fullFeatures
        }

        func makeCoordinator() -> TextFieldContainer.Coordinator {
            Coordinator(self)
        }

        func makeUIView(context: UIViewRepresentableContext<TextFieldContainer>) -> UITextField {
            let innertTextField = EndOnlyTextField(frame: .zero)
            innertTextField.placeholder = placeholder
            innertTextField.text = text.wrappedValue
            innertTextField.delegate = context.coordinator
            innertTextField.didDelete = onDelete
            innertTextField.fullFeatures = fullFeatures

            context.coordinator.setup(innertTextField)

            return innertTextField
        }

        func updateUIView(_ uiView: UITextField, context _: UIViewRepresentableContext<TextFieldContainer>) {
            uiView.text = text.wrappedValue
            if let uiViewEndOnlyTextField = uiView as? EndOnlyTextField {
                uiViewEndOnlyTextField.fullFeatures = fullFeatures
                uiViewEndOnlyTextField.didDelete = onDelete
            }
        }

        final class Coordinator: NSObject, UITextFieldDelegate {
            var parent: TextFieldContainer

            init(_ textFieldContainer: TextFieldContainer) {
                parent = textFieldContainer
            }

            func setup(_ textField: UITextField) {
                Log.userInteraction.debug("Getting setup")
                textField.addTarget(self, action: #selector(textFieldDidChange), for: .allEditingEvents)
                textField.becomeFirstResponder()
            }

            #if !os(iOS)
                @objc func textFieldDidEndEditing(_: UITextField) {
                    parent.onDone()
                }
            #endif
            @objc func textFieldShouldReturn(_: UITextField) -> Bool {
                parent.onDone()
                return true
            }

            func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
                let maxLength = globalMaxLengthChars
                let currentString = (textField.text ?? "") as NSString
                let newString = currentString.replacingCharacters(in: range, with: string)

                return newString.count <= maxLength
            }

            @objc func textFieldDidChange(_ textField: UITextField) {
                parent.text.wrappedValue = textField.text ?? ""

                if parent.fullFeatures == true {
                    return
                }

                let newPosition = textField.endOfDocument
                textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
            }
        }
    }

    @MainActor
    final class KeyboardListener {
        var observerTokens: [Any] = []

        var keyboardHideNotifier: (() -> Void)?
        var keyboardShowNotifier: (() -> Void)?

        func handleHideKeyboard() {
            keyboardHideNotifier?()
        }
        func handleShowKeyboard() {
            keyboardShowNotifier?()
        }

        func startListening() throws {
            Log.userInteraction.notice("Starting keyboard observations")
            // Get the default notification center instance.
            let t1 = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main,
                using: { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.handleHideKeyboard()
                    }
                }
            )
            let t2 = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main,
                using: { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.handleShowKeyboard()
                    }
                }
            )

            observerTokens.append(t1)
            observerTokens.append(t2)
        }

        func stopListening() {
            Log.userInteraction.notice("Stoping keyboard observations")
            self.keyboardShowNotifier = nil
            self.keyboardHideNotifier = nil
            let ot = self.observerTokens
            self.observerTokens = []
            for token in ot {
                NotificationCenter.default.removeObserver(token)
            }
        }

        var events: AsyncStream<Bool>? {
            AsyncStream { continuation in
                do {
                    self.keyboardShowNotifier = {
                        self.keyboardHideNotifier = {
                            continuation.yield(true)
                        }
                    }

                    try startListening()

                    continuation.onTermination = { @Sendable _ in
                        Task {
                            await self.stopListening()
                        }
                    }
                } catch {}
            }
        }
    }
#endif
