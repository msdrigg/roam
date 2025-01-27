import Foundation
import SwiftUI
import OSLog
import TipKit

private let logger = Logger(subsystem: getLogSubsystem(), category: "KeyboardShortcut")

struct CustomKeyboardShortcut: Identifiable, Codable, Equatable {
    let title: CustomKeyboardShortcut.Key
    let key: KeyEquivalent?
    let modifiers: EventModifiers
    var id: String {
        title.rawValue
    }

    init(title: CustomKeyboardShortcut.Key, key: KeyEquivalent?, modifiers: EventModifiers) {
        self.title = title
        self.key = key
        self.modifiers = modifiers
    }

    #if !os(tvOS)
    init(title: CustomKeyboardShortcut.Key, shortcut: KeyboardShortcut) {
        self.title = title
        self.key = shortcut.key
        self.modifiers = shortcut.modifiers
    }
    #endif

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(CustomKeyboardShortcut.Key.self, forKey: .title)
        key = try? container.decode(KeyEquivalent.self, forKey: .key)
        let modifiersRawValue = try container.decode(Int.self, forKey: .modifiers)
        modifiers = EventModifiers(rawValue: modifiersRawValue)
    }

    var keys: String {
        var keyBuilder: String = ""
        if key == nil {
            return ""
        }
        for pair in [(EventModifiers.command, "⌘"), (EventModifiers.shift, "⇧"), (EventModifiers.control, "^"), (EventModifiers.option, "⌥")] where modifiers.contains(pair.0) {
            keyBuilder.append(pair.1)
            keyBuilder.append(" ")
        }
        if let key {
            keyBuilder.append(key.printableRepresentation)
        }
        return keyBuilder
    }

    #if !os(tvOS)
    @MainActor
    static var defaults: [Key: KeyboardShortcut]  {
        var items: [Key: KeyboardShortcut] = [:]
        #if !os(macOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            items = [
                .back: KeyboardShortcut(.leftArrow, modifiers: .command),
                .power: KeyboardShortcut(.return, modifiers: .command),
                .volumeDown: KeyboardShortcut(.downArrow, modifiers: .command),
                .volumeUp: KeyboardShortcut(.upArrow, modifiers: .command),
                .mute: KeyboardShortcut(KeyEquivalent("m"), modifiers: .command),
                .home: KeyboardShortcut(KeyEquivalent("h"), modifiers: [.command, .shift]),
                .playPause: KeyboardShortcut(KeyEquivalent("p"), modifiers: .command),
                .ok: KeyboardShortcut(.return, modifiers: .command),
                .left: KeyboardShortcut(.leftArrow, modifiers: .command),
                .right: KeyboardShortcut(.rightArrow, modifiers: .command),
                .up: KeyboardShortcut(.upArrow, modifiers: .command),
                .down: KeyboardShortcut(.downArrow, modifiers: .command),
                .keyboardShortcuts: KeyboardShortcut(KeyEquivalent("k"), modifiers: .command),
                .chatWithDeveloper: KeyboardShortcut(KeyEquivalent("j"), modifiers: .command),
                .paste: KeyboardShortcut(KeyEquivalent("v"), modifiers: .command),
                .cut: KeyboardShortcut(KeyEquivalent("x"), modifiers: .command),
                .copy: KeyboardShortcut(KeyEquivalent("c"), modifiers: .command)
            ]
        } else {
            items = [
                .back: KeyboardShortcut(.leftArrow, modifiers: .command),
                .power: KeyboardShortcut(.return, modifiers: .command),
                .volumeDown: KeyboardShortcut(.downArrow, modifiers: .command),
                .volumeUp: KeyboardShortcut(.upArrow, modifiers: .command),
                .mute: KeyboardShortcut(KeyEquivalent("m"), modifiers: .command),
                .home: KeyboardShortcut(KeyEquivalent("h"), modifiers: [.command, .shift]),
                .playPause: KeyboardShortcut(KeyEquivalent("p"), modifiers: .command),
                .ok: KeyboardShortcut(.return, modifiers: .shift),
                .left: KeyboardShortcut(.leftArrow, modifiers: []),
                .right: KeyboardShortcut(.rightArrow, modifiers: []),
                .up: KeyboardShortcut(.upArrow, modifiers: []),
                .down: KeyboardShortcut(.downArrow, modifiers: []),
                .keyboardShortcuts: KeyboardShortcut(KeyEquivalent("k"), modifiers: .command),
                .chatWithDeveloper: KeyboardShortcut(KeyEquivalent("j"), modifiers: .command),
                .paste: KeyboardShortcut(KeyEquivalent("v"), modifiers: .command),
                .cut: KeyboardShortcut(KeyEquivalent("x"), modifiers: .command),
                .copy: KeyboardShortcut(KeyEquivalent("c"), modifiers: .command)
            ]
        }
        #else
        items = [
            .back: KeyboardShortcut(.leftArrow, modifiers: .command),
            .power: KeyboardShortcut(.return, modifiers: .command),
            .volumeDown: KeyboardShortcut(.downArrow, modifiers: .command),
            .volumeUp: KeyboardShortcut(.upArrow, modifiers: .command),
            .mute: KeyboardShortcut(KeyEquivalent("m"), modifiers: .command),
            .home: KeyboardShortcut(KeyEquivalent("h"), modifiers: [.command]),
            .playPause: KeyboardShortcut(KeyEquivalent("p"), modifiers: .command),
            .ok: KeyboardShortcut(.return, modifiers: .command),
            .left: KeyboardShortcut(.leftArrow, modifiers: .command),
            .right: KeyboardShortcut(.rightArrow, modifiers: .command),
            .up: KeyboardShortcut(.upArrow, modifiers: .command),
            .down: KeyboardShortcut(.downArrow, modifiers: .command),
            .paste: KeyboardShortcut(KeyEquivalent("v"), modifiers: .command),
            .cut: KeyboardShortcut(KeyEquivalent("x"), modifiers: .command),
            .copy: KeyboardShortcut(KeyEquivalent("c"), modifiers: .command),
            .keyboardShortcuts: KeyboardShortcut(KeyEquivalent("k"), modifiers: .command),
            .chatWithDeveloper: KeyboardShortcut(KeyEquivalent("j"), modifiers: .command)
        ]
        #endif

        return items
    }
    #endif

    enum CodingKeys: String, CodingKey {
        case title
        case key
        case modifiers
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(key, forKey: .key)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }

    func persist() {
        logger.notice("Saving shortcut with title \(self.title.rawValue, privacy: .public) key \(keys, privacy: .public)")
        do {
            let data = try PropertyListEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: "keyboard-shortcut-\(title)")
        } catch {
            logger.error("Error encoding keyboard shortcut to string \(error, privacy: .public)")
        }
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: "keyboard-shortcut-\(title)")
    }

    #if !os(tvOS)
    @MainActor
    init(title: Key) {
        if let data = UserDefaults.standard.data(forKey: "keyboard-shortcut-\(title)"),
           let shortcut = try? PropertyListDecoder().decode(Self.self, from: data) {
            self = shortcut
        } else if let defaultShortcut = Self.defaults[title] {
            self = Self(title: title, shortcut: defaultShortcut)
        } else {
            self.title = title
            self.key = nil
            self.modifiers = .command
        }
    }
    #endif

    public enum Key: String, CaseIterable, Codable, CustomStringConvertible {
        case back = "Back"
        case power = "Power"
        case home = "Home"
        case volumeDown = "Volume Down"
        case volumeUp = "Volume Up"
        case mute = "Mute"
        case playPause = "Play/Pause"
        case ok = "Ok"
        case left = "Left"
        case right = "Right"
        case up = "Up"
        case down = "Down"
        case keyboardShortcuts = "Keyboard Shortcuts"
        case chatWithDeveloper = "Chat with the Developer"
        case options = "Options"
        case headphonesMode = "Headphones Mode"
        case instantReplay = "Instant Replay"
        case fastForward = "Fast Forward"
        case rewind = "Rewind"
        case paste = "Paste"
        case copy = "Copy"
        case cut = ""

        var defaultsKey: String {
            return "keyboard-shortcut-\(rawValue)"
        }

        public static let caseDisplayRepresentations: [Self: String] = [
            .back: String(localized: "Back", comment: "Keyboard shortcut to go back"),
            .power: String(localized: "Power", comment: "Keyboard shortcut to power on/off the TV"),
            .home: String(localized: "Home", comment: "Keyboard shortcut to go to the home screen"),
            .volumeDown: String(localized: "Volume Down", comment: "Keyboard shortcut to turn the volume down"),
            .volumeUp: String(localized: "Volume Up", comment: "Keyboard shortcut to turn the volume up"),
            .mute: String(localized: "Mute", comment: "Keyboard shortcut to mute/unmute the TV"),
            .playPause: String(localized: "Play/Pause", comment: "Keyboard shortcut to Play/Pause the TV"),
            .ok: String(localized: "Ok", comment: "Keyboard shortcut to Select/Enter"),
            .left: String(localized: "Left", comment: "Keyboard shortcut to move left"),
            .right: String(localized: "Right", comment: "Keyboard shortcut to move right"),
            .up: String(localized: "Up", comment: "Keyboard shortcut to move up"),
            .down: String(localized: "Down", comment: "Keyboard shortcut to move down"),
            .keyboardShortcuts: String(localized: "Keyboard Shortcuts", comment: "Keyboard shortcut to open the keyboard shortcut panel"),
            .chatWithDeveloper: String(localized: "Chat with the Developer", comment: "Keyboard shortcut to open the chat window"),
            .options: String(localized: "Options", comment: "Keyboard shortcut to open the options menu"),
            .headphonesMode: String(localized: "Headphones Mode", comment: "Keyboard shortcut to toggle headphones mode"),
            .instantReplay: String(localized: "Instant Replay", comment: "Keyboard shortcut to instant replay"),
            .fastForward: String(localized: "Fast Forward", comment: "Keyboard shortcut to fast forward"),
            .rewind: String(localized: "Rewind", comment: "Keyboard shortcut to rewind"),
            .paste: String(localized: "Paste", comment: "Keyboard shortcut to paste"),
            .cut: String(localized: "Cut", comment: "Keyboard shortcut to cut"),
            .copy: String(localized: "Copy", comment: "Keyboard shortcut to copy")
        ]

        public var description: String {
            return Key.caseDisplayRepresentations[self] ?? rawValue
        }

        public init?(remoteButton: RemoteButton) {
            switch remoteButton {
            case .back:
                self = .back
            case .power:
                self = .power
            case .home:
                self = .home
            case .volumeDown:
                self = .volumeDown
            case .volumeUp:
                self = .volumeUp
            case .mute:
                self = .mute
            case .playPause:
                self = .playPause
            case .select:
                self = .ok
            case .left:
                self = .left
            case .right:
                self = .right
            case .up:
                self = .up
            case .down:
                self = .down
            case .options:
                self = .options
            case .headphonesMode:
                self = .headphonesMode
            case .instantReplay:
                self = .instantReplay
            case .fastForward:
                self = .fastForward
            case .rewind:
                self = .rewind
            default:
                return nil
            }
        }

        public var matchingRemoteButton: RemoteButton? {
            switch self {
            case .back:
                return .back
            case .power:
                return .power
            case .home:
                return .home
            case .volumeDown:
                return .volumeDown
            case .volumeUp:
                return .volumeUp
            case .mute:
                return .mute
            case .playPause:
                return .playPause
            case .ok:
                return .select
            case .left:
                return .left
            case .right:
                return .right
            case .up:
                return .up
            case .down:
                return .down
            case .keyboardShortcuts, .paste, .chatWithDeveloper, .cut, .copy:
                return nil
            case .options:
                return .options
            case .headphonesMode:
                return .headphonesMode
            case .instantReplay:
                return .instantReplay
            case .fastForward:
                return .fastForward
            case .rewind:
                return .rewind
            }
        }
    }

