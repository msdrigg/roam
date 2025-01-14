import AsyncAlgorithms
@preconcurrency import AVFoundation
import Foundation
import Network
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "HeadphonesMode"
)

enum HeadphonesModeError: Error, LocalizedError {
    case badURL
    case audioStreamingTimeout
}

func listenContinually(ecpSession: ECPSession, location: String, rtcpPort: UInt16?) async throws {
    do {
        try await withThrowingDiscardingTaskGroup { taskGroup in
            logger.info("Starting headphones mode")

            let rtpSession: RTPSession
            if let url = URL(string: location), let host = url.host() {
                rtpSession = try RTPSession(
                    localRTPPort: globalHostRTPPort,
                    localRTCPPort: globalHostRTCPPort,
                    remoteRTCPPort: rtcpPort ?? globalDefaultRemoteRTCPPort,
                    remoteRTCPAddress: host
                )
            } else {
                logger.error("Error getting RTPSession")
                throw HeadphonesModeError.badURL
            }
            taskGroup.addTask {
                try await rtpSession.streamAudio()
            }

            taskGroup.addTask {
                do {
                    try await ecpSession.requestHeadphonesMode()
                    await Task.sleepUntilCancelled()
                } catch {
                    if !(error is CancellationError) {
                        logger.error("Error requesting headphones mode \(error, privacy: .public)")
                    }
                    throw error
                }
            }

            taskGroup.addTask {
                do {
                    try await withTimeout(delay: 6.0) {
                        try await rtpSession.performRTCPHandshake()
                    }
                } catch {
                    logger.error("Error performing handshake: \(error, privacy: .public)")
                    throw error
                }
                do {
                    try await rtpSession.sendRTCPReceiverReports()
                } catch {
                    logger.error("Error sending receiver reports: \(error, privacy: .public)")
                    throw error
                }
            }
        }
    } catch {
        logger.error("Error among headphones mode tasks \(error, privacy: .public)")
        throw error
    }
}

