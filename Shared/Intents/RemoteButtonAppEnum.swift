import AppIntents

enum RemoteButtonAppEnum: String, AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Remote Button", comment: "A type of button that can perform an action"))

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
    case headphonesMode = "HeadphonesMode"

    public static let typeDisplayName: String = "Button"

    public static let caseDisplayRepresentations: [RemoteButtonAppEnum: DisplayRepresentation] = [
        .up: "Up",
        .left: "Left",
        .right: "Right",
        .down: "Down",
        .select: "Select",
        .home: "Home",
        .back: "Back",
        .power: "Power On/Off",
        .powerOn: "Power On",
        .powerOff: "Power Off",
        .mute: "Mute/Unmute",
        .volumeUp: "Volume Up",
        .volumeDown: "Volume Down",
        .options: "Options",
        .instantReplay: "Instant Replay",
        .rewind: "Rewind",
        .fastForward: "Fast Forward",
        .playPause: "Play/Pause",
        .findRemote: "Find Remote",
        .backspace: "Backspace",
        .search: "Search",
        .enter: "Enter",
        .channelUp: "Channel Up",
        .channelDown: "Channel Down",
        .inputTuner: "Input Tuner",
        .inputHDMI1: "Input HDMI 1",
        .inputHDMI2: "Input HDMI 2",
        .inputHDMI3: "Input HDMI 3",
        .inputHDMI4: "Input HDMI 4",
        .inputAV1: "Input AV 1",
        .headphonesMode: "Headphones Mode",
    ]

    var button: RemoteButton {
        switch self {
        case .up:
            .up
        case .left:
            .left
        case .right:
            .right
        case .down:
            .down
        case .select:
            .select
        case .home:
            .home
        case .back:
            .back
        case .power:
            .power
        case .powerOn:
            .powerOn
        case .powerOff:
            .powerOff
        case .mute:
            .mute
        case .volumeUp:
            .volumeUp
        case .volumeDown:
            .volumeDown
        case .options:
            .options
        case .instantReplay:
            .instantReplay
        case .rewind:
            .rewind
        case .fastForward:
            .fastForward
        case .playPause:
            .playPause
        case .findRemote:
            .findRemote
        case .backspace:
            .backspace
        case .search:
            .search
        case .enter:
            .enter
        case .channelUp:
            .channelUp
        case .channelDown:
            .channelDown
        case .inputTuner:
            .inputTuner
        case .inputHDMI1:
            .inputHDMI1
        case .inputHDMI2:
            .inputHDMI2
        case .inputHDMI3:
            .inputHDMI3
        case .inputHDMI4:
            .inputHDMI4
        case .inputAV1:
            .inputAV1
        case .headphonesMode:
            .headphonesMode
        }
    }
}

extension RemoteButton {
    var buttonAppEnum: RemoteButtonAppEnum {
        switch self {
        case .up:
            .up
        case .left:
            .left
        case .right:
            .right
        case .down:
            .down
        case .select:
            .select
        case .home:
            .home
        case .back:
            .back
        case .power:
            .power
        case .powerOn:
            .powerOn
        case .powerOff:
            .powerOff
        case .mute:
            .mute
        case .volumeUp:
            .volumeUp
        case .volumeDown:
            .volumeDown
        case .options:
            .options
        case .instantReplay:
            .instantReplay
        case .rewind:
            .rewind
        case .fastForward:
            .fastForward
        case .playPause:
            .playPause
        case .findRemote:
            .findRemote
        case .backspace:
            .backspace
        case .search:
            .search
        case .enter:
            .enter
        case .channelUp:
            .channelUp
        case .channelDown:
            .channelDown
        case .inputTuner:
            .inputTuner
        case .inputHDMI1:
            .inputHDMI1
        case .inputHDMI2:
            .inputHDMI2
        case .inputHDMI3:
            .inputHDMI3
        case .inputHDMI4:
            .inputHDMI4
        case .inputAV1:
            .inputAV1
        case .headphonesMode:
            .headphonesMode
        }
    }
}