#if !os(macOS)
    @MainActor
    public func getUIKeyCommand(action: Selector) -> UIKeyCommand? {
        guard let key = self.key else {
            return nil
        }
        let input: String?

        switch key {
        case .upArrow:
            input = UIKeyCommand.inputUpArrow
        case .downArrow:
            input = UIKeyCommand.inputDownArrow
        case .leftArrow:
            input = UIKeyCommand.inputLeftArrow
        case .rightArrow:
            input = UIKeyCommand.inputRightArrow
        case .escape:
            input = UIKeyCommand.inputEscape
        case .home:
            input = UIKeyCommand.inputHome
        case .end:
            input = UIKeyCommand.inputEnd
        case .pageUp:
            input = UIKeyCommand.inputPageUp
        case .pageDown:
            input = UIKeyCommand.inputPageDown
        case .tab:
            input = "\t"
        case .return:
            input = "\r"
        case .delete:
            input = UIKeyCommand.inputDelete
        default:
            input = String(key.character)
        }
        guard let input else {
            return nil
        }

        let command = UIKeyCommand(input: input, modifierFlags: self.modifiers.uiKeyModifierFlagsRepresentation, action: action)
        command.discoverabilityTitle = title.rawValue
        command.title = title.rawValue
        command.wantsPriorityOverSystemBehavior = true

        return command
    }
