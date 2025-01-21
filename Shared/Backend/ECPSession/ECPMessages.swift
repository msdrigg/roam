import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ECPResponseMessage")
enum ECPResponseMessage: Decodable {
    case notify(ECPNotification)
    case response(ECPResponse)

    init(from decoder: any Decoder) throws {
        // Decode responseiddecoder and
        do {
            self = .response(try ECPResponse(from: decoder))
            return
        } catch {}

        self = .notify(try .init(from: decoder))
    }
}

enum ECPNotification: Decodable {
    case texteditChanged(TextEditState)
    case texteditOpened(TextEditState)
    case texteditClosed

    enum NotifyCodingKey: String, CodingKey {
        case notify
    }
    enum NotifyTypes: String, Decodable {
        case texteditOpened = "textedit-opened"
        case texteditClosed = "textedit-closed"
        case texteditChanged = "textedit-changed"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: NotifyCodingKey.self)
        let notify = try container.decode(NotifyTypes.self, forKey: .notify)

        switch notify {
        case .texteditChanged:
            self = .texteditChanged(try .init(from: decoder))
        case .texteditOpened:
            self = .texteditOpened(try .init(from: decoder))
        case .texteditClosed:
            self = .texteditClosed
        }
    }
}

enum ECPRequestMessage: Encodable {
    case configureAudio(ConfigureAudioRequest)
    case launchApp(AppLaunchRequest)
    case queryActiveApp(ActiveAppQueryRequest)
    case queryTexteditState(TexteditStateQueryRequest)
    case keyPress(KeyPressRequest)
    case setTexteditState(SetTexteditStateRequest)
    case queryDeviceApps(QueryApps)
    case queryDeviceInfo(QueryDeviceInfo)
    case queryDeviceCapabilities(QueryAudioDevice)
    case queryAppIcon(QueryAppIcon)
    case requestEventsNotify(EventsNotifyRequest)

    var requestId: String {
        switch self {
        case .configureAudio(let req): req.requestId
        case .keyPress(let req): req.requestId
        case .launchApp(let req): req.requestId
        case .queryActiveApp(let req): req.requestId
        case .queryTexteditState(let req): req.requestId
        case .setTexteditState(let req): req.requestId
        case .queryAppIcon(let req): req.requestId
        case .queryDeviceApps(let req): req.requestId
        case .queryDeviceInfo(let req): req.requestId
        case .queryDeviceCapabilities(let req): req.requestId
        case .requestEventsNotify(let req): req.requestId
        }
    }

    func withId(_ id: String) -> ECPRequestMessage {
        switch self {
        case .configureAudio(let val): .configureAudio(val.withId(id))
        case .keyPress(let val): .keyPress(val.withId(id))
        case .launchApp(let val): .launchApp(val.withId(id))
        case .queryActiveApp(let req): .queryActiveApp(req.withId(id))
        case .queryTexteditState(let req): .queryTexteditState(req.withId(id))
        case .setTexteditState(let req): .setTexteditState(req.withId(id))
        case .queryAppIcon(let req): .queryAppIcon(req.withId(id))
        case .queryDeviceApps(let req): .queryDeviceApps(req.withId(id))
        case .queryDeviceInfo(let req): .queryDeviceInfo(req.withId(id))
        case .queryDeviceCapabilities(let req): .queryDeviceCapabilities(req.withId(id))
        case .requestEventsNotify(let req): .requestEventsNotify(req.withId(id))
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .configureAudio(let value):
            try value.encode(to: encoder)
        case .launchApp(let value):
            try value.encode(to: encoder)
        case .keyPress(let value):
            try value.encode(to: encoder)
        case .queryActiveApp(let value):
            try value.encode(to: encoder)
        case .queryTexteditState(let value):
            try value.encode(to: encoder)
        case .setTexteditState(let value):
            try value.encode(to: encoder)
        case .queryAppIcon(let req):
            try req.encode(to: encoder)
        case .queryDeviceApps(let req):
            try req.encode(to: encoder)
        case .queryDeviceInfo(let req):
            try req.encode(to: encoder)
        case .queryDeviceCapabilities(let req):
            try req.encode(to: encoder)
        case .requestEventsNotify(let req):
            try req.encode(to: encoder)
        }
    }
}

struct TextEditState: Codable, Equatable, Hashable {
    let masked: String?
    let maxLength: String?
    let texteditId: String
    let selectionEnd: String?
    let selectionStart: String?
    let textEditType: String?
    let text: String?

