#if !os(watchOS)
import Network
import OSLog
import Foundation
import CommonCrypto

private let requestKey = "ecp_request"

extension NWProtocolFramer.Message {
    convenience init(ecpRequest request: ECPRequestMessage) {
        self.init(definition: ECPProtocol.definition)
        self[requestKey] = request
    }

    var ecpRequest: ECPRequestMessage? {
        self[requestKey] as? ECPRequestMessage
    }
}

private let responseMessageKey = "ecp_response"

extension NWProtocolFramer.Message {
    convenience init(ecpResponseMessage message: ECPResponseMessage) {
        self.init(definition: ECPProtocol.definition)
        self[responseMessageKey] = message
    }

    var ecpResponse: ECPResponseMessage? {
        self[responseMessageKey] as? ECPResponseMessage
    }
}

let globalECPRefreshInterval: TimeInterval = 10
let globalECPRequestTimeout: Int = 5

final class ECPProtocol: NWProtocolFramerImplementation {
    init(framer: NWProtocolFramer.Instance) { }

    static fileprivate let logger = Logger(subsystem: "ecp.websocket", category: "ECPProtocolFramer")
    static let definition = NWProtocolFramer.Definition(implementation: ECPProtocol.self)

    /// Protocol definition
    static let label: String = "ECPWebSocketFramer"

    let uuid: UUID = UUID()

