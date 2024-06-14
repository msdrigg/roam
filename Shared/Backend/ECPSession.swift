import CommonCrypto
import Foundation
import os.log

actor ECPSession {
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ECPSession.self)
    )

    let url: URL
    let device: DeviceAppEntity
    var session: URLSession
    var webSocketTask: URLSessionWebSocketTask
    var requestIdCounter: Int = 0
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    enum ECPError: Error, LocalizedError {
        case badWebsocketMessage
        case authDenied
        case badURL
        case connectFailed
        case badInterfaceIP
        case plStartFailed
        case badKepress
        case responseRejection(code: String)
    }

    public init(device: DeviceAppEntity) throws {
        Self.logger.info("Initing ECP Session with url \(device.location)")
        // SAFETY: "http" is always a valid regex
        // swiftlint:disable:next force_try
        guard let url = URL(string: "\(device.location.replacing(try! Regex("http"), with: "ws"))ecp-session") else {
            Self.logger.error("Bad url for location \(device.location)ecp-session")
            throw ECPError.badURL
        }
        self.url = url

        session = URLSession(configuration: .ephemeral)
        webSocketTask = session.webSocketTask(with: url, protocols: ["ecp-2"])
        self.device = device
    }

    public func close() async {
        Self.logger.info("Closing ecp")
        webSocketTask.cancel()
        session.invalidateAndCancel()
    }

    public func configure() async throws {
        try catchObjc {
            webSocketTask = session.webSocketTask(with: url, protocols: ["ecp-2"])
            webSocketTask.resume()
        }
        requestIdCounter = 0

        do {
            try await establishConnectionAndAuthenticate()
        } catch {
            Self.logger.error("Failed to establish connection and authenticate. Cancelling...: \(error)")
            webSocketTask.cancel()
            throw error
        }
    }

    // MARK: Actions

    public func powerToggleDevice() async throws {
        Self.logger.debug("Toggling power for device \(self.device.location)")

        await powerToggleDeviceStateless(location: device.location, mac: device.usingMac())
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

            let requestData = try String(
                data: encoder.encode(ConfigureAudioRequest.headphonesMode(
                    hostIp: localAddress,
                    requestId: getAndUpdateRequestId()
                )),
                encoding: .utf8
            )!

            try await preInitWebsocket()

            // SAFETY: We can unwrap because json encoder always encodes to string
            try await webSocketTask.send(.string(requestData))

            let responseMessage = try await webSocketTask.receive()
            let plResponseData = switch responseMessage {
            case let .data(data):
                data
            case let .string(str):
                if let data = str.data(using: .utf8) {
                    data
                } else {
                    Self.logger.error("Unknown message type received: \(String(describing: responseMessage))")
                    throw ECPError.badWebsocketMessage
                }
            @unknown default:
                Self.logger.error("Unknown message type received: \(String(describing: responseMessage))")
                throw ECPError.badWebsocketMessage
            }

            let websocketStr = String(data: plResponseData, encoding: .utf8) ?? "--Bad data--"
            Self.logger.info("Got PL start weboscket response: \(websocketStr, privacy: .public)")

            let authResponse = try decoder.decode(BaseResponse.self, from: plResponseData)
            if !authResponse.isSuccess {
                Self.logger
                    .error("Unable to start headphones mode on roku with response \(String(describing: authResponse))")
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
        // Before we send anything, make sure the websocket is up and running
        try await preInitWebsocket()

        // SAFETY: We can unwrap because json encoder always encodes to string
        let requestData = try String(
            data: encoder.encode(AppLaunchRequest(paramChannelId: app.id, requestId: String(getAndUpdateRequestId()))),
            encoding: .utf8
        )!
        try await webSocketTask.send(.string(requestData))

        try await consumeResponse()

        Self.logger.info("Opened app \(app.id) successfully")
    }

    private func sendKeypress(_ data: String) async throws {
        // Try 2x with 0.1 sec delay between
        do {
            try await sendKeypressOnce(data)
        } catch {
            Self.logger.warning("Error sending keypress the first time--retrying: \(error)")
            try await Task.sleep(duration: 0.1)
            try await sendKeypressOnce(data)
        }
    }

    private func sendKeypressOnce(_ data: String) async throws {
        Self.logger.trace("Trying to send keypress \(data)")
        // Before we send anything, make sure the websocket is up and running
        try await preInitWebsocket()

        // SAFETY: We can unwrap because json encoder always encodes to string
        let requestData = try String(
            data: encoder.encode(KeyPressRequest(paramKey: data, requestId: String(getAndUpdateRequestId()))),
            encoding: .utf8
        )!
        try await webSocketTask.send(.string(requestData))
        try await consumeResponse()
        Self.logger.info("Sent key \(data) successfully")
    }

    // MARK: Helper methods

    private func preInitWebsocket() async throws {
        if webSocketTask.state != .running {
            Self.logger.info("WS not running, re-configuring")
            try await configure()
        }
    }

    private func getAndUpdateRequestId() -> Int {
        let reqid = requestIdCounter
        requestIdCounter += 1

        return reqid
    }

    private func consumeResponse() async throws {
        // Receive all messages in the buffer before sending (to clear out old msgsa)
        do {
            let resultMessage = try await withTimeout(delay: 2) {
                try await self.webSocketTask.receive()
            }
            // Try to process as a typical response
            let responseMessageData = switch resultMessage {
            case let .data(data):
                data
            case let .string(str):
                if let data = str.data(using: .utf8) {
                    data
                } else {
                    Self.logger.error("Unknown message type received: \(String(describing: resultMessage))")
                    throw ECPError.badWebsocketMessage
                }
            @unknown default:
                Self.logger.error("Unknown message type received: \(String(describing: resultMessage))")
                throw ECPError.badWebsocketMessage
            }
            let websocketStr = String(data: responseMessageData, encoding: .utf8) ?? "--Bad data--"
            Self.logger.info("Got Roku weboscket response: \(websocketStr, privacy: .public)")

            let response = try decoder.decode(BaseResponse.self, from: responseMessageData)
            if !response.isSuccess {
                Self.logger.error("Bad response for \(response.response): \(String(describing: response))")
                throw ECPError.responseRejection(code: response.status)
            }
            Self.logger
                .info(
                    "Received successful ecp response \(String(describing: response.statusMsg)) for command \(response.response)"
                )
        } catch {
            // If cancellation error igonre
            if error is TimeoutError {
                return
            }
            Self.logger.error("Error consuming all ECP messages \(error)")
            throw error
        }
    }

    private func establishConnectionAndAuthenticate() async throws {
        do {
            let authMessage = try await webSocketTask.receive()
            let authMessageData = switch authMessage {
            case let .data(data):
                data
            case let .string(str):
                if let data = str.data(using: .utf8) {
                    data
                } else {
                    Self.logger.error("Unknown message type received: \(String(describing: authMessage))")
                    throw ECPError.badWebsocketMessage
                }
            @unknown default:
                Self.logger.error("Unknown message type received: \(String(describing: authMessage))")
                throw ECPError.badWebsocketMessage
            }

            let websocketStr = String(data: authMessageData, encoding: .utf8) ?? "--Bad data--"
            Self.logger.info("Got auth weboscket response: \(websocketStr, privacy: .public)")

            let challengeMessage = try decoder.decode(AuthChallenge.self, from: authMessageData)
            let responseMessage = AuthVerifyRequest(
                challenge: challengeMessage.paramChallenge,
                requestId: getAndUpdateRequestId()
            )
            let responseData = try encoder.encode(responseMessage)
            // We can unwrap here because data always encodes to string
            try await webSocketTask.send(.string(String(data: responseData, encoding: .utf8)!))

            do {
                try await consumeResponse()
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
            Self.logger.error("WebSocket connection failed: \(error)")
            throw error
        }
    }
}

private struct AuthChallenge: Codable {
    let paramChallenge: String

    private enum CodingKeys: String, CodingKey {
        case paramChallenge = "param-challenge"
    }
}

private struct AuthVerifyRequest: Codable {
    let paramMicrophoneSampleRates: String = "1600"
    let paramResponse: String
    let requestId: String
    let paramClientFriendlyName: String = "Wireless Speaker"
    let request: String = "authenticate"
    let paramHasMicrophone: String = "false"

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

    init(challenge: String, requestId: Int) {
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
        paramResponse = createAuthKey(challenge)
        self.requestId = String(requestId)
    }

    private enum CodingKeys: String, CodingKey {
        case paramMicrophoneSampleRates = "param-microphone-sample-rates"
        case paramResponse = "param-response"
        case paramClientFriendlyName = "param-client-friendly-name"
        case request
        case requestId = "request-id"
        case paramHasMicrophone = "param-has-microphone"
    }
}

// MARK: Request-response

private struct ConfigureAudioRequest: Codable {
    let paramDevname: String?
    let paramAudioOutput: String
    let request: String = "set-audio-output"
    let requestId: String

    #if !os(watchOS)
        static func headphonesMode(hostIp: String, requestId: Int) -> Self {
            Self(
                paramDevname: "\(hostIp):\(globalHostRTPPort):\(globalRTPPayloadType):\(globalClockRate / 50)",
                paramAudioOutput: "datagram",
                requestId: String(requestId)
            )
        }
    #endif

    private enum CodingKeys: String, CodingKey {
        case paramDevname = "param-devname"
        case paramAudioOutput = "param-audio-output"
        case request
        case requestId = "request-id"
    }
}

private struct AppLaunchRequest: Codable {
    let request: String = "launch"
    let paramChannelId: String
    let requestId: String

    private enum CodingKeys: String, CodingKey {
        case paramChannelId = "param-channel-id"
        case requestId = "request-id"
        case request
    }
}

private struct KeyPressRequest: Codable {
    let request: String = "key-press"
    let paramKey: String
    let requestId: String

    private enum CodingKeys: String, CodingKey {
        case paramKey = "param-key"
        case requestId = "request-id"
        case request
    }
}

private struct BaseResponse: Codable {
    let response: String
    let responseId: String
    let status: String
    let statusMsg: String?

    var isSuccess: Bool {
        status == "200"
    }

    private enum CodingKeys: String, CodingKey {
        case response
        case responseId = "response-id"
        case status
        case statusMsg = "status-msg"
    }
}
