import CommonCrypto
import os.log
import Network
import SwiftUI
import Combine

enum ECPSessionStatus: Equatable {
    case connected
    case connecting(Date)
    case disconnected(Date)
}

enum HeadphonesModeStatus {
    case connected
    case connecting
    case off
    case error
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

enum TextEditStatus: Equatable, Hashable {
    case editing(TextEditState)
    case off

    var isActive: Bool {
        return switch self {
        case .editing: true
        case .off: false
        }
    }

    var text: String? {
        return switch self {
        case let .editing(state): state.text ?? ""
        case .off: nil
        }
    }

    var texteditId: String? {
        return switch self {
        case let .editing(state):
            if state.texteditId == "none" || state.texteditId == "" {
                nil
            } else {
                state.texteditId
            }
        case .off: nil
        }
    }
}

@MainActor
@Observable
class ECPSessionState {
    var status: ECPSessionStatus = .disconnected(.distantPast)
    var headphonesModeStatus: HeadphonesModeStatus = .off
    var textEditStatus: TextEditStatus = .off
    var ecpSession: ECPSession?
}

let refreshInterval: TimeInterval = 10
let requestTimeout: TimeInterval = 3

actor ECPSession {
    nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ECPSession.self)
    )

    static let messageReceivedNotification: NSNotification.Name = .init("com.msdrigg.ECPSession.messageReceived")
    static let websocketStateUpdatedNotification: NSNotification.Name = .init("com.msdrigg.ECPSession.websocketStateUpdated")

    let device: DeviceAppEntity
    let status: ECPSessionState

    private var connection: NWConnection?
    private let endpoint: NWEndpoint
    private let url: URL
    private var isMigratingConnection: Bool = false

    private let errorWhileWaitingLimit = 20
    private var errorWhileWaitingCount = 0

    var requestIdCounter: Int = 0
    var cancellables: Set<AnyCancellable> = Set()
    nonisolated var kebabEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = kebabParamEncodingStrategy()
        return e
    }
    nonisolated var kebabDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = kebabParamDecodingStrategy()
        return d
    }
    let connectionQueue: DispatchQueue = DispatchQueue(label: "ECP Session Queue", qos: .userInitiated)

    enum ECPError: Error, LocalizedError {
        case badWebsocketMessage
        case authDenied
        case badURL
        case connectFailed
        case badInterfaceIP
        case plStartFailed
        case badKepress
        case badTexteditId
        case responseRejection(code: String)
    }

    private static var websocketParameters: NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionDropTime = 2
        tcpOptions.connectionTimeout = 2
        tcpOptions.keepaliveCount = 2
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveInterval = 2
        tcpOptions.persistTimeout = 2
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let options = NWProtocolWebSocket.Options()
        options.setSubprotocols(["ecp-2"])
        options.autoReplyPing = true

        params.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        return params
    }

    public init(device: DeviceAppEntity, status: ECPSessionState) throws {
        Self.logger.info("Initing ECP Session with url \(device.location, privacy: .public)")
        // SAFETY: "http" is always a valid regex
        // swiftlint:disable:next force_try
        guard let url = URL(string: "\(device.location.replacing(try! Regex("^http:"), with: "ws:"))ecp-session") else {
            Self.logger.error("Bad url for location \(device.location)ecp-session")
            throw ECPError.badURL
        }
        self.url = url
        self.endpoint = NWEndpoint.url(url)

        self.status = status
        self.device = device

        Task {
            await self.initObservers()
        }
    }

    deinit {
        connection?.cancel()
        connection = nil
        self.websocketStateUpdated(status: .disconnected(.now))
    }

    private func initObservers() {
        DispatchQueue
            .global(qos: .utility)
            .schedule(after: DispatchQueue.SchedulerTimeType(.now().advanced(by: .seconds(Int(refreshInterval)))),
                      interval: .seconds(refreshInterval),
                      tolerance: .seconds(refreshInterval / 5)) { [weak self] in
                guard let self else { return }
                Task { await self.ping() }
            }
          .store(in: &self.cancellables)

        NotificationCenter.default
            .publisher(for: Self.messageReceivedNotification)
            .filter { notification in
                guard let notificationNotify = notification.userInfo?["notify"] as? String else {
                    return false
                }

                return notificationNotify == "textedit-closed" || notificationNotify == "textedit-opened" || notificationNotify == "textedit-changed"
            }
            .sink { notification in
                Self.logger.info("Got response for notify")
                guard let data = notification.userInfo?["data"] as? Data else {
                    Self.logger.error("Error parsing notify message in waker (no data)")
                    return
                }

                guard let notificationNotify = notification.userInfo?["notify"] as? String else {
                    return
                }

                guard notificationNotify != "textedit-closed" else {
                    self.reportTextEditChanged(state: TextEditState.disconnected())
                    return
                }

                do {
                    let response = try self.kebabDecoder.decode(TextEditState.self, from: data)
                    self.reportTextEditChanged(state: response)
                } catch {
                    Self.logger.error("Error getting response from notify: \(error)")
                }
            }
            .store(in: &self.cancellables)
    }

    public func close() async {
        Self.logger.info("Closing ecp")
        self.cancellables.removeAll()

        connection?.cancel()
        connection = nil

        self.websocketStateUpdated(status: .disconnected(.now))
    }

    nonisolated func websocketStateUpdated(status: ECPSessionStatus) {
        Self.logger.info("WS Status updated to \(String(describing: status))")
        NotificationCenter.default.post(name: Self.websocketStateUpdatedNotification, object: nil, userInfo: ["websocketState": status])
        let currentStatus = self.status

        DispatchQueue.main.async {
            switch (status, currentStatus.status) {
            case (.disconnected, .disconnected), (.connecting, .connecting):
                break
            default:
                currentStatus.status = status
            }
        }
    }

    public func triggerReconnect() {
        guard !isMigratingConnection else { return }
        connection?.cancel()
        isMigratingConnection = true
        let connection = NWConnection(to: endpoint, using: Self.websocketParameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task {
                await self?.stateDidChange(to: state)
            }
        }
        connection.betterPathUpdateHandler = { [weak self] isAvailable in
            Task {
                await self?.betterPath(isAvailable: isAvailable)
            }
        }
        connection.viabilityUpdateHandler = { [weak self] isViable in
            Task {
                await self?.viabilityDidChange(isViable: isViable)
            }
        }
        listen()
        Task {
            do {
                try await establishConnectionAndAuthenticate()
            } catch {
                Self.logger.error("Failed to establish connection and authenticate. Cancelling...: \(error, privacy: .public)")
                connection.cancel()
                throw error
            }
        }
    }

    public func configure() async throws {
        if let connection {
            if isMigratingConnection {
                return
            }
            self.websocketStateUpdated(status: .connecting(.now))
            switch connection.state {
            case NWConnection.State.cancelled, .failed:
                self.triggerReconnect()
            case .ready, .waiting, .preparing:
                break
            case .setup:
                Self.logger.info("Updating status to .connecting")
                self.websocketStateUpdated(status: .connecting(.now))

                do {
                    try await establishConnectionAndAuthenticate()
                } catch {
                    Self.logger.error("Failed to establish connection and authenticate. Cancelling...: \(error, privacy: .public)")
                    connection.cancel()
                    throw error
                }
            @unknown default:
                Self.logger.info("Unknown connection state: \(String(describing: connection.state), privacy: .public)")
            }
        } else if connection?.state != .ready {
            self.websocketStateUpdated(status: .connecting(.now))
            let connection = NWConnection(to: endpoint, using: ECPSession.websocketParameters)

            connection.stateUpdateHandler = { [weak self] state in
                Task {
                    await self?.stateDidChange(to: state)
                }
            }
            connection.betterPathUpdateHandler = { [weak self] isAvailable in
                Task {
                    await self?.betterPath(isAvailable: isAvailable)
                }
            }
            connection.viabilityUpdateHandler = { [weak self] isViable in
                Task {
                    await self?.viabilityDidChange(isViable: isViable)
                }
            }
            self.connection = connection
            self.listen()

            do {
                try await establishConnectionAndAuthenticate()
                do {
                    try await requestTextEditNotify()
                } catch {
                    Self.logger.error("Error requesting text edit notify: \(error, privacy: .public)")
                }
            } catch {
                Self.logger.error("Failed to establish connection and authenticate. Cancelling...: \(error, privacy: .public)")
                connection.cancel()
                throw error
            }
        }

        requestIdCounter = 0
    }

    public func listen() {
        connection?.receiveMessage { [weak self] (data, context, _, error) in
            guard let self = self else {
                return
            }
            DispatchQueue.main.async {
                self.status.status = .connected
            }
            Self.logger.info("Receiving data \(String(describing: data))")

            Task {
                if let data = data, let context = context {
                    await self.receiveMessage(data: data, context: context)
                }

                if let error = error {
                    await self.reportErrorOrDisconnection(error)
                } else {
                    await self.listen()
                }
            }
        }
    }

    func tearDownConnection(error: NWError?) {
        if let error = error {
            self.reportErrorOrDisconnection(error)
        }
        connection?.cancel()
        connection = nil

        if let error {
            self.reportErrorOrDisconnection(error)
        }
    }

    func stateDidChange(to state: NWConnection.State) {
        Self.logger.info("WS State changed to \(String(describing: state), privacy: .public)")
        switch state {
        case .ready:
            isMigratingConnection = false
            self.websocketStateUpdated(status: .connected)
        case .waiting(let error):
            isMigratingConnection = false
            reportErrorOrDisconnection(error)
            self.websocketStateUpdated(status: .connecting(.now))

            /// Workaround to prevent loop while reconnecting
            errorWhileWaitingCount += 1
            if errorWhileWaitingCount >= errorWhileWaitingLimit {
                tearDownConnection(error: error)
                errorWhileWaitingCount = 0
            }
        case .failed(let error):
            errorWhileWaitingCount = 0
            isMigratingConnection = false
            tearDownConnection(error: error)
            self.websocketStateUpdated(status: .disconnected(.now))
        case .setup, .preparing:
            self.websocketStateUpdated(status: .connecting(.now))
        case .cancelled:
            self.websocketStateUpdated(status: .disconnected(.now))
            errorWhileWaitingCount = 0
            tearDownConnection(error: nil)
        @unknown default:
            Self.logger.warning("Unknown state \(String(describing: state), privacy: .public)")
        }
    }

    func betterPath(isAvailable: Bool) {
        if isAvailable {
            Self.logger.info("Reconnecting with better path")
            self.triggerReconnect()
        } else {
            Self.logger.info("Not reconnecting because no better path available")
        }
    }

    func viabilityDidChange(isViable: Bool) {
        Self.logger.info("Network viability changed \(isViable)")
    }

    private func reportDisconnection(closeCode: NWProtocolWebSocket.CloseCode, reason: Data?) {
        self.websocketStateUpdated(status: .disconnected(.now))
        let reasonText = String(data: reason ?? .init(), encoding: .utf8) ?? "No reason text"
        Self.logger.error("Websocket closed with reason \(reasonText, privacy: .public) code \(String(describing: closeCode), privacy: .public)")
    }

    private func reportErrorOrDisconnection(_ error: any Error) {
        self.websocketStateUpdated(status: .disconnected(.now))
        Self.logger.error("Error from websocket \(error)")
    }

    private nonisolated func waitForConnectionReady() async throws {
        var cancellable: (any Cancellable)?
        Self.logger.info("Waiting for connection ready")
        defer {
            // Keep cancellable around until after the block exits (so it doesn't drop)
            cancellable?.cancel()
        }

        _ = try await withCheckedThrowingContinuation { continuation in
            cancellable = NotificationCenter.default
                .publisher(for: Self.messageReceivedNotification)
                .sink { notification in
                    Self.logger.info("Received notification \(String(describing: notification.name))")
                    guard let websocketState = notification.userInfo?["websocketState"] as? ECPSessionStatus else {
                        Self.logger.error("Received bad ECPSession notification")
                        return
                    }
                    switch websocketState {
                    case .connected:
                        continuation.resume(
                            returning: ""
                        )
                        return
                    case .disconnected:
                        Self.logger.error("Received ECPSession notification for disconnected websocket")
                        continuation.resume(throwing: ECPError.connectFailed)
                        return
                    case .connecting:
                        return
                    }
                }
        }
    }

    private nonisolated func receive(requestId: String?) async throws -> Data {
        var cancellable: (any Cancellable)?
        Self.logger.info("Waiting for response \(String(describing: requestId), privacy: .public)")
        defer {
            // Keep cancellable around until after the block exits (so it doesn't drop)
            cancellable?.cancel()
        }
        return try await withUnsafeThrowingContinuation { continuation in
            cancellable = NotificationCenter.default
                .publisher(for: Self.messageReceivedNotification)
                .filter { notification in
                    if let requestId {
                        guard let notificationRequestId = notification.userInfo?["requestId"] as? String else {
                            return false
                        }
                        return requestId == notificationRequestId
                    } else {
                        return true
                    }
                }
                .sink { notification in
                    Self.logger.info("Got response for id \(String(describing: requestId), privacy: .public)")
                    if let data = notification.userInfo?["data"] as? Data {
                        continuation.resume(
                            returning: data
                        )
                    } else {
                        Self.logger.error("Error parsing websocket message in waker")
                        continuation.resume(throwing: ECPError.badWebsocketMessage)
                        return
                    }
                }
        }
    }

    private func receiveMessage(data: Data, context: NWConnection.ContentContext) {
        guard let metadata = context.protocolMetadata.first as? NWProtocolWebSocket.Metadata else {
            return
        }

        switch metadata.opcode {
        case .binary:
            guard let string = String(data: data, encoding: .utf8) else {
                return
            }
            self.webSocketDidReceiveMessage(string: string)
        case .cont:
            break
        case .text:
            guard let string = String(data: data, encoding: .utf8) else {
                return
            }
            self.webSocketDidReceiveMessage(string: string)
        case .close:
            reportDisconnection(closeCode: metadata.closeCode, reason: data)
        case .ping:
            // Auto-replying (see `websocketParameters`)
            break
        case .pong:
            // SEE `ping()` FOR PONG RECEIVE LOGIC.
            break
        @unknown default:
            Self.logger.warning("Unknown websocket message type \(String(describing: metadata.opcode), privacy: .public)")
        }
    }

    private nonisolated func webSocketDidReceiveMessage(string: String) {
        Self.logger.info("Received message: \(string)")

        if let data = string.data(using: .utf8) {
            do {
                let response = try kebabDecoder.decode(ResponseIdDecoder.self, from: data)
                var userInfo: [String: Any] = ["data": data]
                Self.logger.info("Received response id \(String(describing: response.responseId)) or message")
                if let responseId = response.responseId {
                    userInfo["requestId"] = responseId
                }
                if let notifyResponse = response.notify {
                    userInfo["notify"] = notifyResponse
                }
                NotificationCenter.default.post(name: Self.messageReceivedNotification, object: nil, userInfo: userInfo)
            } catch {
                Self.logger.info("No response id received for message")
                NotificationCenter.default.post(name: Self.messageReceivedNotification, object: nil, userInfo: ["data": data])
            }
        } else {
            Self.logger.error("Failed to convert string to data")
        }
    }

    // MARK: Actions
    func pingProtocolLayer() async throws {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
        metadata.setPongHandler(connectionQueue) { [weak self] error in
            guard let self = self else {
                return
            }
            Task {
                if let error = error {
                    await self.reportErrorOrDisconnection(error)
                }
            }
        }
        let context = NWConnection.ContentContext(identifier: "pingContext", metadata: [metadata])

        try await send(data: "ping".data(using: .utf8)!, context: context)
    }

    private nonisolated func reportTextEditChanged(state: TextEditState) {
        DispatchQueue.main.async {
            if state.texteditId != "none" {
                self.status.textEditStatus = .editing(state)
            } else {
                self.status.textEditStatus = .off
            }
        }
    }

    private func requestTextEditNotify() async throws {
        // Start notify for textedit state
        let notifyRequestId = getAndUpdateRequestId()
        let requestData = try String(
            data: kebabEncoder.encode(
                RequestEventsNotify(requestId: notifyRequestId, events: "+textedit-opened,+textedit-changed,+textedit-closed")
            ),
            encoding: .utf8
        )!

        // SAFETY: We can unwrap because json encoder always encodes to string
        let notifyResponseTask = Task {
            try await self.receive(requestId: notifyRequestId)
        }

        try await send(string: requestData)

        let notifyResponseData = try await notifyResponseTask.value

        let websocketStr = String(data: notifyResponseData, encoding: .utf8) ?? "--Bad data--"

        let notifyResponse = try kebabDecoder.decode(BaseResponse.self, from: notifyResponseData)

        if !notifyResponse.isSuccess {
            Self.logger.error("Got unsuccessful response from notify start: \(websocketStr, privacy: .public)")
        } else {
            Self.logger.info("Got successful notify start websocket response: \(websocketStr, privacy: .public)")
        }

        // Now query for textedit state
        let textEditQueryRequestId = getAndUpdateRequestId()
        let textEditQueryRequestData = try String(
            data: kebabEncoder.encode(
                GenericRequest(request: "query-textedit-state", requestId: textEditQueryRequestId)
            ),
            encoding: .utf8
        )!

        // SAFETY: We can unwrap because json encoder always encodes to string

        try await send(string: textEditQueryRequestData)

        let textEditQueryResponseTask = Task {
            try await self.receive(requestId: textEditQueryRequestId)
        }

        let textEditQueryResponseData = try await textEditQueryResponseTask.value

        let textEditQueryResponse = try kebabDecoder.decode(BaseResponse.self, from: textEditQueryResponseData)

        let texteditWebsocketStr = String(data: textEditQueryResponseData, encoding: .utf8) ?? "--Bad data--"
        if !textEditQueryResponse.isSuccess {
            Self.logger.error("Got unsuccessful response from textEditQuery start: \(texteditWebsocketStr, privacy: .public)")
        } else {
            Self.logger.info("Got successful textEditQuery start websocket response: \(texteditWebsocketStr, privacy: .public)")
        }

        if let textEditResponseData = textEditQueryResponse.contentData {
            // Decode as textEditState
            struct TextEditStateWrapper: Decodable {
                let texteditState: TextEditState
            }
            let state = try kebabDecoder.decode(TextEditStateWrapper.self, from: textEditResponseData)
            self.reportTextEditChanged(state: state.texteditState)
        } else {
            Self.logger.info("No content data for text edit query")
        }
    }
    func setTextEditText(_ text: String, for texteditId: String) async throws {
        //  {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}

        // Now query for textedit state
        let textEditSetRequestId = getAndUpdateRequestId()

        guard texteditId != "none" else {
            Self.logger.error("Can't set textedit state with 'none' Textedit ID")
            throw ECPError.badTexteditId
        }

        let textEditSetRequestData = try String(
            data: kebabEncoder.encode(
                RequestSetTexteditState(requestId: textEditSetRequestId, text: text, texteditId: texteditId)
            ),
            encoding: .utf8
        )!

        try await send(string: textEditSetRequestData)

        let textEditSetResponseTask = Task {
            try await self.receive(requestId: textEditSetRequestId)
        }

        let textEditSetResponseData = try await textEditSetResponseTask.value

        let textEditSetResponse = try kebabDecoder.decode(BaseResponse.self, from: textEditSetResponseData)

        let texteditWebsocketStr = String(data: textEditSetResponseData, encoding: .utf8) ?? "--Bad data--"
        if !textEditSetResponse.isSuccess {
            Self.logger.error("Got unsuccessful response from textEditQuery start: \(texteditWebsocketStr, privacy: .public)")
        } else {
            Self.logger.info("Got successful textEditQuery start websocket response: \(texteditWebsocketStr, privacy: .public)")
        }
    }

    func send(string: String) async throws {
        guard let data = string.data(using: .utf8) else {
            return
        }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "textContext",
            metadata: [metadata]
        )

        try await send(data: data, context: context)
    }

    func send(data: Data) async throws {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "textContext",
            metadata: [metadata]
        )

        try await send(data: data, context: context)
    }

    private func send(data: Data?, context: NWConnection.ContentContext) async throws {
        // Before we send anything, make sure the websocket is up and running
        try await preInitWebsocket()
        let dataString = String(decoding: data ?? .init(), as: UTF8.self)
        Self.logger.info("Sending data \(dataString)")

        connection?.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed({ [weak self] error in
                guard let self = self else {
                    return
                }

                Task {
                    // If a connection closure was sent, inform delegate on completion
                    if let socketMetadata = context.protocolMetadata.first as? NWProtocolWebSocket.Metadata,
                       socketMetadata.opcode == .close {
                        await self.reportDisconnection(closeCode: socketMetadata.closeCode, reason: data)
                    }

                    if let error = error {
                        await self.reportErrorOrDisconnection(error)
                    }
                }
            })
        )
    }

    func pingOnce() async throws {
        Self.logger.info("Pinging!")

        // SAFETY: We can unwrap because json encoder always encodes to string
        let requestData = try String(
            data: kebabEncoder.encode(PingRequest(requestId: String(getAndUpdateRequestId()))),
            encoding: .utf8
        )!
        try await send(string: requestData)
    }

    func ping() async {
        do {
            try await pingProtocolLayer()
        } catch {
            Self.logger.error("Unable to ping \(error, privacy: .public)")
            try? await pingProtocolLayer()
        }

    }

    public func powerToggleDevice() async throws {
        Self.logger.debug("Toggling power for device \(self.device.location)")

        await powerToggleDeviceStateless(location: device.location, macs: device.macs())
    }

    #if !os(watchOS)
        public func requestHeadphonesMode() async throws {
            guard let connectingInterface = await tryConnectTCP(location: url.absoluteString, timeout: 3.0) else {
                Self.logger.error("Unable to connect tcp to \(self.url.absoluteString) to request headphones mode")
                throw ECPError.connectFailed
            }

            let localInterfaces = await allAddressedInterfaces()
            guard let localNWInterface = localInterfaces
                .first(where: { connectingInterface.name == $0.name && $0.isIPV4 })
            else {
                Self.logger
                    .error(
                        "Connected with interface \(connectingInterface.name) but no match in \(localInterfaces.map(\.name))"
                    )
                throw ECPError.badInterfaceIP
            }
            let localAddress = localNWInterface.address.addressString
            Self.logger.debug("Got local address \(localAddress)")

            let plRequestId = getAndUpdateRequestId()
            let requestData = try String(
                data: kebabEncoder.encode(ConfigureAudioRequest.headphonesMode(
                    hostIp: localAddress,
                    requestId: plRequestId
                )),
                encoding: .utf8
            )!

            // SAFETY: We can unwrap because json encoder always encodes to string
            let plResponseTask = Task {
                try await self.receive(requestId: plRequestId)
            }

            try await send(string: requestData)

            let plResponseData = try await plResponseTask.value

            let websocketStr = String(data: plResponseData, encoding: .utf8) ?? "--Bad data--"
            Self.logger.info("Got PL start weboscket response: \(websocketStr, privacy: .public)")

            let plResponse = try kebabDecoder.decode(BaseResponse.self, from: plResponseData)
            if !plResponse.isSuccess {
                Self.logger
                    .error("Unable to start headphones mode on roku with response \(String(describing: plResponse))")
                throw ECPError.plStartFailed
            } else {
                Self.logger.info("Started headphones mode successfully")
            }
        }
    #endif

    public func pressButton(_ key: RemoteButton) async throws {
        if key == .power {
            try await powerToggleDevice()
            return
        }

        guard let keypress = key.apiValue else {
            Self.logger.fault("Bad key with no api value \(String(describing: key))")
            throw ECPError.badKepress
        }

        try await sendKeypress(keypress)
    }

    public func pressCharacter(_ character: Character) async throws {
        let keypress = getKeypressForKey(key: character)
        try await sendKeypress(keypress)
    }

    public func openApp(_ app: AppLinkAppEntity) async throws {
        // Try 2x with 0.1 sec delay between
        do {
            try await openAppOnce(app)
        } catch {
            Self.logger.warning("Error opening app the first time--retrying: \(error)")
            try await Task.sleep(duration: 0.1)
            try await openAppOnce(app)
        }
    }

    public func openAppOnce(_ app: AppLinkAppEntity) async throws {
        Self.logger.info("Opening app \(app.id)")

        // SAFETY: We can unwrap because json encoder always encodes to string
        let reqId = getAndUpdateRequestId()
        let requestData = try String(
            data: kebabEncoder.encode(AppLaunchRequest(requestId: reqId, channelId: app.id)),
            encoding: .utf8
        )!

        let receiveTask = Task {
            try await self.receive(requestId: reqId)
        }

        try await send(string: requestData)
        _ = try await receiveTask.value

        Self.logger.info("Opened app \(app.id) successfully")
    }

    private func sendKeypress(_ data: String) async throws {
        // Try 2x with 0.1 sec delay between
        do {
            try await sendKeypressOnce(data)
        } catch {
            Self.logger.warning("Error sending keypress the first time--retrying: \(error, privacy: .public)")
            try await Task.sleep(duration: 0.1)
            try await sendKeypressOnce(data)
        }
    }

    private func sendKeypressOnce(_ data: String) async throws {
        Self.logger.trace("Trying to send keypress \(data)")

        // SAFETY: We can unwrap because json encoder always encodes to string
        let requestData = try String(
            data: kebabEncoder.encode(KeyPressRequest(key: data, requestId: String(getAndUpdateRequestId()))),
            encoding: .utf8
        )!
        try await send(string: requestData)
        Self.logger.info("Sent key \(data) successfully")
    }

    // MARK: Helper methods
    private func preInitWebsocket() async throws {
        if connection?.state != .ready  {
            if connection?.state == .preparing {
                try await waitForConnectionReady()
            } else {
                Self.logger.info("WS in down state, reconfiguring.")
                try await configure()
            }
        }
    }

    private func getAndUpdateRequestId() -> String {
        let reqid = requestIdCounter
        requestIdCounter += 1

        return String(reqid)
    }

    private func establishConnectionAndAuthenticate() async throws {
        guard let connection else {
            Self.logger.error("Trying to authenticate but no connection")
            return
        }

        do {
            let authReceiveTask = Task {
                try await self.receive(requestId: nil)
            }
            connection.start(queue: connectionQueue)
            let authMessageData = try await authReceiveTask.value

            let websocketStr = String(data: authMessageData, encoding: .utf8) ?? "--Bad data--"
            Self.logger.info("Got auth weboscket response: \(websocketStr, privacy: .public)")

            let challengeMessage = try kebabDecoder.decode(AuthChallenge.self, from: authMessageData)
            let reqId = getAndUpdateRequestId()
            let responseMessage = AuthVerifyRequest(
                challenge: challengeMessage.challenge,
                requestId: reqId
            )
            let responseData = try kebabEncoder.encode(responseMessage)

            let receiveTask = Task {
                try await self.receive(requestId: reqId)
            }

            try await send(data: responseData)

            do {
                _ = try await receiveTask.value
                Self.logger.info("Authenticated to roku successfully")
            } catch {
                Self.logger.info("Auth challenge failed with error \(error)")

                if let error = error as? ECPError {
                    switch error {
                    case .responseRejection(code:):
                        throw ECPError.authDenied
                    default:
                        throw error
                    }
                }

                throw error
            }
        } catch {
            Self.logger.error("WebSocket connection failed: \(error, privacy: .public)")
            throw error
        }
    }
}

