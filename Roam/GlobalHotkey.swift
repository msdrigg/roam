
// Install the key event handler
var pressedEventType = EventTypeSpec()
pressedEventType.eventClass = OSType(kEventClassKeyboard)
pressedEventType.eventKind = OSType(kEventHotKeyPressed)

InstallEventHandler(GetEventDispatcherTarget(), { _, inEvent, _ -> OSStatus in
    return handlePressedKeyboardEvent(inEvent!)
}, 1, &pressedEventType, nil, nil)


// Register the hotkey
let hotKeyId = EventHotKeyID(signature: UTGetOSTypeFromString("some-unique-identifier" as CFString), id: 0)
var carbonHotKey: EventHotKeyRef?

RegisterEventHotKey(UInt32(kVK_ANSI_R),
                    UInt32(cmdKey),
                    hotKeyId,
                    GetEventDispatcherTarget(),
                    0,
                    &carbonHotKey)

// Handle the event
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
    assert(hotKeyId.signature == UTGetOSTypeFromString("some-unique-identifier" as CFString), "Invalid hot key id")

    switch GetEventKind(event) {
    case EventParamName(kEventHotKeyPressed):
        // do your thing.. eventually
    default:
        assert(false, "Unknown event kind")
    }
    return noErr
}