    static func disconnected() -> Self {
        return TextEditState(
            masked: nil,
            maxLength: nil,
            texteditId: "none",
            selectionEnd: nil,
            selectionStart: nil,
            textEditType: nil,
            text: nil
        )
    }
}

struct ConfigureAudioRequest: Encodable {
    let devname: String?
    let audioOutput: String
    let request: String = "set-audio-output"
    let requestId: String

    func withId(_ id: String) -> Self {
        Self(devname: devname, audioOutput: audioOutput, requestId: id)
    }

    #if !os(watchOS)
        static func headphonesMode(hostIp: String, requestId: String) -> Self {
            Self(
                devname: "\(hostIp):\(globalHostRTPPort):\(globalRTPPayloadType):\(globalClockRate / 50)",
                audioOutput: "datagram",
                requestId: requestId
            )
        }
    #endif
}

struct AppLaunchRequest: Encodable {
    let request: String = "launch"
    let requestId: String
    let channelId: String
    let params: [String: String]?

    func withId(_ id: String) -> Self {
        Self(requestId: id, channelId: channelId, params: params)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys.self)
        try container.encode(request, forKey: .request)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(channelId, forKey: .channelId)
        if let params {
            let jsonEncoder = JSONEncoder()
            let paramsString = try jsonEncoder.encode(params)

            let paramsStringString = String(data: paramsString, encoding: .utf8)!
            try container.encode(paramsStringString, forKey: .params)
        }
    }

    enum CodingKeys: String, CodingKey {
        case request
        case requestId
        case channelId
        case params
    }
}

struct QueryAppIcon: Encodable {
    let request: String = "query-icon"
    let requestId: String
    let channelId: String

    func withId(_ id: String) -> Self {
        Self(requestId: id, channelId: self.channelId)
    }

    enum CodingKeys: String, CodingKey {
        case request = "request"
        case requestId = "request-id"
        case channelId = "param-channel-id"
    }
}
struct QueryApps: Encodable {
    let request: String = "query-apps"
    let requestId: String

    func withId(_ id: String) -> Self {
        Self(requestId: id)
    }
}

struct QueryAudioDevice: Encodable {
    let request: String = "query-audio-device"
    let requestId: String

    func withId(_ id: String) -> Self {
        Self(requestId: id)
    }
}

struct QueryDeviceInfo: Encodable {
    let request: String = "query-device-info"
    let requestId: String

    func withId(_ id: String) -> Self {
        Self(requestId: id)
    }
}

struct EventsNotifyRequest: Encodable {
    let request: String = "request-events"
    let requestId: String
    let events: String

    func withId(_ id: String) -> Self {
        Self(requestId: id, events: self.events)
    }
}

struct ActiveAppQueryRequest: Encodable {
    let request: String = "query-active-app"
    let requestId: String

    func withId(_ id: String) -> Self {
        Self(requestId: id)
    }
}

struct TexteditStateQueryRequest: Encodable {
    let request: String = "query-textedit-state"
    let requestId: String

    func withId(_ id: String) -> Self {
        Self(requestId: id)
    }
}

struct KeyPressRequest: Encodable {
    let request: String = "key-press"
    let key: String
    let requestId: String

    func withId(_ id: String) -> Self {
        Self(key: key, requestId: id)
    }
}

struct SetTexteditStateRequest: Encodable {
    let request: String = "set-textedit-text"
    let requestId: String
    let text: String
    let texteditId: String

    func withId(_ id: String) -> Self {
        Self(requestId: id, text: text, texteditId: texteditId)
    }
}

enum ECPResponse: Decodable {
    case base(BaseResponse)

    var responseId: String {
        switch self {
        case .base(let baseResponse):
            return baseResponse.responseId
        }
    }

    var status: String {
        switch self {
        case .base(let baseResponse):
            return baseResponse.status
        }
    }

    var isSuccess: Bool {
        switch self {
        case .base(let baseResponse):
            return baseResponse.isSuccess
        }
    }

    init(from decoder: any Decoder) throws {
        let baseResponse = try BaseResponse(from: decoder)
        self = .base(baseResponse)
    }
}

struct BaseResponse: Decodable {
    let response: String
    let responseId: String
    let status: String
    let statusMsg: String?
    let contentData: Data?
    let contentType: String?

    var isSuccess: Bool {
        status == "200"
    }
}
