import AppIntents

@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
struct RoamAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenDeviceIntent(),
            phrases: [
                "Open \(\.$target) with \(.applicationName)",
                "Show \(\.$target) on \(.applicationName)",
                "Open \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Open", comment: "Siri shortcut to open a device"),
            systemImageName: "tv"
        )
        AppShortcut(
            intent: PlayIntent(),
            phrases: [
                "Press play with \(.applicationName)",
                "Press play on \(\.$device) with \(.applicationName)",
                "Press pause with \(.applicationName)",
                "Press pause on \(\.$device) with \(.applicationName)",
                "Play with \(.applicationName)",
                "Play \(\.$device) with \(.applicationName)",
                "Pause with \(.applicationName)",
                "Pause \(\.$device) with \(.applicationName)",
                "Pause the TV with \(.applicationName)",
                "Play the TV with \(.applicationName)",
                "Unpause the TV with \(.applicationName)",
                "Unpause with \(.applicationName)",
                "Unpause \(\.$device) with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Play/Pause", comment: "Siri shortcut to play/pause"),
            systemImageName: "playpause"
        )
        AppShortcut(
            intent: PowerIntent(),
            phrases: [
                "Press power with \(.applicationName)",
                "Press power on \(\.$device) with \(.applicationName)",
                "Turn off with \(.applicationName)",
                "Turn off \(\.$device) with \(.applicationName)",
                "Turn on with \(.applicationName)",
                "Turn on \(\.$device) with \(.applicationName)",
                "Turn on the TV with \(.applicationName)",
                "Turn off the TV with \(.applicationName)",
                "Shutdown the TV with \(.applicationName)",
                "Shutdown \(\.$device) with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Power", comment: "Siri shortcut to power on/off the device"),
            systemImageName: "power"
        )
        AppShortcut(
            intent: MuteIntent(),
            phrases: [
                "Press mute with \(.applicationName)",
                "Press mute on \(\.$device) with \(.applicationName)",
                "Mute with \(.applicationName)",
                "Mute \(\.$device) with \(.applicationName)",
                "Unmute \(.applicationName)",
                "Unmute \(\.$device) with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Mute/Unmute", comment: "Siri shortcut to mute/unmute the device"),
            systemImageName: "speaker.slash"
        )
        AppShortcut(
            intent: VolumeDownIntent(),
            phrases: [
                "Volume down with \(.applicationName)",
                "Volume down on \(\.$device) with \(.applicationName)",
                "Lower volume with \(.applicationName)",
                "Lower volume \(\.$device) with \(.applicationName)",
                "Turn volume down with \(.applicationName)",
                "Turn volume down on \(\.$device) with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Volume Down", comment: "Siri shortcut to turn the volume down"),
            systemImageName: "speaker.minus"
        )
        AppShortcut(
            intent: VolumeUpIntent(),
            phrases: [
                "Volume up with \(.applicationName)",
                "Volume up on \(\.$device) with \(.applicationName)",
                "Raise volume with \(.applicationName)",
                "Raise volume \(\.$device) with \(.applicationName)",
                "Turn volume up with \(.applicationName)",
                "Turn volume up on \(\.$device) with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Volume Up", comment: "Siri shortcut to turn the volume up"),
            systemImageName: "speaker.plus"
        )
        AppShortcut(
            intent: OkIntent(),
            phrases: [
                "Press Ok with \(.applicationName)",
                "Press Ok on \(\.$device) with \(.applicationName)",
                "Press select with \(.applicationName)",
                "Press select on \(\.$device) with \(.applicationName)",
                "Select with \(.applicationName)",
                "Select on \(\.$device) with \(.applicationName)",
                "Confirm with \(.applicationName)",
                "Confirm on \(\.$device) with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Select", comment: "Siri shortcut to select/confirm"),
            systemImageName: "checkmark"
        )
        AppShortcut(
            intent: ButtonPressIntent(),
            phrases: [
                "Press \(\.$button) with \(.applicationName)",
                "Press a button on TV with \(.applicationName)",
                "Press a button on Roku with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Press Any Button", comment: "Siri shortcut to press any button"),
            systemImageName: "button.programmable"
        )
        AppShortcut(
            intent: LaunchAppIntent(),
            phrases: [
                "Launch \(\.$app) with \(.applicationName)",
                "Launch \(\.$app) on TV with \(.applicationName)",
                "Launch \(\.$app) on Roku \(.applicationName)",
                "Open \(\.$app) with \(.applicationName)",
                "Open \(\.$app) on TV with \(.applicationName)",
                "Open app with \(.applicationName)",
                "Launch app on \(\.$device) \(.applicationName)",
                "Launch app on TV with \(.applicationName)",
                "Launch app on Roku with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Launch App", comment: "Siri shortcut to launch an app"),
            systemImageName: "apps.iphone.landscape"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .purple
}