    var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = kebabParamDecodingStrategy()
        return d
    }
    var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = kebabParamEncodingStrategy()
        return e
    }

    var needProgressBy: Date = .distantFuture
    var lastPingSent: Date = .distantPast
    var state: WebsocketState = .waitingForUpgrade
    var partialheader: Data = Data()
    var nextHeader: WebsocketHeader?

    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult {
        // Generate a random Sec-WebSocket-Key
        var randomBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let secWebSocketKey = Data(randomBytes).base64EncodedString()

        // Get the host from the framer's NWEndpoint
        let host: String
        if case let .hostPort(hostname, _) = framer.remote {
            host = "\(hostname.debugDescription)"
        } else {
            Self.logger.info("Unable to parse host header from \(String(describing: framer.remote), privacy: .public)")
            host = "roku.local"
        }

        // Send HTTP headers for WebSocket upgrade
        let formattedRequest = Data("""
        GET /ecp-session HTTP/1.1\r\n\
        Upgrade: WebSocket\r\n\
        Connection: Upgrade\r\n\
        Host: \(host)\r\n\
        Origin: iOS\r\n\
        Sec-WebSocket-Version: 13\r\n\
        Sec-WebSocket-Protocol: ecp-2\r\n\
        Sec-WebSocket-Key: \(secWebSocketKey)\r\n\r\n
        """.utf8)

        framer.writeOutput(data: formattedRequest)
        framer.scheduleWakeup(wakeupTime: .milliseconds(500))
        self.needProgressBy = .now.addingTimeInterval(0.5)
        return .willMarkReady
    }

    func wakeup(framer: NWProtocolFramer.Instance) {
        if self.needProgressBy.timeIntervalSinceNow < 0 {
            if self.state != WebsocketState.stopped {
                Self.logger.warning("Timed out \(self.needProgressBy) \(self.state.debugDescription)")
                self.sendClose(framer: framer)
            }
            framer.markFailed(error: .posix(.ETIMEDOUT))
            self.state = .stopped
        } else if self.state == .ready && self.needProgressBy.timeIntervalSinceNow < 4 && self.lastPingSent.timeIntervalSinceNow < -0.6 {
            // Send ping
            Self.logger.info("Sending ping with time due \(self.needProgressBy.timeIntervalSinceNow)  and last ping sent \(self.lastPingSent.timeIntervalSinceNow)")
            self.lastPingSent = .now

            self.sendPing(framer: framer)
        }

        framer.scheduleWakeup(wakeupTime: .milliseconds(500))
    }

    enum SingleInputResult {
        case canContinue
        case doneForNow(Int)
    }

    func handleSignleInput(framer: NWProtocolFramer.Instance) throws -> SingleInputResult {
        if state == .waitingForUpgrade {
            return try self.handleUpgrade(framer: framer)
        } else {
            return try self.handleWebsocketFrame(framer: framer)
        }
    }

    func handleUpgrade(framer: NWProtocolFramer.Instance) throws -> SingleInputResult {
        var offset: Int?
        let result = framer.parseInput(minimumIncompleteLength: 24, maximumLength: 1024) { buffer, _ in
            guard let buffer = buffer else { return 0 }

            // Look for the end of the headers section (marked by \r\n\r\n)
            let endOfHeadersRange = buffer.withUnsafeBytes { rawBuffer -> Range<Int>? in
                guard let baseAddress = rawBuffer.baseAddress else { return nil }
                let data = Data(bytes: baseAddress, count: rawBuffer.count)
                return data.range(of: Data("\r\n\r\n".utf8))
            }

            if let endOfHeaders = endOfHeadersRange?.upperBound {
                offset = endOfHeaders
                return endOfHeaders
            }

            // If no end of headers found, return 0
            return 0
        }
        guard result, offset != nil else {
            return .doneForNow(0)
        }

        self.needProgressBy = self.needProgressBy.addingTimeInterval(0.2)
        self.state = .waitingForAuthChallenge

        return .canContinue
    }

    func handleWebsocketFrame(framer: NWProtocolFramer.Instance) throws -> SingleInputResult {
        var parseError: WebsocketError?
        let header: WebsocketHeader
        if let nextHeader = self.nextHeader {
            header = nextHeader
        } else {
            let parseResult = framer.parseWebsocketHeader(framer: framer, partialHeader: self.partialheader)
            switch parseResult {
            case .parsed(let nextHeader):
                header = nextHeader
                self.partialheader = Data()
            case .failed(let data, let needed):
                Self.logger.info("Failed to parse data with partial \(data.count) needed \(needed)")
                self.partialheader = data
                return .doneForNow(needed)
            }
        }
        Self.logger.info("Parsed header \(header.debugOpcode) with len \(header.payloadLength)")

        var nextWsFrame: WebsocketMessage?
        if header.payloadLength == 0 {
            nextWsFrame = try WebsocketMessage.parse(header: header, data: nil)
            self.nextHeader = nil
        } else {
            Self.logger.info("Requesting data for payload length \(header.payloadLength)")
            let parseResult = framer.parseInput(minimumIncompleteLength: header.payloadLength, maximumLength: header.payloadLength) { buffer, _ in
                guard let buffer = buffer else {
                    Self.logger.info("No buffer, not consuming anything")
                    return 0
                }
                Self.logger.info("Got buffer with count \(buffer.count)")

                do {
                    let frame = try WebsocketMessage.parse(header: header, data: buffer)
                    nextWsFrame = frame
                    Self.logger.info("Consuming \(header.payloadLength) for \(frame.debugDescription)")
                    return header.payloadLength
                } catch {
                    Self.logger.error("Error parsing unknown ws frame \(error, privacy: .public). Consuming \(header.payloadLength)")
                    parseError = error as? WebsocketError ?? .badWebsocketFrame("Failed to parse with weird error")
                    return header.payloadLength
                }
            }
            if parseResult {
                self.nextHeader = nil
            } else {
                self.nextHeader = header
                return .doneForNow(header.payloadLength)
            }

            if let parseError {
                throw parseError
            }
        }

        guard let frame = nextWsFrame else {
            Self.logger.info("Returning bc no frame from nextwsframe")
            return .doneForNow(header.payloadLength)
        }
        switch (self.state, frame) {
        case (.waitingForUpgrade, _), (.stopped, _):
            Self.logger.error("Should not be possible to hit this \(self.state.debugDescription, privacy: .public)")
            throw WebsocketError.badWebsocketFrame("Shouldn't be possible to hit this")
        case (_, .close(let code, let reason)):
            Self.logger.info("Getting close frame unexpectedly with code \(code, privacy: .public) and reaspon \(reason ?? "nil", privacy: .public), current state \(self.state.debugDescription, privacy: .public)")
            self.sendClose(framer: framer)
            framer.markFailed(error: nil)
            self.state = .stopped
        case (.waitingForAuthChallenge, .text(let data)):
            let authChallenge = try self.decoder.decode(AuthChallenge.self, from: data)
            self.sendJson(framer: framer, json: AuthVerifyRequest(challenge: authChallenge.challenge))
            self.state = .waitingForAuthResponse
            self.needProgressBy = self.needProgressBy.addingTimeInterval(0.2)
        case (.waitingForAuthResponse, .text(let data)):
            Self.logger.info("Getting data \(data) while waiting for auth response")
            let response: BaseResponse = try self.decoder.decode(BaseResponse.self, from: data)
            if !response.isSuccess {
                Self.logger.warning("Failed to authenticate with response status \(response.status, privacy: .public)")
                throw WebsocketError.authFailure
            } else {
                Self.logger.info("Successfully authed!")
            }
            self.needProgressBy = Date.now.addingTimeInterval(5)
            self.state = .ready
            framer.markReady()
        case (.waitingForAuthChallenge, .ping ), (.waitingForAuthChallenge, .pong), (.waitingForAuthResponse, .ping ), (.waitingForAuthResponse, .pong):
            Self.logger.info("Expecting no pings or pongs before authenticating \(self.state.debugDescription, privacy: .public)")
            throw WebsocketError.badWebsocketFrame("Expecting no pings or pongs before auth")
        case (.ready, .ping):
            Self.logger.info("Receiving ping")
            self.sendPong(framer: framer)
            self.needProgressBy = Date.now.addingTimeInterval(5)
        case (.ready, .pong):
            Self.logger.info("Receiving pong")
            self.needProgressBy = Date.now.addingTimeInterval(5)
        case (.ready, .text(let data)):
            if let text = String(data: data, encoding: .utf8) {
                Self.logger.info("Getting text at ready \(text)")
            } else {
                Self.logger.error("Failed to decode data as UTF-8")
            }
            let response: ECPResponseMessage = try self.decoder.decode(ECPResponseMessage.self, from: data)
            self.needProgressBy = Date.now.addingTimeInterval(5)
            if case let .response(.base(baseResponse)) = response {
                Self.logger.info("Delivering response for id \(baseResponse.responseId, privacy: .public)")
            }
            _ = framer.deliverInputNoCopy(length: 0, message: .init(ecpResponseMessage: response), isComplete: true)
        }

        return .canContinue
    }

    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            do {
                if self.state == .stopped {
                    return 0
                }
                let parseResult = try self.handleSignleInput(framer: framer)
                switch parseResult {
                case .canContinue:
                    Self.logger.info("Continuing")
                    continue
                case .doneForNow(let needed):
                    Self.logger.info("Requesting data amount \(needed)")
                    return needed
                }
            } catch {
                Self.logger.error("Error handling input \(error) in state \(self.state.debugDescription)")
                framer.markFailed(error: (error as? WebsocketError)?.nwError ?? NWError.posix(.EPROTO))
                self.state = .stopped
                return 0
            }
        }
    }

    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool) {
        guard let request = message.ecpRequest else {
            Self.logger.error("Unable to get ecpRequest from message")
            return
        }
        guard !invalidRequestIds.contains(request.requestId) else {
            Self.logger.error("Sending request with invalid id \(request.requestId)")
            return
        }
        self.sendJson(framer: framer, json: request)
    }

    func stop(framer: NWProtocolFramer.Instance) -> Bool {
        switch self.state {
        case .stopped:
            Self.logger.info("Getting re-close frame. Force-stopping")
        case .waitingForUpgrade:
            Self.logger.info("Getting close on waiting for upgrade. Stopping instantly")
        case .waitingForAuthChallenge, .waitingForAuthResponse, .ready:
            Self.logger.info("Getting close. Sending close frame before stopping")
            self.sendClose(framer: framer)
        }

        self.state = .stopped
        return true
    }

    func cleanup(framer: NWProtocolFramer.Instance) { }
}