#endif
}

extension KeyEquivalent: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let character = value.first else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid key equivalent")
        }
        self = KeyEquivalent(character)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(self.character))
    }
}

extension EventModifiers {
    var isEmpty: Bool {
        return !self.contains(.shift) && !self.contains(.command) && !self.contains(.control) && !self.contains(.option)
    }
}

extension KeyEquivalent {
    var isPrintableCharacter: Bool {
        let unprintableCharacters: Set<KeyEquivalent> = [
            .delete, .escape, .return,
            .leftArrow, .rightArrow, .upArrow, .downArrow,
            .home, .end, .pageUp, .pageDown
        ]

        return !unprintableCharacters.contains(self)
    }

    @MainActor
    var isNavigationCharacter: Bool {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            let navChars: Set<KeyEquivalent> = [
                .escape, .tab, .leftArrow, .rightArrow, .upArrow, .downArrow,
            ]

            return navChars.contains(self)
        } else {
            let navChars: Set<KeyEquivalent> = [
                .escape
            ]

            return navChars.contains(self)
        }
        #else
        return false
        #endif
    }

    var printableRepresentation: String {
        switch self {
        case " ", .space:
            return String(localized: "Space", comment: "A visual representation of the \" \" key")
        case .return:
            return "⏎"
        case .tab:
            return "⇥"
        case .delete:
            return "⌫"
        case .escape:
            return "⎋"
        case .leftArrow:
            return "←"
        case .rightArrow:
            return "→"
        case .upArrow:
            return "↑"
        case .downArrow:
            return "↓"
        case .home:
            return "↖"
        case .end:
            return "↘"
        case .pageUp:
            return "⇞"
        case .pageDown:
            return "⇟"
        default:
            break
        }

        if self.character.isLetter {
            return String(self.character).uppercased()
        }
        return String(self.character).lowercased()
    }
}

