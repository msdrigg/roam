#if !os(watchOS)
import Network
import Dispatch
import OSLog

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

actor ECPWebsocketClient {
    enum ECPError: Error {
        case requestFailed(String)
        case badKeypress(RemoteButton)
        case noValidInterface([NWInterface])
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

    private let maxInFlightVolumeCommands = 2
    private var inFlightVolumeCommands: Int = 0

    private var inError: Bool = false

    private let uuid = UUID()

    let endpoint: NWEndpoint
    let macs: [String]

    static let baseRequestId = 2
    var requestId = 2

    let connectionQueue: DispatchQueue = DispatchQueue.networkQueue

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
        Log.connection.notice("De-initting \(self.uuid, privacy: .public) for \(self.endpoint.debugDescription, privacy: .public)")
        for handler in staleHandlers.values {
            handler(.failure(.connectionFailed))
        }

    }

    public func cancel() {
        if self.connection.state != .cancelled {
            self.connection.cancel()
        }
        self.clearHandlers()
    }

    private func newRequestId() -> String {
        let reqId = String(requestId)
        requestId += 1
        return reqId
    }

    public func run<T: Sendable>(_ block: (isolated ECPWebsocketClient) async throws -> T) async rethrows -> T {
        return try await block(self)
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
            Log.connection.fault("Bad key with no api value \(button.description, privacy: .public)")
            throw ECPError.badKeypress(button)
        }

        if button == .volumeUp || button == .volumeDown {
            guard await self.tryReserveVolumeSlot() else {
                Log.connection.notice("Dropping \(button.description, privacy: .public) — in-flight volume cap reached")
                return
            }
            do {
                try await self.sendKey(keypress)
            } catch {
                await self.releaseVolumeSlot()
                throw error
            }
            await self.releaseVolumeSlot()
            return
        }

        try await self.sendKey(keypress)
    }

    @discardableResult
    public nonisolated func sendCommand(_ command: ECPRequestMessage, timeout: TimeInterval = 5) async throws -> ECPResponse {
        Log.connection.notice("Sending command \(command.debugDescription, privacy: .public)")

        let response = try await withTaskCancellationHandler {
            try await withTimeout(delay: timeout) {
                try await withCheckedThrowingContinuation { continuation in
                    Task {
                        await self.sendMessage(command, timeout: timeout, completion: { response in
                            switch response {
                            case .success(let response):
                                Log.connection.notice("Got success response for message \(response.debugDescription, privacy: .public)")
                                continuation.resume(returning: response)
                            case .failure(let error):
                                Log.connection.notice("Got failure for command \(command.debugDescription, privacy: .public)")
                                continuation.resume(throwing: error)
                            }
                        })
                    }
                }
            }
        } onCancel: {
            Task {
                Log.connection.notice("Cancelling self due to sendCommand getting cancelled")
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
            Log.connection.error("Can't set textedit state with 'none' Textedit ID")
            throw ECPError.badTexteditId
        }

        try await self.sendCommand(.setTexteditState(SetTexteditStateRequest(requestId: "", text: text, texteditId: texteditId)))
    }

#if !WIDGET
    public nonisolated func getDeviceInfo() async throws -> DeviceInfo {
        let result = try await self.sendCommand(.queryDeviceInfo(QueryDeviceInfo(requestId: "")))
        // Parse device info from result
        switch result {
        case .base(let resp):
            guard let data = resp.contentData else {
                throw ECPError.invalidResponse
            }
            let decoder = XMLStreamDecoder(.convertFromKebabCase)
            do {
                return try decoder.decode(DeviceInfo.self, from: data)
            } catch {
                Log.connection.error("Error decoding DeviceInfo response \(error, privacy: .public)")
                throw ECPError.invalidResponse
            }
        }
    }

    public nonisolated func getDeviceCapabilities() async throws -> DeviceCapabilities {
        let result = try await self.sendCommand(.queryDeviceCapabilities(QueryAudioDevice(requestId: "")))
        switch result {
        case .base(let resp):
            guard let data = resp.contentData else {
                Log.connection.notice("Error getting device capaibilities -- no content data")
                throw ECPError.invalidResponse
            }

            let decoder = XMLStreamDecoder()
            let audioDevice = try decoder.decode(AudioDevice.self, from: data)

            let isDatagramSupported = audioDevice.capabilities.allDestinations?.contains("datagram")
            let rtcpPort = audioDevice.rtpInfo?.rtcpPort

            return DeviceCapabilities(supportsDatagram: isDatagramSupported ?? false, rtcpPort: rtcpPort)
        }
    }

    public nonisolated func getDeviceApps() async throws -> [ AppLink] {
        let result = try await self.sendCommand(.queryDeviceApps(QueryApps(requestId: "")))
        switch result {
        case .base(let resp):
            guard let data = resp.contentData else {
                Log.connection.notice("Error getting device apps -- no content data")
                throw ECPError.invalidResponse
            }

            let decoder = XMLStreamDecoder()
            let apps: Apps
            do {
                apps = try decoder.decode(Apps.self, from: data)
            } catch {
                let responseBody = String(bytes: data, encoding: .utf8) ?? data.toHexString()
                Log.connection.error("Error decoding Apps response \(error, privacy: .public). Received \(data.count, privacy: .public) bytes: \(responseBody, privacy: .public)")
                throw error
            }

            return apps
        }
    }
#endif

    public nonisolated func getDeviceAppIcon(_ appId: String) async throws -> Data {
        let result = try await self.sendCommand(.queryAppIcon(QueryAppIcon(requestId: "", channelId: appId)))
        switch result {
        case .base(let resp):
            guard let data = resp.contentData, let contentType = resp.contentType else {
                Log.connection.notice("Error getting device app icon -- no content data")
                throw ECPError.invalidResponse
            }

            return try await decodeImage(data: data, mimeType: contentType)
        }
    }

    public nonisolated func requestEventsNotify(events: String? = nil) async throws {
        // +media-player-state-changed,+power-mode-changed,+volume-changed
        // +ecs-microphone-start,+ecs-microphone-stop,+audio-setting-changed,+audio-settings-invalidated
        try await self.sendCommand(.requestEventsNotify(EventsNotifyRequest(requestId: "", events: events ?? "+textedit-opened,+textedit-changed,+textedit-closed")))
    }

    public nonisolated func powerToggleDevice() async {
        await withDiscardingTaskGroup { taskGroup in
            taskGroup.addTask {
                try? await Task.sleep(for: .milliseconds(200))
                Log.connection.notice("Sending wol to wakeup if not already awake")
                await sendWolToDevice(macs: self.macs)
            }

            taskGroup.addTask {
                try? await self.sendKey(RemoteButton.power.apiValue!, delay: 0.5)
            }
        }
    }

    public func requestHeadphonesMode() async throws {
        guard let connectingInterfaces = connection.currentPath?.availableInterfaces else {
            Log.connection.notice("Error requesting headphones mode: no path")
            throw ECPError.noValidInterface([])
        }

        let localInterfaces = await allAddressedInterfaces()
        guard let localNWInterface = connectingInterfaces.compactMap({ connectingInterface in
            localInterfaces
                .first(where: { connectingInterface.name == $0.name && $0.isIPv4 })
        }).first else {
            Log.connection
                .error(
                    "Connected with interfaces \(connectingInterfaces.map(\.name), privacy: .public) but no match in \(localInterfaces.map(\.name), privacy: .public)"
                )
            throw ECPError.noValidInterface(connectingInterfaces)
        }
        let localAddress = localNWInterface.address.addressString
        Log.connection.notice("Got local address for PL request \(localAddress, privacy: .public)")

        try await self.sendCommand(.configureAudio(ConfigureAudioRequest.headphonesMode(
            hostIp: localAddress,
            requestId: ""
        )))
    }

    private func sendMessage(_ inputMessage: ECPRequestMessage, timeout: TimeInterval? = nil, completion: @escaping ECPResponseCompletion) {
        if self.inError {
            Log.connection.notice("Restarting on send message because we are in error state")
            self.start()
        }
        let reqId = self.newRequestId()
        let message = inputMessage.withId(reqId)

        Log.connection.notice("Current response handlers \(self.responseHandlers.count, privacy: .public) and new request \(message.requestId, privacy: .public) with state \(self.state.debugDescription, privacy: .public) and ws state \(String(describing: self.connection.state), privacy: .public)")
        self.responseHandlers[reqId] = completion
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

    private func tryReserveVolumeSlot() -> Bool {
        guard inFlightVolumeCommands < maxInFlightVolumeCommands else {
            return false
        }
        inFlightVolumeCommands += 1
        return true
    }

    private func releaseVolumeSlot() {
        if inFlightVolumeCommands > 0 {
            inFlightVolumeCommands -= 1
        }
    }

    private func clearHandlers() {
        Log.connection.notice("Clearing handlers")
        let staleHandlers = self.responseHandlers
        self.responseHandlers = [:]
        self.requestId = Self.baseRequestId
        for handler in staleHandlers.values {
            handler(.failure(.connectionFailed))
        }
    }

    public func start() {
        if connection.state != .cancelled {
            Log.connection.notice("Cancelling existing connection to restart")
            connection.cancel()
        }
        connection = NWConnection(to: endpoint, using: NWParameters.ecp)
        self.clearHandlers()
        Log.connection.notice("No longer in error b/c restarting")
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

        self.reportStateChange(.connecting(.distantPast))
        connection.start(queue: connectionQueue)
        self.listen()
    }

    private func listen() {
        connection.receiveMessage { [weak self] (_, context, _, error) in
            guard let self = self else {
                Log.connection.warning("Triggering receive message with no self")
                return
            }

            if let error = error {
                Log.connection.warning("Triggering receive message with error")
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
                Log.connection.warning("No data context in message")
            }
        }
    }

    private func handleError(_ error: NWError, requestId: String? = nil) {
        Log.connection.notice("In error because getting req error")
        self.inError = true
        if let requestId {
            Log.connection.notice("Getting error for req \(requestId, privacy: .public)")
            self.responseHandlers.removeValue(forKey: requestId)?(.failure(.sendFailed(error)))
        }
        self.cancel()
    }

    private func receiveMessage(context: NWConnection.ContentContext) {
        guard context.protocolMetadata.count != 0 || !context.isFinal else {
            Log.connection.notice("Received final message unexpectedly. Shutting down now")
            return
        }
        guard let metadata = context.protocolMetadata(definition: ECPProtocol.definition) as? NWProtocolFramer.Message else {
            Log.connection.warning("Received data without ecp message")
            return
        }
        guard let response = metadata.ecpResponse else {
            Log.connection.warning("Received message without ECP response metadata")
            return
        }

        switch response {
        case .notify(let notify):
            Log.connection.notice("Getting notify \(notify.notifyType.rawValue, privacy: .public)")
            self.notificationhandler(notify)
        case .response(let response):
            Log.connection.notice("Getting success for req \(response.responseId, privacy: .public): \(response.responseType, privacy: .public)")
            if let handler = self.responseHandlers.removeValue(forKey: response.responseId) {
                handler(.success(response))
            } else {
                Log.connection.warning("Received ECP handler for unknown response ID \(response.responseId, privacy: .public)")
            }
        }
    }

    func reportStateChange(_ newState: ECPWebsocketState) {
        switch (self.state, newState) {
        case (.connecting(_), .connecting(_)), (.disconnected(_), .disconnected(_)), (.connected, .connected):
            Log.connection.notice("Ignoring state change because it is the same \(String(describing: newState), privacy: .public)")
            return
        case (.connected, .connecting(_)), (.connected, .disconnected(_)), (.disconnected(_), .connected), (.connecting(_), .connected):
            Log.connection.notice("Entering new state \(String(describing: newState), privacy: .public) from \(String(describing: self.state), privacy: .public)")
            self.internalState = newState
        case (.connecting(let date), .disconnected(_)):
            Log.connection.notice("Disconnecting after attempting connection")
            self.internalState = .disconnected(date)
        case (.disconnected(let date), .connecting(_)):
            Log.connection.notice("connecting after being disconnected")
            self.internalState = .connecting(date)
        }
        self.websocketStateUpdated(self.state)
    }

    func stateDidChange(to state: NWConnection.State) {
        switch state {
        case .ready:
            Log.connection.notice("No longer in error with state \(String(describing: state), privacy: .public)")
            self.reportStateChange(.connected)
            self.inError = false
        case .waiting(let error):
            Log.connection.notice("In waiting state, failing with error \(error, privacy: .public). Currently in state \(String(describing: self.connection.state), privacy: .public)")
            self.reportStateChange(.connecting(.now))
            self.inError = true

            /// Workaround to prevent loop while reconnecting
            errorWhileWaitingCount += 1
            if errorWhileWaitingCount >= errorWhileWaitingLimit {
                Log.connection.notice("Cancelling after \(self.errorWhileWaitingLimit, privacy: .public) errors in waiting state")
                self.cancel()
            }
        case .failed(let error):
            Log.connection.notice("In error with state \(String(describing: state), privacy: .public)")
            self.reportStateChange(.disconnected(.now))
            self.inError = true
            self.handleError(error)
        case .setup, .preparing:
            Log.connection.notice("No longer in error with state \(String(describing: state), privacy: .public)")
            self.reportStateChange(.connecting(.now))
            self.inError = false
            errorWhileWaitingCount = 0
        case .cancelled:
            Log.connection.notice("In error with state \(String(describing: state), privacy: .public)")
            self.reportStateChange(.disconnected(.now))
            self.inError = true
        @unknown default:
            Log.connection.warning("Unknown state \(String(describing: state), privacy: .public)")
        }
    }

    func betterPath(isAvailable: Bool) {
        if isAvailable {
            Log.connection.notice("Reconnecting with better path")
        } else {
            Log.connection.notice("Not reconnecting because no better path available")
        }
    }

    func pathDidChange(to path: NWPath) {
        Log.connection.notice("WS path changed to \(String(describing: path), privacy: .public)")
    }

    func viabilityDidChange(isViable: Bool) {
        if isViable {
            self.reportStateChange(.connected)
        } else {
            self.reportStateChange(.disconnected(.now))
        }
        Log.connection.notice("Network viability changed \(isViable, privacy: .public)")
    }
}

extension ECPWebsocketClient {
    public func oneOff<T: Sendable>(timeout: TimeInterval = 5, _ block: @escaping @Sendable (isolated ECPWebsocketClient) async throws -> T) async throws -> T {
        Log.connection.notice("Running quick oneoff with id \(self.uuid, privacy: .public) for endpoint \(self.endpoint.debugDescription, privacy: .public)")
        self.start()
        defer {
            self.cancel()
        }

        return try await withTimeout(delay: timeout) {
            return try await self.run(block)
        }
    }
}
#endif
