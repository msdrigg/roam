#if !os(macOS)
    import Foundation
    import Observation
    import os.log
    import SwiftUI

    let globalMaxLengthChars = 64

    private struct StrTransformation {
        let old: String
        let new: String
    }

    struct KeyboardEntry: View {
        @State var str: String = ""
        @State var strSent: String = ""
        @Binding var showing: Bool
        @FocusState private var keyboardFocused: Bool

        let queue = AsyncQueue()

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

        private func handleDelete() {
            Task {
                await onKeyPress(.delete)
            }
        }

        private func handleDone() {
            withAnimation {
                keyboardFocused = false
                showing = false
            }
        }

        private func scenePhaseTask() async {
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

        private func handleStringChange(_ str: String) {
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
                queue.async {
                    let charDifference = str.count - strSentNow.count

                    if charDifference > 0 {
                        let startIndex = str.index(str.endIndex, offsetBy: -charDifference)
                        let newChars = str[startIndex..<str.endIndex]

                        do {
                            try await withTimeout(delay: 2.0) {
                                for char in newChars.unicodeScalars {
                                    await onKeyPress(KeyEquivalent(Character(char)))
                                }
                            }
                        } catch {
                            Log.userInteraction.warning("Couldn't send kb input within 2s, or canccelled \(error, privacy: .public)")
                        }
                    }
                }
            }
            strSent = str
        }

        private func handleTexteditIdChange() {
            Log.userInteraction.notice("Text edit id changed to \(texteditId ?? "nil")")
            if texteditId != nil && (texteditText ?? "" != str) {
                str = texteditText ?? ""
            }
        }

        private func handleLeavingChange(_ leaving: Bool) {
            if leaving {
                withAnimation {
                    keyboardFocused = false
                    showing = false
                }
            } else {
                keyboardFocused = true
            }
        }

        private func handleAppear() {
            keyboardFocused = true
            if texteditId == nil {
                str = ""
                strSent = ""
            } else {
                str = texteditText ?? ""
                strSent = texteditText ?? ""
            }
        }

        var body: some View {
            HStack(spacing: 10) {
                TextFieldContainer(
                    String(localized: "Enter some text...", comment: "Placeholder for a text field"),
                    text: $str,
                    onDelete: handleDelete,
                    onDone: handleDone,
                    fullFeatures: texteditId != nil
                )
                .textSelection(.disabled)
                .focused($keyboardFocused)
                .font(.body)
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background(.regularMaterial, in: Capsule())
                .glassEffectIfSupported(in: Capsule())

                Button(action: handleDone) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .background(.regularMaterial, in: Circle())
                        .glassEffectIfSupported(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("CloseKeyboardButton")
                .accessibilityLabel(
                    String(
                        localized: "Close keyboard",
                        comment: "Accessibility label for the button that closes the keyboard text entry"
                    ))
            }
            .task(id: scenePhase) { await scenePhaseTask() }
            .onChange(of: str) { _, newStr in handleStringChange(newStr) }
            .onChange(of: texteditId) { handleTexteditIdChange() }
            .onChange(of: leaving) { _, newLeaving in handleLeavingChange(newLeaving) }
            .onAppear(perform: handleAppear)
        }
    }

    final class EndOnlyTextField: UITextField {
        var didDelete: (() -> Void)?
        var fullFeatures: Bool?
        // `becomeFirstResponder` is a no-op outside a window, which is where
        // the field is the first time the keyboard-following container
        // builds it.
        var focusesOnWindow = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, focusesOnWindow else { return }
            focusesOnWindow = false
            // Not from inside the commit that inserts the field: raising the
            // keyboard there starts UIKit layout in the middle of SwiftUI's
            // update.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.becomeFirstResponder()
            }
        }

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
                if textField.window == nil, let textField = textField as? EndOnlyTextField {
                    textField.focusesOnWindow = true
                } else {
                    textField.becomeFirstResponder()
                }
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

    #if os(iOS)
        /// Keeps its content above the docked keyboard. The remote ignores the
        /// keyboard safe area so it never reflows, which leaves this to read
        /// the keyboard's frame itself.
        struct KeyboardFollowingContainer<Content: View>: View {
            let content: Content

            var body: some View {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        content
                    }
                    .padding(.bottom, KeyboardFrameTracker.shared.inset(below: proxy.frame(in: .global).maxY))
                }
                .ignoresSafeArea(.all, edges: .bottom)
                .onAppear { KeyboardFrameTracker.shared.refresh() }
            }
        }

        /// The docked keyboard's top edge in key-window coordinates, which are
        /// SwiftUI's `.global` space. Observing starts on first use, which is
        /// before the entry's field exists, so the notification for the
        /// keyboard that field raises cannot be missed.
        @MainActor @Observable
        final class KeyboardFrameTracker {
            static let shared = KeyboardFrameTracker()

            private(set) var keyboardTop: CGFloat?
            private(set) var safeBottom: CGFloat?
            @ObservationIgnored private var observers: [any NSObjectProtocol] = []

            private struct Change: Sendable {
                let endFrame: CGRect
                let duration: Double
                let curve: Int
                let hiding: Bool
            }

            private init() {
                // Read here, on the main actor, so the observer closure below
                // captures only Sendable values.
                let hideName = UIResponder.keyboardWillHideNotification
                let frameKey = UIResponder.keyboardFrameEndUserInfoKey
                let durationKey = UIResponder.keyboardAnimationDurationUserInfoKey
                let curveKey = UIResponder.keyboardAnimationCurveUserInfoKey
                let names = [UIResponder.keyboardWillChangeFrameNotification, hideName]
                observers = names.map { name in
                    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                        let info = note.userInfo
                        let change = Change(
                            endFrame: (info?[frameKey] as? NSValue)?.cgRectValue ?? .zero,
                            duration: info?[durationKey] as? Double ?? 0,
                            curve: info?[curveKey] as? Int ?? 0,
                            hiding: note.name == hideName
                        )
                        MainActor.assumeIsolated {
                            KeyboardFrameTracker.shared.apply(change)
                        }
                    }
                }
                refresh()
            }

            /// How far content ending at `maxY` must rise to clear the docked
            /// keyboard, or the home indicator while none is docked.
            func inset(below maxY: CGFloat) -> CGFloat {
                let edge = min(keyboardTop ?? .greatestFiniteMagnitude, safeBottom ?? maxY)
                return max(0, maxY - edge)
            }

            func refresh() {
                guard let window = Self.keyWindow() else { return }
                safeBottom = window.bounds.maxY - window.safeAreaInsets.bottom
            }

            private func apply(_ change: Change) {
                guard let window = Self.keyWindow(), let screen = window.windowScene?.screen else { return }
                let frame = window.convert(change.endFrame, from: screen.coordinateSpace)
                let bottom = window.bounds.maxY
                // Floating and split keyboards stop short of the bottom edge,
                // so the entry stays at the bottom rather than chasing them.
                let docked = !change.hiding && !frame.isEmpty && frame.maxY >= bottom - 1 && frame.minY < bottom
                let top = docked ? frame.minY : nil
                let safe = bottom - window.safeAreaInsets.bottom
                guard top != keyboardTop || safe != safeBottom else { return }
                withAnimation(Self.animation(for: change)) {
                    keyboardTop = top
                    safeBottom = safe
                }
            }

            /// UIKit animates the keyboard with private curve 7. The bezier is
            /// an approximation of it, run over the duration UIKit reports.
            private static func animation(for change: Change) -> Animation? {
                guard change.duration > 0 else { return nil }
                if change.curve == 7 {
                    return .timingCurve(0.38, 0.7, 0.125, 1, duration: change.duration)
                }
                return .easeInOut(duration: change.duration)
            }

            private static func keyWindow() -> UIWindow? {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .first(where: \.isKeyWindow)
            }
        }
    #endif

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