extension EventModifiers: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        self = EventModifiers(rawValue: rawValue)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

#if !os(tvOS)
extension View {
    func customKeyboardShortcut(_ title: CustomKeyboardShortcut.Key) -> some View {
        modifier(CustomKeyboardShortcutModifier(title: title))
    }
}

struct CustomKeyboardShortcutModifier: ViewModifier {
    @KeyboardShortcutStorage var shortcut: CustomKeyboardShortcut?

    init(title: CustomKeyboardShortcut.Key, defaultShortcut: CustomKeyboardShortcut? = nil) {
        self._shortcut = KeyboardShortcutStorage(title)
    }

    func body(content: Content) -> some View {
        if let key = shortcut?.key?.character.lowercased().first, let modifiers = shortcut?.modifiers {
            #if os(macOS)
            return AnyView(content.keyboardShortcut(KeyboardShortcut(KeyEquivalent(key), modifiers: modifiers)))
            #else
            return AnyView(content)
            #endif
        } else {
            return AnyView(content)
        }
    }
}

@propertyWrapper
@MainActor
struct KeyboardShortcutStorage: DynamicProperty {
    private let title: CustomKeyboardShortcut.Key
    @AppStorage var data: Data?

    var wrappedValue: CustomKeyboardShortcut? {
        get {
            if let data = data {
                if let sc = try? PropertyListDecoder().decode(CustomKeyboardShortcut.self, from: data) {
                    return sc
                }
            }
            if let sc = CustomKeyboardShortcut.defaults[title] {
                return CustomKeyboardShortcut(title: title, shortcut: sc)
            }
            return nil
        }
        nonmutating set {
            if let newValue = newValue {
                data = try? PropertyListEncoder().encode(newValue)
            } else {
                data = nil
            }
        }
    }

    var projectedValue: Binding<CustomKeyboardShortcut?> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0 }
        )
    }

    init(_ title: CustomKeyboardShortcut.Key) {
        self.title = title
        self._data = AppStorage("keyboard-shortcut-\(title)")
    }
}

