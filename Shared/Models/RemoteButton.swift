import Foundation
import SwiftUI

public enum RemoteButton: String, CaseIterable, Sendable, Encodable, Hashable {
    case up = "Up"
    case left = "Left"
    case right = "Right"
    case down = "Down"

    case select = "Select"
    case home = "Home"
    case back = "Back"
    case powerOff = "PowerOff"
    case powerOn = "PowerOn"
    case power = "Power"

    case mute = "VolumeMute"
    case volumeUp = "VolumeUp"
    case volumeDown = "VolumeDown"

    case options = "Info"
    case instantReplay = "InstantReplay"
    case rewind = "Rev"
    case fastForward = "Fwd"
    case playPause = "Play"

    case findRemote = "FindRemote"
    case backspace = "Backspace"
    case search = "Search"
    case enter = "Enter"

    case channelUp = "ChannelUp"
    case channelDown = "ChannelDown"

    case inputTuner = "InputTuner"
    case inputHDMI1 = "InputHDMI1"
    case inputHDMI2 = "InputHDMI2"
    case inputHDMI3 = "InputHDMI3"
    case inputHDMI4 = "InputHDMI4"
    case inputAV1 = "InputAV1"
    case headphonesMode = "Headphones Mode"

    public static let typeDisplayName: String = "Button"

    public static let caseDisplayRepresentations: [RemoteButton: String] = [
        .up: String(localized: "Up", comment: "Remote button to move up"),
        .left: String(localized: "Left", comment: "Remote button to move left"),
        .right: String(localized: "Right", comment: "Remote button to move right"),
        .down: String(localized: "Down", comment: "Remote button to move down"),
        .select: String(localized: "Ok", comment: "Remote button to select/confirm"),
        .home: String(localized: "Home", comment: "Remote button to go to home screen"),
        .back: String(localized: "Back", comment: "Remote button to go back"),
        .power: String(localized: "Power On/Off", comment: "Remote button to power on/off"),
        .powerOn: String(localized: "Power On", comment: "Remote button to power on"),
        .powerOff: String(localized: "Power Off", comment: "Remote button to power off"),
        .mute: String(localized: "Mute/Unmute", comment: "Remote button to mute/unmute"),
        .volumeUp: String(localized: "Volume Up", comment: "Remote button to increase volume"),
        .volumeDown: String(localized: "Volume Down", comment: "Remote button to decrease volume"),
        .options: String(localized: "Options", comment: "Remote button for options menu"),
        .instantReplay: String(localized: "Instant Replay", comment: "Remote button for instant replay"),
        .rewind: String(localized: "Rewind", comment: "Remote button to rewind"),
        .fastForward: String(localized: "Fast Forward", comment: "Remote button to fast forward"),
        .playPause: String(localized: "Play/Pause", comment: "Remote button to play/pause"),
        .findRemote: String(localized: "Find Remote", comment: "Remote button to find remote"),
        .backspace: String(localized: "Backspace", comment: "Remote button to backspace"),
        .search: String(localized: "Search", comment: "Remote button to search"),
        .enter: String(localized: "Enter", comment: "Remote button to enter"),
        .channelUp: String(localized: "Channel Up", comment: "Remote button to increase channel number"),
        .channelDown: String(localized: "Channel Down", comment: "Remote button to decrease channel number"),
        .inputTuner: String(localized: "Input Tuner", comment: "Remote button for input tuner"),
        .inputHDMI1: String(localized: "Input HDMI 1", comment: "Remote button for HDMI input 1"),
        .inputHDMI2: String(localized: "Input HDMI 2", comment: "Remote button for HDMI input 2"),
        .inputHDMI3: String(localized: "Input HDMI 3", comment: "Remote button for HDMI input 3"),
        .inputHDMI4: String(localized: "Input HDMI 4", comment: "Remote button for HDMI input 4"),
        .inputAV1: String(localized: "Input AV 1", comment: "Remote button for AV input 1"),
        .headphonesMode: String(localized: "Headphones Mode", comment: "Remote button for headphones mode")
    ]