actor RTPSession {
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: RTPSession.self)
    )

    let videoBufferMs: UInt32 = 400
    let baseAudioTransitMs: UInt32 = 0

    var baseAudioDelayMs: UInt32 {
        videoBufferMs + baseAudioTransitMs
    }

    let rtcpStream: AsyncThrowingBufferedChannel<RtcpPacket, any Error>
    let rtpStream: AsyncThrowingBufferedChannel<RtpPacket, any Error>
    let rtpListener: NWListener
    let rtcpListener: NWListener

    let remoteRtcpConnection: NWConnection

    enum RTPError: Error, LocalizedError {
        case badRTCPPacket
    }

    init(localRTPPort: UInt16, localRTCPPort: UInt16, remoteRTCPPort: UInt16, remoteRTCPAddress: String) throws {
        let remoteRtcpEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(remoteRTCPAddress),
            port: NWEndpoint.Port(rawValue: remoteRTCPPort)!
        )

        let rtcpParameters = NWParameters.udp
        let localEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("0.0.0.0"),
            port: NWEndpoint.Port(rawValue: localRTPPort)!
        )
        Self.logger
            .info(
                "Starting rtcp with local port \(localRTPPort), remote address \(remoteRTCPAddress), endpoint \(String(describing: localEndpoint))"
            )
        rtcpParameters.requiredLocalEndpoint = localEndpoint
        rtcpParameters.allowLocalEndpointReuse = true

        remoteRtcpConnection = NWConnection(to: remoteRtcpEndpoint, using: rtcpParameters)

        let rtpParams = NWParameters.udp
        rtpParams.allowLocalEndpointReuse = true

        rtpListener = try NWListener(using: rtpParams, on: NWEndpoint.Port(rawValue: localRTPPort)!)
        rtcpListener = try NWListener(using: .udp, on: NWEndpoint.Port(rawValue: localRTCPPort)!)

        remoteRtcpConnection.start(queue: .global())

        rtpStream = AsyncThrowingBufferedChannel<RtpPacket, any Error>()
        rtcpStream = AsyncThrowingBufferedChannel<RtcpPacket, any Error>()
        Task {
            await startRtcpStream()
            await startRtpStream()
        }
    }

    deinit {
        Self.logger.info("Closing rtp listeners and connections")
        self.rtpListener.cancel()
        self.rtcpListener.cancel()
        self.remoteRtcpConnection.cancel()
    }

    func startRtcpStream() {
        rtcpListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case let .failed(err):
                Self.logger.info("rtcpConnection failed with error \(err, privacy: .public)")
                self?.rtcpStream.fail(err)
            case .cancelled:
                Self.logger.info("rtcpConnection cancelled")
                self?.rtcpStream.finish()
            case .ready:
                Self.logger.info("rtcpConnection ready")
            default:
                Self.logger.info("Getting new rtcp state \(String(describing: state), privacy: .public)")
            }
        }

        rtcpListener.newConnectionHandler = { [weak self] rtcpConnection in
            guard let rtcpStream = self?.rtcpStream else {
                Self.logger.warning("No rtcp stream when getting new connection")
                return
            }
            Self.logger.info("Got new rtcp connection \(String(describing: rtcpConnection), privacy: .public)")
            @Sendable func closure(_ data: Data?, _: NWConnection.ContentContext?, _: Bool, _ error: NWError?) {
                Self.logger.info("Got new rtcp packet \(String(describing: data), privacy: .public), error: \(error, privacy: .public)")
                guard let data else {
                    return
                }
                if let packet = RtcpPacket(data: data) {
                    rtcpStream.send(packet)
                } else {
                    Self.logger.error("Error parsing rtcp packet")
                }
                rtcpConnection.receiveMessage(completion: closure)
            }

            rtcpConnection.receiveMessage(completion: closure)

            self?.rtcpListener.stateUpdateHandler = { state in
                switch state {
                case let .failed(err):
                    Self.logger.info("rtcpConnection failed with error \(err, privacy: .public)")
                    rtcpConnection.send(
                        content: RtcpPacket.bye(.init(ssrc: 0)).packet(),
                        completion: .contentProcessed { error in
                            Self.logger.info("Sent RTCP Bye with error \(error, privacy: .public)")
                            rtcpConnection.cancel()
                        }
                    )
                    rtcpStream.fail(err)
                case .cancelled:
                    Self.logger.info("rtcpConnection cancelled")
                    rtcpConnection.send(
                        content: RtcpPacket.bye(.init(ssrc: 0)).packet(),
                        completion: .contentProcessed { error in
                            Self.logger.info("Sent RTCP Bye with error \(error, privacy: .public)")
                            rtcpConnection.cancel()
                        }
                    )
                    rtcpStream.finish()
                case .ready:
                    Self.logger.info("rtcpConnection ready")
                default:
                    Self.logger.info("Getting new rtcp state \(String(describing: state), privacy: .public)")
                }
            }

            rtcpConnection.stateUpdateHandler = { state in
                switch state {
                case let .failed(err):
                    Self.logger.info("rtcpConnection connection failed with error \(err, privacy: .public)")
                    rtcpStream.fail(err)
                case .cancelled:
                    Self.logger.info("rtcpConnection connection cancelled")
                    rtcpStream.finish()
                case .ready:
                    Self.logger.info("rtcpConnection connection ready")
                default:
                    Self.logger.info("Getting new rtcpConnection connection state \(String(describing: state), privacy: .public)")
                }
            }
            rtcpConnection.start(queue: .global())
        }

        rtcpListener.start(queue: .global())
    }

    func startRtpStream() {
        rtpListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case let .failed(err):
                Self.logger.info("rtpConnection failed with error \(err, privacy: .public)")
                self?.rtpStream.fail(err)
            case .cancelled:
                Self.logger.info("rtpConnection cancelled")
                self?.rtpStream.finish()
            case .ready:
                Self.logger.info("rtpConnection ready")
            default:
                Self.logger.info("Getting new rtp state \(String(describing: state), privacy: .public)")
            }
        }

        rtpListener.newConnectionHandler = { [weak self] rtpConnection in
            guard let rtpStream = self?.rtpStream else {
                Self.logger.warning("No rtp stream when getting new connection")
                return
            }

            Self.logger.info("Getting rtp connection \(String(describing: rtpConnection), privacy: .public)")

            @Sendable func closure(_ data: Data?, _: NWConnection.ContentContext?, _: Bool, _: NWError?) {
                guard let data else {
                    return
                }
                do {
                    let packet = try RtpPacket(data: data)

                    rtpStream.send(packet)
                } catch {
                    Self.logger.error("Error parsing rtp packet: \(error, privacy: .public)")
                }

                rtpConnection.receiveMessage(completion: closure)
            }

            rtpConnection.receiveMessage(completion: closure)
            rtpConnection.stateUpdateHandler = { state in
                switch state {
                case let .failed(err):
                    Self.logger.info("rtpConnection connection failed with error \(err, privacy: .public)")
                    rtpStream.fail(err)
                case .cancelled:
                    Self.logger.info("rtpConnection connection cancelled")
                    rtpStream.finish()
                case .ready:
                    Self.logger.info("rtpConnection connection ready")
                default:
                    Self.logger.info("Getting new rtpConnection connection state \(String(describing: state), privacy: .public)")
                }
            }
            rtpConnection.start(queue: .global())

            self?.rtpListener.stateUpdateHandler = { state in
                switch state {
                case let .failed(err):
                    Self.logger.info("RTPConnection failed with error \(err, privacy: .public)")
                    rtpConnection.cancel()
                    rtpStream.fail(err)
                case .cancelled:
                    Self.logger.info("RTPConnection cancelled")
                    rtpConnection.cancel()
                    rtpStream.finish()
                case .ready:
                    Self.logger.info("rtpConnection ready")
                default:
                    Self.logger.info("Getting new rtp state \(String(describing: state), privacy: .public)")
                }
            }
        }

        rtpListener.start(queue: .global())
    }

    func performVDLYHandshake() async throws {
        // Send VDLY rtcp packet using rtcpConnection
        // Wait for response XDLY using rtcpStream
        Self.logger.info("Performing VDLY handshake")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            remoteRtcpConnection.send(
                content: RtcpPacket.vdly(delayMs: globalHugeFixedVDLYMS).packet(),
                completion: .contentProcessed { error in
                    if let error {
                        Self.logger.warning("Error sending VDLY packet \(error, privacy: .public)")
                        continuation.resume(throwing: error)
                    } else {
                        Self.logger.debug("VDLY Sent \(globalHugeFixedVDLYMS, privacy: .public)")
                        continuation.resume(returning: ())
                    }
                }
            )
        }

        for try await packet in rtcpStream {
            switch packet {
            case let .appSpecific(.xdly(xdly)):
                if xdly.delayMicroseconds == globalHugeFixedVDLYMS * 1000 {
                    Self.logger.info("Got good xdly packet from rtcp as expected")
                    return
                }
                Self.logger.warning("Got bad xdly microseconds. Expecting \(globalHugeFixedVDLYMS * 1000, privacy: .public)")
            default:
                Self.logger.warning("Got bad packet from rtcp. Expecting App.XDLY. Got \(String(describing: packet), privacy: .public)")
            }
        }
    }

    func performNewClientHandshake() async throws {
        // Send CVER rtcp packet using rtcpConnection
        // Wait for response NCLI packet using rtcpStream
        Self.logger.info("Performing NCLI handshake")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            remoteRtcpConnection.send(
                content: RtcpPacket.cver(clientVersion: 2).packet(),
                completion: .contentProcessed { error in
                    if let error {
                        Self.logger.warning("Error sending CVER packet \(error, privacy: .public)")
                        continuation.resume(throwing: error)
                    } else {
                        Self.logger.debug("CVER Sent")
                        continuation.resume(returning: ())
                    }
                }
            )
        }

        for try await packet in rtcpStream {
            switch packet {
            case .appSpecific(.ncli):
                Self.logger.info("Got ncli packet from rtcp as expected")
                return
            default:
                Self.logger.warning("Got bad packet from rtcp. Expecting App.NCLI. Got \(String(describing: packet), privacy: .public)")
            }
        }
    }

    func performRTCPHandshake() async throws {
        Self.logger.info("Performing RTCP handshake")
        var timerStream = AsyncTimerSequence.repeating(every: .seconds(1)).makeAsyncIterator()
        while !Task.isCancelled {
            do {
                try await withTimeout(delay: 1) {
                    try await self.performVDLYHandshake()
                }
                break
            } catch {
                Self.logger.error("Error performing VDLY handshake \(error, privacy: .public)")
                _ = await timerStream.next()
            }
        }

        while !Task.isCancelled {
            do {
                try await withTimeout(delay: 1) {
                    try await self.performNewClientHandshake()
                }
                break
            } catch {
                Self.logger.error("Error performing NCLI handshake \(error, privacy: .public)")
            }
        }
        Self.logger.info("Performed RTCP handshake successfully")
    }

    func sendRTCPReceiverReport() async throws {
//        Self.logger.info("Sending receiver report")

        let report = RtcpPacket.receiverReport(.init(ssrc: 0, reportBlocks: []))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            remoteRtcpConnection.send(content: report.packet(), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    func sendRTCPReceiverReports() async throws {
//        Self.logger.info("Sending receiver reports")
        var timerStream = AsyncTimerSequence.repeating(every: .seconds(1)).makeAsyncIterator()
        while !Task.isCancelled {
            do {
                try await sendRTCPReceiverReport()
            } catch {
                Self.logger.error("Error sending receiver report \(error, privacy: .public)")
            }
            _ = await timerStream.next()
        }
    }

    func streamAudio() async throws {
        #if !os(macOS)
            await setupSessionForAudioPlayback()
            defer {
                do {
                    try AVAudioSession.sharedInstance().setActive(false)
                } catch {
                    Self.logger.error("Failed to disable audio session active: \(error, privacy: .public)")
                }
            }
        #endif

        try await withThrowingDiscardingTaskGroup { taskGroup in
            let rtpAudioPlayer = AudioPlayer()

            Self.logger.info("Starting receiving rtp packets")
            let decoder: OpusDecoderWithJitterBuffer =
                try OpusDecoderWithJitterBuffer(audioBuffer: Double(videoBufferMs) / 1000)
            taskGroup.addTask {
                var count = 0
                var lsqNo: Int64 = 0

                do {
                    for try await rtpPacket in self.rtpStream {
                        let seqNo = rtpPacket.sequenceNumber
                        Self.logger.debug("Received packet in stream: \(seqNo, privacy: .public)")
                        // Drop first 5 packets because we want to have a reasonable sync packet and sometimes the first
                        // packet or two isn't valid
                        count += 1
                        if count < 5 {
                            continue
                        }

                        if lsqNo != Int64(seqNo) - 1 {
                            Self.logger.info("Packet with seqno received \(seqNo, privacy: .public) when expecting \(lsqNo + 1, privacy: .public)")
                        }
                        lsqNo = Int64(seqNo)

                        await decoder.addPacket(packet: rtpPacket)
                    }
                } catch {
                    Self.logger.error("Error iterating rtpstream \(error, privacy: .public)")
                }
            }

            taskGroup.addTask {
                try await rtpAudioPlayer.start()
                defer {
                    Task {
                        await rtpAudioPlayer.stop()
                    }
                }

                for await _ in AsyncTimerSequence.repeating(every: .milliseconds(10), tolerance: .microseconds(10)) {
                    Task {
                        if let lrt = await rtpAudioPlayer.lastRender() {
                            if let returns = await decoder.nextPacket(atTime: consume lrt) {
                                let pcmBuffer = returns.0
                                let audioTime = returns.1

                                await rtpAudioPlayer.scheduleAudioBytes(buffer: pcmBuffer, atTime: audioTime)
                            }
                        }
                    }
                }
            }

            taskGroup.addTask {
                for await _ in AsyncTimerSequence.repeating(every: .milliseconds(200)) {
                    if let lrt = await rtpAudioPlayer.lastRender() {
                        let latency = await rtpAudioPlayer.getOutputLatency()
                        if await decoder.syncAudio(
                            time: lrt,
                            additionalAudioDelay: Double(globalHugeFixedVDLYMS - self.baseAudioDelayMs) / 1000 -
                                latency
                        ) {
                            break
                        }
                    }
                }

                if let stream = await LatencyListener().events {
                    for await latency in stream {
                        Self.logger.error("New latency event \(latency, privacy: .public)")
                        for await _ in AsyncTimerSequence.repeating(every: .milliseconds(200)) {
                            if let lrt = await rtpAudioPlayer.lastRender() {
                                if await decoder.syncAudio(
                                    time: lrt,
                                    additionalAudioDelay: Double(globalHugeFixedVDLYMS - self.baseAudioDelayMs) /
                                        1000 -
                                        latency
                                ) {
                                    break
                                }
                            }
                        }
                        Self.logger.info("Synced audio!")
                    }
                } else {
                    Self.logger.error("Unable to get latency events stream")
                }
            }
        }
    }

    #if !os(macOS)
    @MainActor
        func setupSessionForAudioPlayback() {
            // Retrieve the shared audio session.
            let audioSession = AVAudioSession.sharedInstance()
            do {
                Self.logger.info("Settingup audio session")
                // Set the audio session category and mode.
                try audioSession.setCategory(.playback, mode: .default, policy: .longFormAudio)
                try audioSession.setActive(true)
            } catch {
                Self.logger.error("Failed to set the audio session configuration: \(error, privacy: .public)")
            }
        }
    #endif
}