@propertyWrapper
struct AllCustomKeyboardShortcuts: DynamicProperty {
    @KeyboardShortcutStorage(.back) private var backShortcut
    @KeyboardShortcutStorage(.power) private var powerShortcut
    @KeyboardShortcutStorage(.home) private var homeShortcut
    @KeyboardShortcutStorage(.volumeDown) private var volumeDownShortcut
    @KeyboardShortcutStorage(.volumeUp) private var volumeUpShortcut
    @KeyboardShortcutStorage(.mute) private var muteShortcut
    @KeyboardShortcutStorage(.playPause) private var playPauseShortcut
    @KeyboardShortcutStorage(.ok) private var okShortcut
    @KeyboardShortcutStorage(.left) private var leftShortcut
    @KeyboardShortcutStorage(.right) private var rightShortcut
    @KeyboardShortcutStorage(.up) private var upShortcut
    @KeyboardShortcutStorage(.down) private var downShortcut
    @KeyboardShortcutStorage(.keyboardShortcuts) private var keyboardShortcutsShortcut
    @KeyboardShortcutStorage(.chatWithDeveloper) private var chatWithDeveloperShortcut
    @KeyboardShortcutStorage(.paste) private var pasteShortcut
    @KeyboardShortcutStorage(.cut) private var cutShortcut
    @KeyboardShortcutStorage(.copy) private var copyShortcut
    @KeyboardShortcutStorage(.options) private var optionsShortcut
    @KeyboardShortcutStorage(.headphonesMode) private var headphonesModeShortcut
    @KeyboardShortcutStorage(.instantReplay) private var instantReplayShortcut
    @KeyboardShortcutStorage(.fastForward) private var fastForwardShortcut
    @KeyboardShortcutStorage(.rewind) private var rewindShortcut

    var wrappedValue: [CustomKeyboardShortcut] {
        [
            backShortcut,
            powerShortcut,
            homeShortcut,
            volumeDownShortcut,
            volumeUpShortcut,
            muteShortcut,
            playPauseShortcut,
            okShortcut,
            leftShortcut,
            rightShortcut,
            upShortcut,
            downShortcut,
            keyboardShortcutsShortcut,
            chatWithDeveloperShortcut,
            optionsShortcut,
            headphonesModeShortcut,
            instantReplayShortcut,
            fastForwardShortcut,
            rewindShortcut,
            pasteShortcut,
            copyShortcut,
            cutShortcut
        ]
            .compactMap { $0 }
    }

    var projectedValue: Binding<[CustomKeyboardShortcut]> {
        Binding(
            get: {
                [
                    backShortcut,
                    powerShortcut,
                    homeShortcut,
                    volumeDownShortcut,
                    volumeUpShortcut,
                    muteShortcut,
                    playPauseShortcut,
                    okShortcut,
                    leftShortcut,
                    rightShortcut,
                    upShortcut,
                    downShortcut,
                    keyboardShortcutsShortcut,
                    chatWithDeveloperShortcut,
                    optionsShortcut,
                    headphonesModeShortcut,
                    instantReplayShortcut,
                    fastForwardShortcut,
                    rewindShortcut,
                    pasteShortcut,
                    cutShortcut,
                    copyShortcut
                ].compactMap { $0 }
            },
            set: { newShortcuts in
                for shortcut in newShortcuts {
                    switch shortcut.title {
                    case .back: backShortcut = shortcut
                    case .power: powerShortcut = shortcut
                    case .home: homeShortcut = shortcut
                    case .volumeDown: volumeDownShortcut = shortcut
                    case .volumeUp: volumeUpShortcut = shortcut
                    case .mute: muteShortcut = shortcut
                    case .playPause: playPauseShortcut = shortcut
                    case .ok: okShortcut = shortcut
                    case .left: leftShortcut = shortcut
                    case .right: rightShortcut = shortcut
                    case .up: upShortcut = shortcut
                    case .down: downShortcut = shortcut
                    case .keyboardShortcuts: keyboardShortcutsShortcut = shortcut
                    case .chatWithDeveloper: chatWithDeveloperShortcut = shortcut
                    case .options: optionsShortcut = shortcut
                    case .headphonesMode: headphonesModeShortcut = shortcut
                    case .instantReplay: instantReplayShortcut = shortcut
                    case .fastForward: fastForwardShortcut = shortcut
                    case .rewind: rewindShortcut = shortcut
                    case .paste: pasteShortcut = shortcut
                    case .cut: cutShortcut = shortcut
                    case .copy: copyShortcut = shortcut
                    }
                }
            }
        )
    }
}