    public static let systemIcons: [RemoteButton: String?] = [
        .up: "chevron.up",
        .left: "chevron.left",
        .right: "chevron.right",
        .down: "chevron.down",
        .select: nil,
        .home: "house",
        .back: "arrow.left",
        .power: "power",
        .powerOn: "power",
        .powerOff: "power",
        .mute: "speaker.slash",
        .volumeUp: "speaker.plus",
        .volumeDown: "speaker.minus",
        .options: "asterisk",
        .instantReplay: "arrow.uturn.left",
        .rewind: "backward",
        .fastForward: "forward",
        .playPause: "playpause",
        .findRemote: "av.remote",
        .backspace: "delete.left",
        .search: "magnifyingglass",
        .enter: "return",
        .channelUp: "arrowtriangle.up",
        .channelDown: "arrowtriangle.down",
        .headphonesMode: "headphones",
        .inputTuner: nil,
        .inputHDMI1: nil,
        .inputHDMI2: nil,
        .inputHDMI3: nil,
        .inputHDMI4: nil,
        .inputAV1: nil,
    ]

    public static let buttonApiDescription: [RemoteButton: String] = [
        .up: "Up",
        .left: "Left",
        .right: "Right",
        .down: "Down",
        .select: "Select",
        .home: "Home",
        .back: "Back",
        .power: "Power",
        .powerOn: "PowerOn",
        .powerOff: "PowerOff",
        .mute: "VolumeMute",
        .volumeUp: "VolumeUp",
        .volumeDown: "VolumeDown",
        .options: "Info",
        .instantReplay: "InstantReplay",
        .rewind: "Rev",
        .fastForward: "Fwd",
        .playPause: "Play",
        .findRemote: "FindRemote",
        .backspace: "Backspace",
        .search: "Search",
        .enter: "Enter",
        .channelUp: "ChannelUp",
        .channelDown: "ChannelDown",
        .inputTuner: "InputTuner",
        .inputHDMI1: "InputHDMI1",
        .inputHDMI2: "InputHDMI2",
        .inputHDMI3: "InputHDMI3",
        .inputHDMI4: "InputHDMI4",
        .inputAV1: "InputAV1",
    ]

    public var apiValue: String? {
        Self.buttonApiDescription[self]
    }

    public var systemIcon: String? {
        // Why do I have to do this
        if let icon = Self.systemIcons[self] {
            icon
        } else {
            nil
        }
    }

    public static func fromCharacter(character: Character) -> RemoteButton? {
        #if !os(watchOS)
            let keyMap: [Character: RemoteButton] = [
                "\u{7F}": RemoteButton.backspace,
                KeyEquivalent.delete.character: RemoteButton.backspace,
                KeyEquivalent.deleteForward.character: RemoteButton.backspace,
                KeyEquivalent.escape.character: RemoteButton.backspace,
                KeyEquivalent.downArrow.character: RemoteButton.down,
                KeyEquivalent.upArrow.character: RemoteButton.up,
                KeyEquivalent.rightArrow.character: RemoteButton.right,
                KeyEquivalent.leftArrow.character: RemoteButton.left,
                KeyEquivalent.home.character: RemoteButton.home,
                KeyEquivalent.return.character: RemoteButton.select,
            ]
        #else
            let keyMap: [Character: RemoteButton] = [
                "\u{7F}": RemoteButton.backspace,
            ]
        #endif

        if let mappedString = keyMap[character] {
            return mappedString
        }

        return nil
    }

    @ViewBuilder
    public var label: some View {
        if let systemIcon {
            Label(description, systemImage: systemIcon)
        } else {
            Text(description)
        }
    }

    public var description: String {
        Self.caseDisplayRepresentations[self]!
    }
}