private struct AuthChallenge: Codable {
    let challenge: String
}

private struct AuthVerifyRequest: Encodable {
    let microphoneSampleRates: String = "1600"
    let response: String
    let requestId: String
    let clientFriendlyName: String = "Wireless Speaker"
    let request: String = "authenticate"
    let hasMicrophone: String = "false"

    static let KEY = "95E610D0-7C29-44EF-FB0F-97F1FCE4C297"

    private static func charTransform(_ var1: UInt8, _ var2: UInt8) -> UInt8 {
        var var3: UInt8
        if var1 >= UInt8(ascii: "0"), var1 <= UInt8(ascii: "9") {
            var3 = var1 - UInt8(ascii: "0")
        } else if var1 >= UInt8(ascii: "A"), var1 <= UInt8(ascii: "F") {
            var3 = var1 - UInt8(ascii: "A") + 10
        } else {
            return var1
        }

        var var2 = (15 - var3 + var2) & 15
        if var2 < 10 {
            var2 += UInt8(ascii: "0")
        } else {
            var2 = var2 + UInt8(ascii: "A") - 10
        }

        return var2
    }

    init(challenge: String, requestId: String) {
        let authKeySeed = Data(Self.KEY.utf8.map { Self.charTransform($0, 9) })

        func createAuthKey(_ s: String) -> String {
            var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            let data = s.data(using: .utf8)! + authKeySeed
            data.withUnsafeBytes {
                _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
            }
            let base64String = Data(digest).base64EncodedString()
            return base64String
        }
        response = createAuthKey(challenge)

        self.requestId = String(requestId)

    }
}