enum HeaderParseResult {
    case parsed(WebsocketHeader)
    case failed(Data, Int)
}

extension NWProtocolFramer.Instance {
    func parseWebsocketHeader(framer: NWProtocolFramer.Instance, partialHeader: Data) -> HeaderParseResult {
        // Parsing server ws headers are 2, 4 and 10
        var partialData = partialHeader
        var parsedHeader: WebsocketHeader?
        let framerParseResult = framer.parseInput(
            minimumIncompleteLength: max(0, WebsocketHeader.minSize - partialHeader.count),
            maximumLength: max(1, WebsocketHeader.maxSize - partialHeader.count),
            parse: { (buffer, _) -> Int in
                guard let buffer = buffer, buffer.count != 0 else {
                    ECPProtocol.logger.info("No buffer or empty buffer. Not parsing header")
                    return 0
                }
                partialData += Data(buffer)
                if let header = WebsocketHeader.parse(from: partialData) {
                    parsedHeader = header
                    let consumed = header.encodedSize - partialHeader.count
                    ECPProtocol.logger.info("Consuming \(consumed) bytes to parse header (\(header.encodedSize)-\(partialHeader.count))")
                    return consumed
                }

                // How much data do we take if it's failed? All of it
                ECPProtocol.logger.info("Consuming all \(buffer.count) bytes to parse header \(Data(partialData).toHexString())")
                return buffer.count
            }
        )

        guard framerParseResult, let header = parsedHeader else {
            ECPProtocol.logger.info("No header parsed (\(framerParseResult))-\(max(0, WebsocketHeader.minSize - partialHeader.count)). Not consuming anything")

            let nextNeededSize = if partialData.count < 2 {
                2
            } else if partialData.count < 4 {
                4
            } else {
                10
            }

            return .failed(partialData, nextNeededSize - partialData.count)
        }

        return .parsed(header)
    }
}