struct ShortcutDisplay: View {
    @KeyboardShortcutStorage var shortcut: CustomKeyboardShortcut?
    let title: CustomKeyboardShortcut.Key

    #if os(iOS)
    @MainActor
    private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    #endif

    init(_ title: CustomKeyboardShortcut.Key) {
        self.title = title
        self._shortcut = KeyboardShortcutStorage(title)
    }

    @ViewBuilder
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title.description)
                Spacer()
                if let keys = shortcut?.keys {
                    Text(keys)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }

#if os(iOS)
            if shortcut?.key?.isNavigationCharacter == true && shortcut?.modifiers.contains(.command) == false && idiom == .pad {
                if idiom == .pad {
                    // swiftlint:disable:next line_length
                    Text("Using this key as a keyboard shortcut without a command modifier (⌘) may not work on iPad if Full Keyboard Access is enabled. To disable Full Keyboard Access to into your iPad settings and navigate to Accessiblity -> Keyboard -> Full Keyboard Access", comment: "Warning indicator underneath a section")
                        .font(.caption)
                        .foregroundStyle(.yellow.opacity(0.6))
                } else {
                    // swiftlint:disable:next line_length
                    Text("Using this key as a keyboard shortcut without a command modifier (⌘) may not work because the operating system captures it first for in-app navigation", comment: "Warning indicator underneath a section")
                        .font(.caption)
                        .foregroundStyle(.yellow.opacity(0.6))

                }
            }
#endif
#if os(macOS)
            if shortcut?.key?.isPrintableCharacter == true && shortcut?.modifiers.contains(.command) == false {
                // swiftlint:disable:next line_length
                Text("Having letters, numbers, or punctuation as keyboard shortcuts without a command modifier (⌘) can interfere with keyboard text entry on the roku TV", comment: "Warning indicator underneath a section")
                    .font(.caption)
                    .foregroundStyle(.yellow.opacity(0.6))
            }
#endif
        }
    }
}

struct KeyboardShortcutPanel: View {
    var shortcuts: [CustomKeyboardShortcut] {
        return CustomKeyboardShortcut.Key.allCases.map{
            CustomKeyboardShortcut(title: $0)
        }
    }

    @State private var focusedShortcut: CustomKeyboardShortcut.Key?
    @Environment(\.openURL) var openURL

    @ViewBuilder
    var body: some View {
        Form {
#if os(macOS)
            TipView(GlobalKeyboardShortcutTip(), action: { _ in
                openURL(URL(string: "shortcuts://create-shortcut")!)
            })
#endif

#if os(macOS)
            Text("Click on a row below to change the shortcut, or right click it to reset", comment: "Caption on a keyboard shortcut panel")
                .foregroundStyle(.secondary)
                .swipeActions(edge: .trailing) {
                    Button(role: .cancel, action: {
                        for shortcut in shortcuts {
                            shortcut.reset()
                        }
                    }, label: {
                        Label(String(localized: "Reset All", comment: "Label on a button to reset keyboard shortcuts"), systemImage: "arrow.uturn.backward")
                    })
                    Button(role: .cancel, action: {
                        for shortcut in shortcuts {
                            let scClone = CustomKeyboardShortcut(title: shortcut.title, key: nil, modifiers: [])
                            scClone.persist()

                        }
                    }, label: {
                        Label(String(localized: "Clear All", comment: "Label on a button to clear keyboard shortcuts"), systemImage: "xmark")
                    })

                }
                .contextMenu {
                    Button(role: .cancel, action: {
                        for shortcut in shortcuts {
                            shortcut.reset()
                        }
                    }, label: {
                        Label(String(localized: "Reset All", comment: "Label on a button to reset keyboard shortcuts"), systemImage: "arrow.uturn.backward")
                    })
                    Button(role: .cancel, action: {
                        for shortcut in shortcuts {
                            let scClone = CustomKeyboardShortcut(title: shortcut.title, key: nil, modifiers: [])
                            scClone.persist()
                        }
                    }, label: {
                        Label(String(localized: "Clear All", comment: "Label on a button to clear keyboard shortcuts"), systemImage: "xmark")
                    })
                }
#else
            Text("Tap a row below to change the shortcut, or swipe to reset", comment: "Caption on a keyboard shortcut panel")
                .foregroundStyle(.secondary)
#if !os(tvOS)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .cancel, action: {
                        for shortcut in shortcuts {
                            shortcut.reset()
                        }
                    }, label: {
                        Label(String(localized: "Reset All", comment: "Label on a button to reset keyboard shortcuts"), systemImage: "arrow.uturn.backward")
                    })
                    Button(role: .cancel, action: {
                        for shortcut in shortcuts {
                            let scClone = CustomKeyboardShortcut(title: shortcut.title, key: nil, modifiers: [])
                            scClone.persist()

                        }
                    }, label: {
                        Label(String(localized: "Clear All", comment: "Label on a button to clear keyboard shortcuts"), systemImage: "xmark")
                    })

                }