// MARK: Request-response

private struct ConfigureAudioRequest: Encodable {
    let devname: String?
    let audioOutput: String
    let request: String = "set-audio-output"
    let requestId: String

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

private struct GenericRequest: Encodable {
    let request: String
    let requestId: String
}

private struct AppLaunchRequest: Encodable {
    let request: String = "launch"
    let requestId: String
    let channelId: String
}

private struct PingRequest: Encodable {
    let request: String = "query-active-app"
    let requestId: String
}

private struct KeyPressRequest: Encodable {
    let request: String = "key-press"
    let key: String
    let requestId: String
}

private struct RequestEventsNotify: Encodable {
    let request: String = "request-events"
    let requestId: String
    let events: String
}

private struct RequestSetTexteditState: Encodable {
    let request: String = "set-textedit-text"
    let requestId: String
    let text: String
    let texteditId: String
}

private struct ResponseIdDecoder: Decodable {
    let responseId: String?
    let notify: String?
}

private struct BaseResponse: Decodable {
    let response: String
    let responseId: String
    let status: String
    let statusMsg: String?
    let contentData: Data?

    var isSuccess: Bool {
        status == "200"
    }
}

func kebabParamDecodingStrategy() -> JSONDecoder.KeyDecodingStrategy {
    return JSONDecoder.KeyDecodingStrategy.custom { keySequence in
        let keyPart = keySequence.last!
        let segments = keyPart.stringValue.stripPrefix("param-").split(separator: "-")
        if segments.isEmpty {
            ECPSession.logger.error("Error parsing kebab-case parameter name: \(keyPart.stringValue)")
        }

        // Join camel case
        let joined = segments.makeIterator().enumerated().map { index, segment in
            if index == 0 {
                return segment.lowercased()
            } else {
                return segment.capitalized(with: Locale(identifier: "en_US"))
            }
        }.joined(separator: "")
        return AnyKey(stringValue: joined)
    }
}

func kebabParamEncodingStrategy() -> JSONEncoder.KeyEncodingStrategy {
    return JSONEncoder.KeyEncodingStrategy.custom { keySequence in
        let keyPart = keySequence.last!.stringValue
        let stringValue = if keyPart == "request" || keyPart == "requestId" || keyPart == "status" || keyPart == "statusMsg" || keyPart == "contentData" || keyPart == "notify" {
            kebabify(keyPart)
        } else {
            "param-" + kebabify(keyPart)
        }

        return AnyKey(stringValue: stringValue)
    }
}
