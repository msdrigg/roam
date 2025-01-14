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
let requestTimeout: Int = 5

actor ECPSession {
    nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ECPSession.self)
    )

    static let messageReceivedNotification: NSNotification.Name = .init("com.msdrigg.ECPSession.messageReceived")
    static let websocketStateUpdatedNotification: NSNotification.Name = .init("com.msdrigg.ECPSession.websocketStateUpdated")

    let location: String
    let macs: [String]
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
        case notImplemented
        case responseRejection(code: String)
    }

    private static var websocketParameters: NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionDropTime = requestTimeout
        tcpOptions.connectionTimeout = requestTimeout
        tcpOptions.keepaliveCount = requestTimeout
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveInterval = requestTimeout
        tcpOptions.persistTimeout = requestTimeout
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let options = NWProtocolWebSocket.Options()
        options.setSubprotocols(["ecp-2"])
        options.autoReplyPing = true

        params.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        return params
    }

    public init(location: String, macs: [String], status: ECPSessionState) throws {
        Self.logger.info("Initing ECP Session with url \(location, privacy: .public)")
        // swiftlint:disable:next force_try
        guard let url = URL(string: "\(location.replacing(try! Regex("^http:"), with: "ws:"))ecp-session") else {
            Self.logger.error("Bad url for location \(location, privacy: .public)ecp-session")
            throw ECPError.badURL
        }
        self.url = url
        self.endpoint = NWEndpoint.url(url)

        self.status = status
        self.macs = macs
        self.location = location

        Task {
            await self.initObservers()
        }
    }

    public init(device: DeviceAppEntity, status: ECPSessionState) throws {
        Self.logger.info("Initing ECP Session with url \(device.location, privacy: .public)")
        // swiftlint:disable:next force_try
        guard let url = URL(string: "\(device.location.replacing(try! Regex("^http:"), with: "ws:"))ecp-session") else {
            Self.logger.error("Bad url for location \(device.location, privacy: .public)ecp-session")
            throw ECPError.badURL
        }
        self.url = url
        self.endpoint = NWEndpoint.url(url)

        self.status = status
        self.location = device.location
        self.macs = device.macs()

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
                    Self.logger.error("Error getting response from notify: \(error, privacy: .public)")
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
        NotificationCenter.default.post(name: Self.websocketStateUpdatedNotification, object: nil, userInfo: ["websocketState": status])
        let currentStatus = self.status

        DispatchQueue.main.async {
            Self.logger.info("WS Status updating to \(String(describing: status), privacy: .public) from \(String(describing: currentStatus.status), privacy: .public)")
            switch (currentStatus.status, status) {
            case (.disconnected, .disconnected), (.connecting, .connecting):
                Self.logger.info("WS Status update ignored")
            case (.connecting, .disconnected):
                currentStatus.status = .disconnected(.distantPast)
                Self.logger.info("WS Status updated to distant past")
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
                Self.logger.info("Not reconfiguring because doing it already")
                return
            }
            Self.logger.info("Reconfiguring existing connection")
            self.websocketStateUpdated(status: .connecting(.now))
            switch connection.state {
            case NWConnection.State.cancelled, .failed:
                self.triggerReconnect()
                throw ECPError.connectFailed
            case let NWConnection.State.waiting(waiting):
                Self.logger.info("Waiting for \(waiting, privacy: .public), so reconnecging...")
                self.triggerReconnect()
                throw ECPError.connectFailed
            case .ready, .preparing, .setup:
                Self.logger.info("Returning because state is OK (\(String(describing: connection.state), privacy: .public))")
            @unknown default:
                Self.logger.info("Unknown connection state: \(String(describing: connection.state), privacy: .public)")
            }
        } else {
            Self.logger.info("Reconfiguring new connection")
            self.websocketStateUpdated(status: .connecting(.now))
            let connection = NWConnection(to: endpoint, using: ECPSession.websocketParameters)

            requestIdCounter = 0

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
    }

    public func listen() {
        connection?.receiveMessage { [weak self] (data, context, _, error) in
            guard let self = self else {
                return
            }

            Task {
                if let data = data, let context = context {
                    await self.receiveMessage(data: data, context: context)
                    self.websocketStateUpdated(status: .connected)
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
            isMigratingConnection = false
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
        Self.logger.info("Network viability changed \(isViable, privacy: .public)")
    }

    private func reportDisconnection(closeCode: NWProtocolWebSocket.CloseCode, reason: Data?) {
        self.websocketStateUpdated(status: .disconnected(.now))
        let reasonText = String(data: reason ?? .init(), encoding: .utf8) ?? "No reason text"
        Self.logger.error("Websocket closed with reason \(reasonText, privacy: .public) code \(String(describing: closeCode), privacy: .public)")
    }

    private func reportErrorOrDisconnection(_ error: any Error) {
        self.websocketStateUpdated(status: .disconnected(.now))
        Self.logger.error("Error from websocket \(error, privacy: .public)")
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
                    Self.logger.info("Received notification \(String(describing: notification.name), privacy: .public)")
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
        Self.logger.info("Received ws message: \(string, privacy: .public)")

        if let data = string.data(using: .utf8) {
            do {
                let response = try kebabDecoder.decode(ResponseIdDecoder.self, from: data)
                var userInfo: [String: Any] = ["data": data]
                Self.logger.info("Received response id \(String(describing: response.responseId), privacy: .public) or message")
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

        try await send(data: Data("ping".utf8), context: context)
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

    func getDeviceAppIcon(_ appId: String) async throws -> Data {
        throw Self.ECPError.notImplemented
    }

    func getDeviceIcon() async throws -> Data {
        throw Self.ECPError.notImplemented
    }

    func getDeviceInfo() async throws -> DeviceInfo {
        throw Self.ECPError.notImplemented
//        {"request":"query-device-info","request-id":"2"}
//        {"content-data":"PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiID8+CjxkZXZpY2UtaW5mbz4KCTx1ZG4+MjgwMDEyNDAtMDAwMC0xMDAwLTgwMDAtODBjYmJjOTg3OTBhPC91ZG4+Cgk8dmlydHVhbC1kZXZpY2UtaWQ+UzBBMzYxOUdOOFVZPC92aXJ0dWFsLWRldmljZS1pZD4KCTxzZXJpYWwtbnVtYmVyPlgwMTkwMFNHTjhVWTwvc2VyaWFsLW51bWJlcj4KCTxkZXZpY2UtaWQ+UzBBMzYxOUdOOFVZPC9kZXZpY2UtaWQ+Cgk8YWR2ZXJ0aXNpbmctaWQ+OWVlYmYxNTEtZTUxOS01NzRiLThkZTItOWUwODUzOTBjNDFkPC9hZHZlcnRpc2luZy1pZD4KCTx2ZW5kb3ItbmFtZT5IaXNlbnNlPC92ZW5kb3ItbmFtZT4KCTxtb2RlbC1uYW1lPjZTZXJpZXMtNTA8L21vZGVsLW5hbWU+Cgk8bW9kZWwtbnVtYmVyPkcyMThYPC9tb2RlbC1udW1iZXI+Cgk8bW9kZWwtcmVnaW9uPlVTPC9tb2RlbC1yZWdpb24+Cgk8aXMtdHY+dHJ1ZTwvaXMtdHY+Cgk8aXMtc3RpY2s+ZmFsc2U8L2lzLXN0aWNrPgoJPHNjcmVlbi1zaXplPjUwPC9zY3JlZW4tc2l6ZT4KCTxwYW5lbC1pZD43PC9wYW5lbC1pZD4KCTxtb2JpbGUtaGFzLWxpdmUtdHY+dHJ1ZTwvbW9iaWxlLWhhcy1saXZlLXR2PgoJPHVpLXJlc29sdXRpb24+MTA4MHA8L3VpLXJlc29sdXRpb24+Cgk8dHVuZXItdHlwZT5BVFNDPC90dW5lci10eXBlPgoJPHN1cHBvcnRzLWV0aGVybmV0PnRydWU8L3N1cHBvcnRzLWV0aGVybmV0PgoJPHdpZmktbWFjPjgwOmNiOmJjOjk4Ojc5OjBhPC93aWZpLW1hYz4KCTx3aWZpLWRyaXZlcj5yZWFsdGVrPC93aWZpLWRyaXZlcj4KCTxoYXMtd2lmaS01Ry1zdXBwb3J0PnRydWU8L2hhcy13aWZpLTVHLXN1cHBvcnQ+Cgk8ZXRoZXJuZXQtbWFjPmEwOjYyOmZiOjc4OjI5OmVlPC9ldGhlcm5ldC1tYWM+Cgk8bmV0d29yay10eXBlPmV0aGVybmV0PC9uZXR3b3JrLXR5cGU+Cgk8ZnJpZW5kbHktZGV2aWNlLW5hbWU+SGlzZW5zZeKAolJva3UgVFYgLSBYMDE5MDBTR044VVk8L2ZyaWVuZGx5LWRldmljZS1uYW1lPgoJPGZyaWVuZGx5LW1vZGVsLW5hbWU+SGlzZW5zZeKAolJva3UgVFY8L2ZyaWVuZGx5LW1vZGVsLW5hbWU+Cgk8ZGVmYXVsdC1kZXZpY2UtbmFtZT5IaXNlbnNl4oCiUm9rdSBUViAtIFgwMTkwMFNHTjhVWTwvZGVmYXVsdC1kZXZpY2UtbmFtZT4KCTx1c2VyLWRldmljZS1uYW1lIC8+Cgk8dXNlci1kZXZpY2UtbG9jYXRpb24gLz4KCTxidWlsZC1udW1iZXI+Q0hELjUwRTA0MTc2QTwvYnVpbGQtbnVtYmVyPgoJPHNvZnR3YXJlLXZlcnNpb24+MTIuNS4wPC9zb2Z0d2FyZS12ZXJzaW9uPgoJPHNvZnR3YXJlLWJ1aWxkPjQxNzY8L3NvZnR3YXJlLWJ1aWxkPgoJPGxpZ2h0bmluZy1iYXNlLWJ1aWxkLW51bWJlciAvPgoJPHVpLWJ1aWxkLW51bWJlcj5DSEQuNTBFMDQxNzZBPC91aS1idWlsZC1udW1iZXI+Cgk8dWktc29mdHdhcmUtdmVyc2lvbj4xMi41LjA8L3VpLXNvZnR3YXJlLXZlcnNpb24+Cgk8dWktc29mdHdhcmUtYnVpbGQ+NDE3NjwvdWktc29mdHdhcmUtYnVpbGQ+Cgk8c2VjdXJlLWRldmljZT50cnVlPC9zZWN1cmUtZGV2aWNlPgoJPGxhbmd1YWdlPmVuPC9sYW5ndWFnZT4KCTxjb3VudHJ5PlVTPC9jb3VudHJ5PgoJPGxvY2FsZT5lbl9VUzwvbG9jYWxlPgoJPHRpbWUtem9uZS1hdXRvPnRydWU8L3RpbWUtem9uZS1hdXRvPgoJPHRpbWUtem9uZT5VUy9FYXN0ZXJuPC90aW1lLXpvbmU+Cgk8dGltZS16b25lLW5hbWU+VW5pdGVkIFN0YXRlcy9FYXN0ZXJuPC90aW1lLXpvbmUtbmFtZT4KCTx0aW1lLXpvbmUtdHo+QW1lcmljYS9OZXdfWW9yazwvdGltZS16b25lLXR6PgoJPHRpbWUtem9uZS1vZmZzZXQ+LTMwMDwvdGltZS16b25lLW9mZnNldD4KCTxjbG9jay1mb3JtYXQ+MTItaG91cjwvY2xvY2stZm9ybWF0PgoJPHVwdGltZT4yOTM0OTg1PC91cHRpbWU+Cgk8cG93ZXItbW9kZT5Qb3dlck9uPC9wb3dlci1tb2RlPgoJPHN1cHBvcnRzLXN1c3BlbmQ+dHJ1ZTwvc3VwcG9ydHMtc3VzcGVuZD4KCTxzdXBwb3J0cy1maW5kLXJlbW90ZT5mYWxzZTwvc3VwcG9ydHMtZmluZC1yZW1vdGU+Cgk8c3VwcG9ydHMtYXVkaW8tZ3VpZGU+dHJ1ZTwvc3VwcG9ydHMtYXVkaW8tZ3VpZGU+Cgk8c3VwcG9ydHMtcnZhPnRydWU8L3N1cHBvcnRzLXJ2YT4KCTxoYXMtaGFuZHMtZnJlZS12b2ljZS1yZW1vdGU+ZmFsc2U8L2hhcy1oYW5kcy1mcmVlLXZvaWNlLXJlbW90ZT4KCTxkZXZlbG9wZXItZW5hYmxlZD5mYWxzZTwvZGV2ZWxvcGVyLWVuYWJsZWQ+Cgk8a2V5ZWQtZGV2ZWxvcGVyLWlkIC8+Cgk8c2VhcmNoLWVuYWJsZWQ+dHJ1ZTwvc2VhcmNoLWVuYWJsZWQ+Cgk8c2VhcmNoLWNoYW5uZWxzLWVuYWJsZWQ+dHJ1ZTwvc2VhcmNoLWNoYW5uZWxzLWVuYWJsZWQ+Cgk8dm9pY2Utc2VhcmNoLWVuYWJsZWQ+dHJ1ZTwvdm9pY2Utc2VhcmNoLWVuYWJsZWQ+Cgk8c3VwcG9ydHMtcHJpdmF0ZS1saXN0ZW5pbmc+dHJ1ZTwvc3VwcG9ydHMtcHJpdmF0ZS1saXN0ZW5pbmc+Cgk8c3VwcG9ydHMtcHJpdmF0ZS1saXN0ZW5pbmctZHR2PnRydWU8L3N1cHBvcnRzLXByaXZhdGUtbGlzdGVuaW5nLWR0dj4KCTxzdXBwb3J0cy13YXJtLXN0YW5kYnk+dHJ1ZTwvc3VwcG9ydHMtd2FybS1zdGFuZGJ5PgoJPGhlYWRwaG9uZXMtY29ubmVjdGVkPmZhbHNlPC9oZWFkcGhvbmVzLWNvbm5lY3RlZD4KCTxzdXBwb3J0cy1hdWRpby1zZXR0aW5ncz5mYWxzZTwvc3VwcG9ydHMtYXVkaW8tc2V0dGluZ3M+Cgk8ZXhwZXJ0LXBxLWVuYWJsZWQ+MS4wPC9leHBlcnQtcHEtZW5hYmxlZD4KCTxzdXBwb3J0cy1lY3MtdGV4dGVkaXQ+dHJ1ZTwvc3VwcG9ydHMtZWNzLXRleHRlZGl0PgoJPHN1cHBvcnRzLWVjcy1taWNyb3Bob25lPnRydWU8L3N1cHBvcnRzLWVjcy1taWNyb3Bob25lPgoJPHN1cHBvcnRzLXdha2Utb24td2xhbj50cnVlPC9zdXBwb3J0cy13YWtlLW9uLXdsYW4+Cgk8c3VwcG9ydHMtYWlycGxheT50cnVlPC9zdXBwb3J0cy1haXJwbGF5PgoJPGhhcy1wbGF5LW9uLXJva3U+dHJ1ZTwvaGFzLXBsYXktb24tcm9rdT4KCTxoYXMtbW9iaWxlLXNjcmVlbnNhdmVyPmZhbHNlPC9oYXMtbW9iaWxlLXNjcmVlbnNhdmVyPgoJPHN1cHBvcnQtdXJsPmhpc2Vuc2UtdXNhLmNvbS9zdXBwb3J0PC9zdXBwb3J0LXVybD4KCTxncmFuZGNlbnRyYWwtdmVyc2lvbj4xMC40LjQ1PC9ncmFuZGNlbnRyYWwtdmVyc2lvbj4KCTxzdXBwb3J0cy10cmM+dHJ1ZTwvc3VwcG9ydHMtdHJjPgoJPHRyYy12ZXJzaW9uPjMuMDwvdHJjLXZlcnNpb24+Cgk8dHJjLWNoYW5uZWwtdmVyc2lvbj45LjMuMTA8L3RyYy1jaGFubmVsLXZlcnNpb24+Cgk8YXYtc3luYy1jYWxpYnJhdGlvbi1lbmFibGVkPjMuMDwvYXYtc3luYy1jYWxpYnJhdGlvbi1lbmFibGVkPgo8L2RldmljZS1pbmZvPgo=","content-type":"text/xml; charset=\"utf-8\"","response":"query-device-info","response-id":"2","status":"200","status-msg":"OK"}
    }

    func getDeviceApps() async throws -> [AppLinkAppEntity] {
        throw Self.ECPError.notImplemented
//        {"request":"query-apps","request-id":"6"}
//        {"content-data":"PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiID8+CjxhcHBzPgoJPGFwcCBpZD0idHZpbnB1dC5kdHYiIHR5cGU9InR2aW4iIHZlcnNpb249IjEuMC4wIj5MaXZlwqBUVjwvYXBwPgoJPGFwcCBpZD0idHZpbnB1dC5oZG1pMiIgdHlwZT0idHZpbiIgdmVyc2lvbj0iMS4wLjAiPk5pbnRlbmRvIFN3aXRjaDwvYXBwPgoJPGFwcCBpZD0idHZpbnB1dC5oZG1pMyIgdHlwZT0idHZpbiIgdmVyc2lvbj0iMS4wLjAiPkhETUnCoDM8L2FwcD4KCTxhcHAgaWQ9InR2aW5wdXQuaGRtaTEiIHR5cGU9InR2aW4iIHZlcnNpb249IjEuMC4wIj5IRE1JwqAxwqAoZUFSQyk8L2FwcD4KCTxhcHAgaWQ9IjEyIiB0eXBlPSJhcHBsIiBzdWJ0eXBlPSJuZGthIiB2ZXJzaW9uPSI2LjEuMTIwMDg4MDI1Ij5OZXRmbGl4PC9hcHA+Cgk8YXBwIGlkPSIyOTEwOTciIHR5cGU9ImFwcGwiIHN1YnR5cGU9InJzZ2EiIHZlcnNpb249IjEuMzguMjAyMzEyMDgwMCI+RGlzbmV5IFBsdXM8L2FwcD4KCTxhcHAgaWQ9IjEzIiB0eXBlPSJhcHBsIiBzdWJ0eXBlPSJuZGthIiB2ZXJzaW9uPSIxNC4xLjIwMjMwOTIwMjIiPlByaW1lIFZpZGVvPC9hcHA+Cgk8YXBwIGlkPSIyMjg1IiB0eXBlPSJhcHBsIiBzdWJ0eXBlPSJyc2dhIiB2ZXJzaW9uPSI2Ljc3LjIiPkh1bHU8L2FwcD4KCTxhcHAgaWQ9IjIyMjk3IiB0eXBlPSJhcHBsIiBzdWJ0eXBlPSJuZGthIiB2ZXJzaW9uPSIyLjExLjY2Ij5TcG90aWZ5IE11c2ljPC9hcHA+Cgk8YXBwIGlkPSIxNTE5MDgiIHR5cGU9ImFwcGwiIHN1YnR5cGU9InJzZ2EiIHZlcnNpb249IjkuMy4xMCI+VGhlIFJva3UgQ2hhbm5lbDwvYXBwPgoJPGFwcCBpZD0iODM3IiB0eXBlPSJhcHBsIiBzdWJ0eXBlPSJuZGthIiB2ZXJzaW9uPSIyLjIyLjExMDAwNTEwMCI+WW91VHViZTwvYXBwPgoJPGFwcCBpZD0iNDE0NjgiIHR5cGU9ImFwcGwiIHN1YnR5cGU9InJzZ2EiIHZlcnNpb249IjMuMC4yIj5UdWJpIC0gRnJlZSBNb3ZpZXMgJmFtcDsgVFY8L2FwcD4KCTxhcHAgaWQ9IjYxMzIyIiB0eXBlPSJhcHBsIiBzdWJ0eXBlPSJyc2dhIiB2ZXJzaW9uPSI1NS4zLjEiPk1heDwvYXBwPgoJPGFwcCBpZD0iODgzOCIgdHlwZT0iYXBwbCIgc3VidHlwZT0icnNnYSIgdmVyc2lvbj0iMi4zMC40Ij5TSE9XVElNRTwvYXBwPgoJPGFwcCBpZD0iNTUxMDEyIiB0eXBlPSJhcHBsIiBzdWJ0eXBlPSJuZGthIiB2ZXJzaW9uPSIxNC4wLjQzIj5BcHBsZSBUVjwvYXBwPgoJPGFwcCBpZD0iNTkzMDk5IiB0eXBlPSJhcHBsIiBzdWJ0eXBlPSJyc2dhIiB2ZXJzaW9uPSI0LjExLjIzIj5QZWFjb2NrIFRWPC9hcHA+Cgk8YXBwIGlkPSI3NDUxOSIgdHlwZT0iYXBwbCIgc3VidHlwZT0icnNnYSIgdmVyc2lvbj0iNS4zMS4yIj5QbHV0byBUViAtIEl0J3MgRnJlZSBUVjwvYXBwPgoJPGFwcCBpZD0iMTIwNDA3IiB0eXBlPSJhcHBsIiBzdWJ0eXBlPSJyc2dhIiB2ZXJzaW9uPSIzLjcuOCI+V0lTIE5ld3MgMTA8L2FwcD4KCTxhcHAgaWQ9IjM1MDU4IiB0eXBlPSJhcHBsIiBzdWJ0eXBlPSJyc2dhIiB2ZXJzaW9uPSI1LjQwLjAiPkxpZmV0aW1lPC9hcHA+Cgk8YXBwIGlkPSI2ODAyMCIgdHlwZT0iYXBwbCIgc3VidHlwZT0icnNnYSIgdmVyc2lvbj0iNS40MC4wIj5MaWZldGltZSBNb3ZpZSBDbHViPC9hcHA+CjwvYXBwcz4K","content-type":"text/xml; charset=\"utf-8\"","response":"query-apps","response-id":"6","status":"200","status-msg":"OK"}
    }

    func getDeviceCapabilities () async throws -> DeviceCapabilities {
        throw Self.ECPError.notImplemented
//        {"request":"query-audio-device","request-id":"5"}
//        {"content-data":"PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiID8+CjxhdWRpby1kZXZpY2U+Cgk8Y2FwYWJpbGl0aWVzPgoJCTxhbGwtZGVzdGluYXRpb25zPmRhdGFncmFtLGhlYWRwaG9uZXMscGVyaXBoZXJhbC1zcGVha2VycyxhcmMsc3BlYWtlcnMsc3BkaWYsbGluZW91dCx3aWZpLXJlbW90ZS1zYXMsbW9iaWxlLXNhczwvYWxsLWRlc3RpbmF0aW9ucz4KCTwvY2FwYWJpbGl0aWVzPgoJPGdsb2JhbD4KCQk8bXV0ZWQ+ZmFsc2U8L211dGVkPgoJCTx2b2x1bWU+MjI8L3ZvbHVtZT4KCQk8ZGVzdGluYXRpb24tbGlzdD5zcGVha2VycyxzcGRpZixsaW5lb3V0PC9kZXN0aW5hdGlvbi1saXN0PgoJPC9nbG9iYWw+Cgk8ZGVzdGluYXRpb25zPgoJCTxkZXN0aW5hdGlvbiBuYW1lPSJzcGVha2VycyI+CgkJCTxtdXRlZD5mYWxzZTwvbXV0ZWQ+CgkJCTx2b2x1bWU+MjI8L3ZvbHVtZT4KCQk8L2Rlc3RpbmF0aW9uPgoJCTxkZXN0aW5hdGlvbiBuYW1lPSJzcGRpZiI+CgkJCTxtdXRlZD5mYWxzZTwvbXV0ZWQ+CgkJCTx2b2x1bWU+MTAwPC92b2x1bWU+CgkJPC9kZXN0aW5hdGlvbj4KCQk8ZGVzdGluYXRpb24gbmFtZT0ibGluZW91dCI+CgkJCTxtdXRlZD5mYWxzZTwvbXV0ZWQ+CgkJCTx2b2x1bWU+MTAwPC92b2x1bWU+CgkJPC9kZXN0aW5hdGlvbj4KCTwvZGVzdGluYXRpb25zPgoJPG1vYmlsZS1zYXM+CgkJPG1pbi12ZXJzaW9uPjQzPC9taW4tdmVyc2lvbj4KCQk8bWF4LXZlcnNpb24+NDU8L21heC12ZXJzaW9uPgoJPC9tb2JpbGUtc2FzPgoJPHJ0cC1pbmZvPgoJCTxydHAtYWRkcmVzcyAvPgoJCTxydGNwLXBvcnQ+NTE1MDwvcnRjcC1wb3J0PgoJCTxjdXJyZW50LWJ1ZmZlci1kZWxheS11cz4wPC9jdXJyZW50LWJ1ZmZlci1kZWxheS11cz4KCQk8Y2xpZW50LXZlcnNpb25zIC8+Cgk8L3J0cC1pbmZvPgo8L2F1ZGlvLWRldmljZT4K","content-type":"text/xml; charset=\"utf-8\"","response":"query-audio-device","response-id":"5","status":"200","status-msg":"OK"}
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

    private func send(data: Data?, context: NWConnection.ContentContext, delay: TimeInterval = 2) async throws {
        // Before we send anything, make sure the websocket is up and running
        try await withTimeout(delay: delay) {
            try await self.preInitWebsocket()
            let dataString = String(data: data ?? .init(), encoding: .utf8) ?? "--BAD UTF8 DATA--"
            Self.logger.info("Sending data \(dataString, privacy: .public)")
        }

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

    #if !os(watchOS)
    public func powerToggleDevice() async throws {
        Self.logger.debug("Toggling power for device \(self.location, privacy: .public)")

        // Attempt checking the device power mode
        let canConnect = await canConnectTCP(location: self.location, timeout: 0.5)
        do {
            if canConnect {
                Self.logger.debug("Attempting to power toggle device with api first")
                try await self.sendKeypress(RemoteButton.power.apiValue!, delay: 1.1)
           } else {
               Self.logger.debug("Power toggle not toggled via api, toggling via wol")
               await sendWolToDevice(location: location, macs: macs)
            }
        } catch {
            Self.logger.warning("Error toggling power")
        }
    }
    #else
    public func powerToggleDevice() async throws {
        Self.logger.debug("Toggling power for device \(self.location, privacy: .public)")

        // Attempt checking the device power mode
        do {
            try await self.sendKeypress(RemoteButton.power.apiValue!, delay: 1.1)
        } catch {
            Self.logger.warning("Error toggling power")
        }
    }
    #endif

    #if !os(watchOS)
        public func requestHeadphonesMode() async throws {
            guard let connectingInterface = await tryConnectTCP(location: url.absoluteString, timeout: 3.0) else {
                Self.logger.error("Unable to connect tcp to \(self.url.absoluteString, privacy: .public) to request headphones mode")
                throw ECPError.connectFailed
            }

            let localInterfaces = await allAddressedInterfaces()
            guard let localNWInterface = localInterfaces
                .first(where: { connectingInterface.name == $0.name && $0.isIPv4 })
            else {
                Self.logger
                    .error(
                        "Connected with interface \(connectingInterface.name, privacy: .public) but no match in \(localInterfaces.map(\.name), privacy: .public)"
                    )
                throw ECPError.badInterfaceIP
            }
            let localAddress = localNWInterface.address.addressString
            Self.logger.debug("Got local address \(localAddress, privacy: .public)")

            let plRequestId = getAndUpdateRequestId()
            let requestData = try String(
                data: kebabEncoder.encode(ConfigureAudioRequest.headphonesMode(
                    hostIp: localAddress,
                    requestId: plRequestId
                )),
                encoding: .utf8
            )!

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
                    .error("Unable to start headphones mode on roku with response \(String(describing: plResponse), privacy: .public)")
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
            Self.logger.fault("Bad key with no api value \(String(describing: key), privacy: .public)")
            throw ECPError.badKepress
        }

        try await sendKeypress(keypress)
    }

    public func pressCharacter(_ character: Character) async throws {
        let keypress = getKeypressForKey(key: character)
        try await sendKeypress(keypress)
    }

    public func openApp(_ app: AppLinkAppEntity, params: [String: String]? = nil) async throws {
        // Try 2x with 0.1 sec delay between
        try await self.openApp(app.id, params: params)
    }

    public func openApp(_ appId: String, params: [String: String]? = nil) async throws {
        // Try 2x with 0.1 sec delay between
        do {
            try await openAppOnce(appId, params: params)
        } catch {
            Self.logger.warning("Error opening app the first time-retrying: \(error, privacy: .public)")
            try await Task.sleep(duration: 0.1)
            try await openAppOnce(appId, params: params)
        }
    }

    public func openAppOnce(_ appId: String, params: [String: String]? = nil, delay: TimeInterval = 5) async throws {
        Self.logger.info("Opening app \(appId, privacy: .public)")

        let reqId = self.getAndUpdateRequestId()
        let requestData = try String(
            data: kebabEncoder.encode(AppLaunchRequest(requestId: reqId, channelId: appId, params: params)),
            encoding: .utf8
        )!

        try await withTimeout(delay: delay) {
            let receiveTask = Task {
                try await self.receive(requestId: reqId)
            }

            try await self.send(string: requestData)
            _ = try await receiveTask.value
        }

        Self.logger.info("Opened app \(appId, privacy: .public) successfully")
    }

    private func sendKeypress(_ data: String, delay: TimeInterval = 5) async throws {
        // Try 2x with 0.1 sec delay between
        do {
            try await sendKeypressOnce(data, delay: delay)
        } catch {
            Self.logger.warning("Error sending keypress the first time--retrying: \(error, privacy: .public)")
            try await Task.sleep(duration: 0.1)
            try await sendKeypressOnce(data, delay: delay)
        }
    }

    private func sendKeypressOnce(_ data: String, delay: TimeInterval = 5) async throws {
        Self.logger.trace("Trying to send keypress \(data, privacy: .public)")

        let reqId = getAndUpdateRequestId()
        let requestData = try String(
            data: kebabEncoder.encode(KeyPressRequest(key: data, requestId: String(reqId))),
            encoding: .utf8
        )!

        try await withTimeout(delay: delay) {
            let receiveTask = Task {
                try await self.receive(requestId: reqId)
            }

            try await self.send(string: requestData)
            _ = try await receiveTask.value
        }

        Self.logger.info("Sent key \(data, privacy: .public) successfully")
    }

    // MARK: Helper methods
    private func preInitWebsocket() async throws {
        if connection?.state != .ready  {
            if connection?.state == .preparing {
                try await waitForConnectionReady()
            } else {
                Self.logger.info("WS in down state (\(String(describing: self.connection?.state), privacy: .public)), reconfiguring.")
                if self.isMigratingConnection {
                    Self.logger.info("Already migrating, ignoring")
                    try await waitForConnectionReady()
                } else {
                    try await configure()
                }
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
                Self.logger.info("Auth challenge failed with error \(error, privacy: .public)")

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
    let params: [String: String]?

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
            ECPSession.logger.error("Error parsing kebab-case parameter name: \(keyPart.stringValue, privacy: .public)")
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