#endif
                .contextMenu {
                    Button(role: .cancel, action: {
                        for shortcut in shortcuts {
                            shortcut.reset()
                        }
                    }, label: {
                        Label(String(localized: "Reset All", comment: "Label on a button to reset keyboard shortcuts"), systemImage: "arrow.uturn.backward")
                    })
                    Button(role: .cancel, action: {
                        for shortcut in shortcuts {
                            let scClone = CustomKeyboardShortcut(title: shortcut.title, key: nil, modifiers: [])
                            scClone.persist()

                        }
                    }, label: {
                        Label(String(localized: "Clear All", comment: "Label on a button to clear keyboard shortcuts"), systemImage: "xmark")
                    })

                }

#endif
            ForEach(shortcuts, id: \.id) { shortcut in
                Button(action: {
                    focusedShortcut = shortcut.title
                }, label: {
                    ShortcutDisplay(shortcut.title)
                        .padding(6)
                        .contentShape(RoundedRectangle(cornerRadius: 8.0))
                })
                .buttonStyle(.plain)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.secondary, lineWidth: 4)
                        .opacity(focusedShortcut == shortcut.title ? 1 : 0)
                        .scaleEffect(focusedShortcut == shortcut.title ? 1 : 1.04)
                        .animation(focusedShortcut == shortcut.title ? .easeIn(duration: 0.2) : .easeOut(duration: 0.0), value: focusedShortcut == shortcut.title)
                )
#if !os(tvOS)
                .swipeActions(edge: .trailing) {
                    Button(role: .cancel, action: {
                        shortcut.reset()
                    }, label: {
                        Label(String(localized: "Reset", comment: "Label on a button to reset a keyboard shortcut"), systemImage: "arrow.uturn.backward")
                    })
                    Button(role: .cancel, action: {
                        let scClone = CustomKeyboardShortcut(title: shortcut.title, key: nil, modifiers: [])
                        scClone.persist()
                    }, label: {
                        Label(String(localized: "Clear", comment: "Label on a button to clear a keyboard shortcut"), systemImage: "xmark")
                    })
                }
#endif
                .contextMenu {
                    Button(role: .cancel, action: {
                        shortcut.reset()
                    }, label: {
                        Label(String(localized: "Reset", comment: "Label on a button to reset a keyboard shortcut"), systemImage: "arrow.uturn.backward")
                    })
                    Button(role: .cancel, action: {
                        let scClone = CustomKeyboardShortcut(title: shortcut.title, key: nil, modifiers: [])
                        scClone.persist()
                    }, label: {
                        Label(String(localized: "Clear", comment: "Label on a button to clear a keyboard shortcut"), systemImage: "xmark")
                    })
                }
            }
        }
        .onAppear {
            logger.notice("Showing view")
        }
        .onDisappear {
            logger.notice("Closing view")
        }
        #if os(macOS)
        .onAppear {
            GlobalKeyboardShortcutTip.viewedKeyboardShortcuts.sendDonation()
        }
        .onKeyDown({ key in
            if let focusedShortcut {
                CustomKeyboardShortcut(title: focusedShortcut, shortcut: KeyboardShortcut(key.key, modifiers: key.modifiers)).persist()
            }
        }, captureShortcuts: true)
        #elseif !os(tvOS)
        .onKeyDown({ key in
            if let focusedShortcut {
                CustomKeyboardShortcut(title: focusedShortcut, shortcut: KeyboardShortcut(key.key, modifiers: key.modifiers)).persist()
            }
        })
        #endif
        .formStyle(.grouped)
        .navigationTitle("Keyboard Shortcuts")
        #if os(macOS)
                .frame(maxWidth: 500)
        #endif
    }
}

#Preview {
    KeyboardShortcutPanel()
}
#endif