extension ECPProtocol {
    func sendPing(framer: NWProtocolFramer.Instance) {
        Self.logger.info("Sending ping \(self.uuid)")
        framer.writeOutput(data: WebsocketMessage.ping.rawData)
    }

    func sendPong(framer: NWProtocolFramer.Instance) {
        Self.logger.info("Sending pong")
        framer.writeOutput(data: WebsocketMessage.pong.rawData)
    }

    func sendClose(framer: NWProtocolFramer.Instance) {
        Self.logger.info("Sending close")
        framer.writeOutput(data: WebsocketMessage.close(1000, "").rawData)
    }

    func sendJson<T: Encodable>(framer: NWProtocolFramer.Instance, json: T) {
        Self.logger.info("Sending json")

        do {
            let wsMessage = WebsocketMessage.text(try encoder.encode(json))

            framer.writeOutput(data: wsMessage.rawData)
        } catch {
            Self.logger.warning("Error encoding message: \(error, privacy: .public)")
        }
    }
}

enum WebsocketState: Equatable, CustomDebugStringConvertible {
    case waitingForUpgrade
    case waitingForAuthChallenge
    case waitingForAuthResponse
    case ready
    case stopped

    var debugDescription: String {
        switch self {
        case .waitingForUpgrade: return "WaitingForUpgrade"
        case .waitingForAuthChallenge: return "WaitingForAuthChallenge"
        case .waitingForAuthResponse: return "WaitingForAuthResponse"
        case .ready: return "Ready"
        case .stopped: return "Stopped"
        }
    }
}

enum WebsocketError: Equatable, CustomDebugStringConvertible, Error {
    case badUpgrade
    case badWebsocketFrame(String)
    case timeout
    case authFailure
    case ioFailure(NWError)

    var debugDescription: String {
        switch self {
        case .badUpgrade: return "BadUpgrade"
        case .badWebsocketFrame(let reason): return "BadWebsocketFrame (\(reason))"
        case .authFailure: return "AuthFailure"
        case .timeout: return "Timeout"
        case .ioFailure(let error): return "IO (\(error.debugDescription))"
        }
    }

    var nwError: NWError{
        switch self {
        case .ioFailure(let error): return error
        case .authFailure, .badUpgrade, .badWebsocketFrame: return NWError.posix(.EPROTO)
        case .timeout: return NWError.posix(.ETIME)
        }
    }
}

struct WebsocketHeader {
    let fin: Bool
    let opcode: UInt8
    let payloadLength: Int
    let mask: Bool

    static let maxSize: Int = 10
    static let minSize: Int = 2

    var encodedSize: Int {
        switch payloadLength {
        case 0...125:
            return Self.minSize
        case 126...65535:
            return Self.minSize + 2
        default:
            return Self.minSize + 8
        }
    }

    var debugOpcode: String {
        switch opcode {
        case 1: return "Text"
        case 8: return "Connection Close"
        case 9: return "Ping"
        case 10: return "Pong"
        default: return "Unknown \(opcode)"
        }
    }

    static func parse(from data: Data) -> WebsocketHeader? {
        guard data.count >= minSize else { return nil }
        let firstByte = data[0]
        let secondByte = data[1]

        let fin = (firstByte & 0x80) != 0
        let opcode = firstByte & 0x0F
        let mask = (secondByte & 0x80) != 0
        var payloadLength = Int(secondByte & 0x7F)
        var offset = minSize

        if payloadLength == 126 {
            guard data.count >= 4 else { return nil }
            ECPProtocol.logger.info("Trying to parse newlen 16 bit \(data[2...3].toHexString())")
            guard let newLen = UInt16(bigEndian: data[2...3]) else { return nil }
            payloadLength = Int(newLen)
            offset += 2
        } else if payloadLength == 127 {
            guard data.count >= 10 else { return nil }
            ECPProtocol.logger.info("Trying to parse newlen 64 bit \(data[2...9].toHexString())")
            guard let newLen = UInt64(bigEndian: data[2...9]) else { return nil }
            payloadLength = Int(newLen)
            offset += 8
        }

        return WebsocketHeader(fin: fin, opcode: opcode, payloadLength: payloadLength, mask: mask)
    }
}

