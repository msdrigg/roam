#if os(macOS)
import Carbon
import SwiftUI
import AppKit
import OSLog

private let osTypeBit: Int32 = 1349179263

enum HotkeyError: Error, LocalizedError {
    case invalidCharacter
    case hotkeyNotSet
    case invalidHotkeyRef
    case registerFailed(OSStatus)
}

@MainActor
func uninstallCarbonHandler(_ ref: Any) throws {
    guard let hotkeyRef = ref as? EventHotKeyRef else {
        throw HotkeyError.invalidHotkeyRef
    }

    let status = UnregisterEventHotKey(hotkeyRef)
    if status != 0 {
        throw HotkeyError.registerFailed(status)
    }
}

@MainActor
func installCarbonHandler(key: KeyEquivalent, modifiers: SwiftUICore.EventModifiers) throws -> EventHotKeyRef {
    guard let ansiKey = key.carbonAnsiKey else {
        Log.userInteraction.warning("Trying to setup a Carbon key handler with invalid parameters")
        throw HotkeyError.invalidCharacter
    }
    var pressedEventType = EventTypeSpec()
    pressedEventType.eventClass = OSType(kEventClassKeyboard)
    pressedEventType.eventKind = OSType(kEventHotKeyPressed)

    InstallEventHandler(GetEventDispatcherTarget(), { _, inEvent, _ -> OSStatus in
        return handlePressedKeyboardEvent(inEvent!)
    }, 1, &pressedEventType, nil, nil)

    // Register the hotkey
    let hotKeyId = EventHotKeyID(signature: OSType(bitPattern: osTypeBit), id: 0)
    var carbonHotKey: EventHotKeyRef?

    let result = RegisterEventHotKey(
        UInt32(ansiKey),
        modifiers.carbonModifiers,
        hotKeyId,
        GetEventDispatcherTarget(),
        0,
        &carbonHotKey
    )

    if result != 0 {
        throw HotkeyError.registerFailed(result)
    }

    guard let carbonHotKey else {
        throw HotkeyError.hotkeyNotSet
    }

    return carbonHotKey
}

private extension KeyEquivalent {
    var carbonAnsiKey: Int? {
        switch self.character {
        case "a": return kVK_ANSI_A
        case "b": return kVK_ANSI_B
        case "c": return kVK_ANSI_C
        case "d": return kVK_ANSI_D
        case "e": return kVK_ANSI_E
        case "f": return kVK_ANSI_F
        case "g": return kVK_ANSI_G
        case "h": return kVK_ANSI_H
        case "i": return kVK_ANSI_I
        case "j": return kVK_ANSI_J
        case "k": return kVK_ANSI_K
        case "l": return kVK_ANSI_L
        case "m": return kVK_ANSI_M
        case "n": return kVK_ANSI_N
        case "o": return kVK_ANSI_O
        case "p": return kVK_ANSI_P
        case "q": return kVK_ANSI_Q
        case "r": return kVK_ANSI_R
        case "s": return kVK_ANSI_S
        case "t": return kVK_ANSI_T
        case "u": return kVK_ANSI_U
        case "v": return kVK_ANSI_V
        case "w": return kVK_ANSI_W
        case "x": return kVK_ANSI_X
        case "y": return kVK_ANSI_Y
        case "z": return kVK_ANSI_Z
        case "0": return kVK_ANSI_0
        case "1": return kVK_ANSI_1
        case "2": return kVK_ANSI_2
        case "3": return kVK_ANSI_3
        case "4": return kVK_ANSI_4
        case "5": return kVK_ANSI_5
        case "6": return kVK_ANSI_6
        case "7": return kVK_ANSI_7
        case "8": return kVK_ANSI_8
        case "9": return kVK_ANSI_9
        case "=": return kVK_ANSI_Equal
        case "-": return kVK_ANSI_Minus
        case "[": return kVK_ANSI_LeftBracket
        case "]": return kVK_ANSI_RightBracket
        case ";": return kVK_ANSI_Semicolon
        case "'": return kVK_ANSI_Quote
        case ",": return kVK_ANSI_Comma
        case ".": return kVK_ANSI_Period
        case "/": return kVK_ANSI_Slash
        case "\\": return kVK_ANSI_Backslash
        case "`": return kVK_ANSI_Grave
        case " ": return kVK_Space
        case "\t": return kVK_Tab
        case "\n": return kVK_Return
        case "\r": return kVK_Return
        case "\u{7F}": return kVK_Delete
        default: break
        }
        switch self {
        case KeyEquivalent.delete: return kVK_Delete
        case KeyEquivalent.deleteForward: return kVK_ForwardDelete
        case KeyEquivalent.escape: return kVK_Escape
        case KeyEquivalent.downArrow: return kVK_DownArrow
        case KeyEquivalent.upArrow: return kVK_UpArrow
        case KeyEquivalent.rightArrow: return kVK_RightArrow
        case KeyEquivalent.leftArrow: return kVK_LeftArrow
        case KeyEquivalent.home: return kVK_Home
        case KeyEquivalent.return: return kVK_Return
        default: return nil
        }
    }
}

private extension SwiftUICore.EventModifiers {
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        result |= contains(.command) ? UInt32(cmdKey) : 0
        result |= contains(.option) ? UInt32(optionKey) : 0
        result |= contains(.control) ? UInt32(controlKey) : 0
        result |= contains(.shift) ? UInt32(shiftKey) : 0

        return result
    }
}

func handlePressedKeyboardEvent(_ event: EventRef) -> OSStatus {
    assert(Int(GetEventClass(event)) == kEventClassKeyboard, "Unknown event class")

    var hotKeyId = EventHotKeyID()
    let error = GetEventParameter(event,
                                  EventParamName(kEventParamDirectObject),
                                  EventParamName(typeEventHotKeyID),
                                  nil,
                                  MemoryLayout<EventHotKeyID>.size,
                                  nil,
                                  &hotKeyId)

    guard error == noErr else { return error }
    assert(hotKeyId.signature == OSType(bitPattern: osTypeBit), "Invalid hot key id")

    switch GetEventKind(event) {
    case EventParamName(kEventHotKeyPressed):
        DispatchQueue.main.async {
            if NSApp.activationPolicy() == .regular {
                NSApp.forceFront("main")
            } else {
                if let popoverWindow = NSApp.windows.first(where: {$0.level == .popUpMenu}), popoverWindow.isVisible {
                    Log.userInteraction.notice("Not opening up from hotkey bc popover is already visible")
                    return
                }
                if let menuBarWindow = NSApp.windows.first(where: {$0.level == .statusBar}) ?? NSApp.windows.first,
                   let statusItem = menuBarWindow.value(forKey: "statusItem") as? NSStatusItem,
                   let button = statusItem.button {
                    Log.userInteraction.notice("Performing click on menubar button")
                    button.performClick(nil)
                } else {
                    Log.userInteraction.warning("No status button found for window. Global hot key not working. Switching to main")
                    NSApp.setActivationPolicy(.regular)
                    NSApp.forceFront("main")
                }
            }
        }
    default:
        assert(false, "Unknown event kind")
    }
    return noErr
}
#endif
