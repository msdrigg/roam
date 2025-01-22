#if !os(watchOS)
import Network
import Dispatch
import OSLog
import XMLCoder

typealias ECPStateCallback = @Sendable (ECPWebsocketState) -> Void
typealias ECPNotificationCallback = @Sendable (ECPNotification) -> Void
typealias ECPResponseCompletion = @Sendable (Result<ECPResponse, ECPWebsocketClient.ECPError>) -> Void

enum ECPWebsocketState: Equatable, CustomDebugStringConvertible {
    case connected
    case disconnected(Date)
    case connecting(Date)

    var debugDescription: String {
        switch self {
        case .connected:
            return "connected"
        case .disconnected(let date):
            return "disconnected at \(date)"
        case .connecting(let date):
            return "connecting at \(date)"
        }
    }
}

actor ECPWebsocketClient: Sendable {
    nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ECPWebsocketClient.self)
    )

    enum ECPError: Error {
        case requestFailed(String)
        case badKeypress(RemoteButton)
        case badInterface(NWInterface?)
        case sendFailed(NWError)
        case connectionFailed
        case notImplemented
        case badTexteditId
        case invalidResponse
    }

    var websocketStateUpdated: ECPStateCallback
    var notificationhandler: ECPNotificationCallback
    var responseHandlers: [String: ECPResponseCompletion]

    var connection: NWConnection
    var internalState: ECPWebsocketState

    var state: ECPWebsocketState {
        internalState
    }

    private let errorWhileWaitingLimit = 2
    private var errorWhileWaitingCount = 0

    private var inError: Bool = false

    private let uuid = UUID()

    let endpoint: NWEndpoint
    let macs: [String]

    var requestId = 3

    let connectionQueue: DispatchQueue = DispatchQueue(label: "ECP Websocket Session Queue", qos: .userInitiated)

    init (location: URL, macs: [String] = [], websocketStateUpdated: @escaping ECPStateCallback = {_ in }, notificationHandler: @escaping ECPNotificationCallback = {_ in }) {
        self.websocketStateUpdated = websocketStateUpdated
        self.notificationhandler = notificationHandler
        self.responseHandlers = [:]
        self.internalState = .connecting(.now)

        endpoint = NWEndpoint.url(location)
        connection = NWConnection(to: endpoint, using: NWParameters.ecp)
        self.macs = macs
    }

    deinit {
        if self.connection.state != .cancelled {
            self.connection.cancel()
        }
        let staleHandlers = self.responseHandlers
        self.responseHandlers = [:]
        Self.logger.info("De-initting \(self.uuid) for \(self.endpoint.debugDescription)")
        for handler in staleHandlers.values {
            handler(.failure(.connectionFailed))
        }

    }

    public func cancel() {
        if self.connection.state != .cancelled {
            self.connection.cancel()
        }
    }

    private func newRequestId() -> String {
        let reqId = String(requestId)
        requestId += 1
        return reqId
    }

    public func run<T: Sendable>(_ block: (isolated ECPWebsocketClient) async throws -> T) async rethrows -> T {
        return try await block(self)
    }

    public func oneOff<T: Sendable>(timeout: TimeInterval = 5, _ block: @escaping @Sendable (isolated ECPWebsocketClient) async throws -> T) async throws -> T {
        Self.logger.info("Running quick oneoff with id \(self.uuid) for endpoint \(self.endpoint.debugDescription)")
        self.start()
        defer {
            self.cancel()
        }

        return try await withTimeout(delay: timeout) {
            return try await self.run(block)
        }
    }

    public nonisolated func pressCharacter(_ character: Character) async throws {
        let keypress = getKeypressForKey(key: character)
        try await self.sendKey(keypress)
    }

    public nonisolated func pressButton(_ button: RemoteButton) async throws {
        guard button != .power else {
            await powerToggleDevice()
            return
        }

        guard let keypress = button.apiValue else {
            Self.logger.fault("Bad key with no api value \(button.description, privacy: .public)")
            throw ECPError.badKeypress(button)
        }

        try await self.sendKey(keypress)
    }

    @discardableResult
    public nonisolated func sendCommand(_ command: ECPRequestMessage, timeout: TimeInterval = 5) async throws -> ECPResponse {
        let reqId = await self.newRequestId()
        Self.logger.info("Sending command \(String(describing: command)) with id \(reqId))")

        let response = try await withTaskCancellationHandler {
            try await withTimeout(delay: timeout) {
                try await withCheckedThrowingContinuation { continuation in
                    Task {
                        await self.sendMessage(command.withId(reqId), timeout: timeout, completion: { response in
                            Self.logger.info("Got response for message \(String(describing: response)) with id \(reqId)")
                            switch response {
                            case .success(let response):
                                continuation.resume(returning: response)
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        })
                    }
                }
            }
        } onCancel: {
            Task {
                Self.logger.info("Cancelling self due to sendCommand getting cancelled")
                await self.cancel()
            }
        }

        guard response.isSuccess else {
            throw ECPError.requestFailed(response.status)
        }
        return response
    }

    private nonisolated func sendKey(_ string: String, delay: TimeInterval = 5) async throws {
        try await self.sendCommand(.keyPress(KeyPressRequest(key: string, requestId: "")), timeout: delay)
    }

    public nonisolated func launchApp(_ appId: String, params: [String: String]? = nil) async throws {
        try await self.sendCommand(.launchApp(AppLaunchRequest(requestId: "", channelId: appId, params: params)))
    }

    public nonisolated func setTextEdit(_ text: String, texteditId: String) async throws {
        guard texteditId != "none" else {
            Self.logger.error("Can't set textedit state with 'none' Textedit ID")
            throw ECPError.badTexteditId
        }

        try await self.sendCommand(.setTexteditState(SetTexteditStateRequest(requestId: "", text: text, texteditId: texteditId)))
    }

    public nonisolated func getDeviceInfo() async throws -> DeviceInfo {
        let result = try await self.sendCommand(.queryDeviceInfo(QueryDeviceInfo(requestId: "")))
        // Parse device info from result
        switch result {
        case .base(let resp):
            guard let data = resp.contentData else {
                throw ECPError.invalidResponse
            }
            let decoder = XMLDecoder()
            decoder.keyDecodingStrategy = .convertFromKebabCase
            do {
                return try decoder.decode(DeviceInfo.self, from: data)
            } catch {
                Self.logger.error("Error decoding DeviceInfo response \(error, privacy: .public)")
                throw ECPError.invalidResponse
            }
        }
    }

    public nonisolated func getDeviceCapabilities() async throws -> DeviceCapabilities {
        let result = try await self.sendCommand(.queryDeviceCapabilities(QueryAudioDevice(requestId: "")))
        Self.logger.info("Got result \(String(reflecting: result))")
        switch result {
        case .base(let resp):
            guard let data = resp.contentData else {
                throw ECPError.invalidResponse
            }

            let decoder = XMLDecoder()
            let audioDevice = try decoder.decode(AudioDevice.self, from: data)

            let isDatagramSupported = audioDevice.capabilities.allDestinations?.contains("datagram")
            let rtcpPort = audioDevice.rtpInfo?.rtcpPort

            return DeviceCapabilities(supportsDatagram: isDatagramSupported ?? false, rtcpPort: rtcpPort)
        }
    }

    public nonisolated func getDeviceApps() async throws -> [AppLinkAppEntity] {
        let result = try await self.sendCommand(.queryDeviceApps(QueryApps(requestId: "")))
        Self.logger.info("Got result \(String(reflecting: result))")
        switch result {
        case .base(let resp):
            guard let data = resp.contentData else {
                throw ECPError.invalidResponse
            }

            let decoder = XMLDecoder()
            let apps = try decoder.decode(Apps.self, from: data)

            return apps.app.map { $0.toAppEntity() }
        }
    }

    public nonisolated func getDeviceAppIcon(_ appId: String) async throws -> Data {
        let result = try await self.sendCommand(.queryAppIcon(QueryAppIcon(requestId: "", channelId: appId)))
        Self.logger.info("Got result \(String(reflecting: result))")
        switch result {
        case .base(let resp):
            guard let data = resp.contentData, let contentType = resp.contentType else {
                throw ECPError.invalidResponse
            }

            return try await decodeImage(data: data, mimeType: contentType)
        }
    }

    public nonisolated func requestEventsNotify() async throws {
        // +media-player-state-changed,+power-mode-changed,+volume-changed
        // +ecs-microphone-start,+ecs-microphone-stop,+audio-setting-changed,+audio-settings-invalidated
        try await self.sendCommand(.requestEventsNotify(EventsNotifyRequest(requestId: "", events: "+textedit-opened,+textedit-changed,+textedit-closed")))
    }

    public nonisolated func powerToggleDevice() async {
        await withDiscardingTaskGroup { taskGroup in
            taskGroup.addTask {
                try? await Task.sleep(for: .milliseconds(200))
                Self.logger.info("Sending wol to wakeup if not already awake")
                await sendWolToDevice(macs: self.macs)
            }

            taskGroup.addTask {
                try? await self.sendKey(RemoteButton.power.apiValue!, delay: 0.5)
            }
        }
    }

    public func requestHeadphonesMode() async throws {
        guard let connectingInterface = connection.currentPath?.remoteEndpoint?.interface else {
            Self.logger.info("Error requesting headphones mode: no path")
            throw ECPError.badInterface(nil)
        }

        let localInterfaces = await allAddressedInterfaces()
        guard let localNWInterface = localInterfaces
            .first(where: { connectingInterface.name == $0.name && $0.isIPv4 })
        else {
            Self.logger
                .error(
                    "Connected with interface \(connectingInterface.name, privacy: .public) but no match in \(localInterfaces.map(\.name), privacy: .public)"
                )
            throw ECPError.badInterface(connectingInterface)
        }
        let localAddress = localNWInterface.address.addressString
        Self.logger.debug("Got local address for PL request \(localAddress, privacy: .public)")

        try await self.sendCommand(.configureAudio(ConfigureAudioRequest.headphonesMode(
            hostIp: localAddress,
            requestId: ""
        )))
    }

    private func sendMessage(_ message: ECPRequestMessage, timeout: TimeInterval? = nil, completion: @escaping ECPResponseCompletion) {
        if self.inError {
            Self.logger.info("Restarting on send message because we are in error state")
            self.start()
        }
        Self.logger.info("Current response handlers \(self.responseHandlers.count) and new request \(message.requestId) with state \(self.state.debugDescription) and ws state \(String(describing: self.connection.state))")
        self.responseHandlers[message.requestId] = completion
        let metadata = NWProtocolFramer.Message(ecpRequest: message)
        let context = NWConnection.ContentContext(
            identifier: "ecpMessage",
            expiration: UInt64((timeout ?? 0) * 1000),
            metadata: [metadata]
        )

        self.connection.send(
            content: nil,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed({ [weak self] error in
                guard let self = self else {
                    return
                }
                if let error {
                    Task {
                        await self.handleError(error, requestId: message.requestId)
                    }
                }
            })
        )
    }

    private func clearHandlers() {
        Self.logger.info("Clearing handlers")
        let staleHandlers = self.responseHandlers
        self.responseHandlers = [:]
        for handler in staleHandlers.values {
            handler(.failure(.connectionFailed))
        }
    }

    public func start() {
        if connection.state != .cancelled {
            Self.logger.info("Cancelling existing connection to restart")
            connection.cancel()
        }
        connection = NWConnection(to: endpoint, using: NWParameters.ecp)
        self.clearHandlers()
        Self.logger.info("No longer in error b/c restarting")
        self.inError = false
        connection.pathUpdateHandler = { [weak self] path in
            guard let self else {
                return
            }
            Task {
                await self.pathDidChange(to: path)
            }
        }
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else {
                return
            }
            Task {
                await self.stateDidChange(to: state)
            }
        }
        connection.betterPathUpdateHandler = { [weak self] isAvailable in
            guard let self else {
                return
            }
            Task {
                await self.betterPath(isAvailable: isAvailable)
            }
        }
        connection.viabilityUpdateHandler = { [weak self] isViable in
            guard let self else {
                return
            }
            Task {
                await self.viabilityDidChange(isViable: isViable)
            }
        }

        self.reportStateChange(.connecting(.now))
        connection.start(queue: connectionQueue)
        self.listen()
    }

    private func listen() {
        connection.receiveMessage { [weak self] (_, context, _, error) in
            Self.logger.info("Triggering receive message")

            guard let self = self else {
                return
            }

            if let error = error {
                Task {
                    await self.handleError(error)
                }
                return
            } else {
                Task {
                    await self.listen()
                }
            }

            if let context = context {
                Task {
                    await self.receiveMessage(context: context)
                }
            } else {
                Self.logger.info("No data or context")
            }

        }
    }

    private func handleError(_ error: NWError, requestId: String? = nil) {
        Self.logger.info("In error because getting req error")
        self.inError = true
        if let requestId {
            Self.logger.info("Getting error for req \(requestId)")
            self.responseHandlers.removeValue(forKey: requestId)?(.failure(.sendFailed(error)))
        } else {
            self.clearHandlers()
        }
    }

    private func receiveMessage(context: NWConnection.ContentContext) {
        guard let metadata = context.protocolMetadata(definition: ECPProtocol.definition) as? NWProtocolFramer.Message else {
            Self.logger.warning("Received data without message")
            return
        }
        guard let response = metadata.ecpResponse else {
            Self.logger.warning("Received message without ECP response metadata")
            return
        }

        switch response {
        case .notify(let notify):
            self.notificationhandler(notify)
        case .response(let response):
            Self.logger.info("Getting success for req \(response.responseId)")
            if let handler = self.responseHandlers.removeValue(forKey: response.responseId) {
                handler(.success(response))
            } else {
                Self.logger.warning("Received ECP handler for unknown response ID \(response.responseId)")
            }
        }
    }

    func reportStateChange(_ newState: ECPWebsocketState) {
        Self.logger.info("Reporting new state \(newState.debugDescription)")
        switch (self.state, newState) {
        case (.connecting(_), .connecting(_)), (.disconnected(_), .disconnected(_)), (.connected, .connected):
            Self.logger.info("Ignoring state change because it is the same \(String(describing: newState), privacy: .public)")
            return
        case (.connected, .connecting(_)), (.connected, .disconnected(_)), (.disconnected(_), .connected), (.connecting(_), .connected):
            Self.logger.info("Entering new state \(String(describing: newState), privacy: .public) from \(String(describing: self.state), privacy: .public)")
            self.internalState = newState
        case (.connecting(let date), .disconnected(_)):
            Self.logger.info("Disconnecting after attempting connection")
            self.internalState = .disconnected(date)
        case (.disconnected(let date), .connecting(_)):
            Self.logger.info("connecting after being disconnected")
            self.internalState = .connecting(date)
        }
        self.websocketStateUpdated(self.state)
    }

    func stateDidChange(to state: NWConnection.State) {
        Self.logger.info("WS State changed to \(String(describing: state), privacy: .public)")

        switch state {
        case .ready:
            Self.logger.info("No longer in error with state \(String(describing: state))")
            self.inError = false
            self.reportStateChange(.connected)
        case .waiting(let error):
            self.reportStateChange(.connecting(.now))
            Self.logger.info("In waiting state, failing with error \(error, privacy: .public). Currently in state \(String(describing: self.connection.state), privacy: .public)")
            self.inError = true

            /// Workaround to prevent loop while reconnecting
            errorWhileWaitingCount += 1
            if errorWhileWaitingCount >= errorWhileWaitingLimit {
                self.cancel()
            }
        case .failed(let error):
            Self.logger.info("In error with state \(String(describing: state))")
            self.inError = true
            self.handleError(error)
            self.reportStateChange(.disconnected(.now))
        case .setup, .preparing:
            Self.logger.info("No longer in error with state \(String(describing: state))")
            self.inError = false
            errorWhileWaitingCount = 0
            self.reportStateChange(.connecting(.now))
        case .cancelled:
            Self.logger.info("In error with state \(String(describing: state))")
            self.inError = true
            self.reportStateChange(.disconnected(.now))
        @unknown default:
            Self.logger.warning("Unknown state \(String(describing: state), privacy: .public)")
        }
    }

    func betterPath(isAvailable: Bool) {
        if isAvailable {
            Self.logger.info("Reconnecting with better path")
        } else {
            Self.logger.info("Not reconnecting because no better path available")
        }
    }

    func pathDidChange(to path: NWPath) {
        Self.logger.info("WS path changed to \(String(describing: path), privacy: .public)")
    }

    func viabilityDidChange(isViable: Bool) {
        if isViable {
            self.reportStateChange(.connected)
        } else {
            self.reportStateChange(.disconnected(.now))
        }
        Self.logger.info("Network viability changed \(isViable, privacy: .public)")
    }
}
#endif