enum WebsocketMessage: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .ping: return "Ping"
        case .pong: return "Pong"
        case .close(let code, let reason): return "Close (\(code), \(reason ?? "no reason"))"
        case .text(let data): return "Text (\(data.count) bytes)"
        }
    }

    case pong
    case ping
    case text(Data)
    case close(Int, String?)

    var rawData: Data {
        var data = Data()

        switch self {
        case .pong:
            data.append(0x8A) // FIN=true, opcode=0xA (pong)
            data.append(0x80) // No payload with masking
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Masking key
        case .ping:
            data.append(0x89) // FIN=true, opcode=0x9 (ping)
            data.append(0x80) // No payload with masking
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Masking key
        case .text(let message):
            let messageData = message
            data.append(0x81) // FIN=true, opcode=0x1 (text)

            if messageData.count <= 125 {
                data.append(0x80 | UInt8(messageData.count)) // Masked with payload length
            } else if messageData.count <= 65535 {
                data.append(0x80 | 0x7E) // Masked with extended payload length
                data.append(contentsOf: withUnsafeBytes(of: UInt16(messageData.count).bigEndian) { Array($0) })
            } else {
                data.append(0x80 | 0x7F) // Masked with 64-bit extended payload length
                data.append(contentsOf: withUnsafeBytes(of: UInt64(messageData.count).bigEndian) { Array($0) })
            }
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Masking key
            data.append(messageData)
        case .close(let code, let reason):
            var payload = Data()
            payload.append(contentsOf: withUnsafeBytes(of: UInt16(code).bigEndian) { Array($0) })
            if let reason = reason {
                payload.append(reason.data(using: .utf8)!)
            }
            data.append(0x88) // FIN=true, opcode=0x8 (close)
            if payload.count <= 125 {
                data.append(0x80 | UInt8(payload.count)) // Masked with payload length
            } else if payload.count <= 65535 {
                data.append(0x80 | 0x7E) // Masked with extended payload length
                data.append(contentsOf: withUnsafeBytes(of: UInt16(payload.count).bigEndian) { Array($0) })
            }
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Masking key
            data.append(payload)
        }

        return data
    }

    static func parse(header: WebsocketHeader, data: UnsafeMutableRawBufferPointer?) throws -> WebsocketMessage? {
        let count = data?.count ?? 0
        guard count >= header.payloadLength else { return nil }

        let payload = if let baseAddress = data?.baseAddress {
            Data(bytes: baseAddress, count: header.payloadLength)
        } else {
            Data()
        }

        switch header.opcode {
        case 0x1: // Text
            return .text(payload)
        case 0x8: // Close
            let code = payload.count >= 2 ? Int(UInt16(bigEndian: withUnsafeBytes(of: payload[0..<2]) { $0.load(as: UInt16.self) })) : 1000
            let reason = payload.count > 2 ? String(data: payload[2...], encoding: .utf8) : nil
            return .close(code, reason)
        case 0x9: // Ping
            return .ping
        case 0xA: // Pong
            return .pong
        default:
            throw WebsocketError.badWebsocketFrame("Unsupported opcode \(header.opcode)")
        }
    }
}

private func kebabParamDecodingStrategy() -> JSONDecoder.KeyDecodingStrategy {
    return JSONDecoder.KeyDecodingStrategy.custom { keySequence in
        let keyPart = keySequence.last!
        let segments = keyPart.stringValue.stripPrefix("param-").split(separator: "-")
        if segments.isEmpty {
            ECPProtocol.logger.error("Error parsing kebab-case parameter name: \(keyPart.stringValue, privacy: .public)")
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

private func kebabParamEncodingStrategy() -> JSONEncoder.KeyEncodingStrategy {
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

private let invalidRequestIds = ["1"]

private struct AuthChallenge: Codable {
    let challenge: String
}

private struct AuthVerifyRequest: Encodable {
    let microphoneSampleRates: String = "1600"
    let response: String
    let requestId: String = "1"
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

    init(challenge: String) {
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
    }
}

extension NWParameters {
    public static var ecp: NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionDropTime = globalECPRequestTimeout
        tcpOptions.connectionTimeout = globalECPRequestTimeout
        tcpOptions.keepaliveCount = globalECPRequestTimeout
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveInterval = globalECPRequestTimeout
        tcpOptions.persistTimeout = globalECPRequestTimeout
        tcpOptions.enableFastOpen = true
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let ecpOptions = NWProtocolFramer.Options(definition: ECPProtocol.definition)

        params.defaultProtocolStack.applicationProtocols.insert(ecpOptions, at: 0)

        return params
    }
}
#endif
