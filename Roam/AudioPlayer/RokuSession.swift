@preconcurrency import AVFoundation
import Foundation
import Network
import os.log

enum HeadphonesModeError: Error, LocalizedError {
    case badURL
    case audioStreamingTimeout
    case rtpListenerFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid device address for headphones mode."
        case .audioStreamingTimeout:
            return "Audio streaming timed out."
        case let .rtpListenerFailed(underlying):
            return "Couldn't start headphones mode: UDP port \(globalHostRTPPort) is unavailable (\(underlying.localizedDescription)). Another app on this Mac may be holding it; try quitting other audio/casting apps and try again."
        }
    }
}

func listenContinually(ecpSession: ECPWebsocketClient, location: String, rtcpPort: UInt16?) async throws {
    do {
        try await withThrowingDiscardingTaskGroup { taskGroup in
            Log.headphones.notice("Starting headphones mode")

            let rtpSession: RTPSession
            if let url = URL(string: location), let host = url.host() {
                rtpSession = try RTPSession(
                    localRTPPort: globalHostRTPPort,
                    localRTCPPort: globalHostRTCPPort,
                    remoteRTCPPort: rtcpPort ?? globalDefaultRemoteRTCPPort,
                    remoteRTCPAddress: host
                )
            } else {
                Log.headphones.error("Error getting RTPSession")
                throw HeadphonesModeError.badURL
            }
            taskGroup.addTask {
                try await rtpSession.streamAudio()
            }

            taskGroup.addTask {
                // Wait for Roku to ACK `set-audio-output` BEFORE starting
                // any RTCP traffic. If VDLY/RR arrive before Roku has
                // registered the session, Roku silently drops them — and
                // because it also kills RTP after a few seconds without
                // RRs, racing the ACK destroys the whole stream.
                do {
                    try await ecpSession.requestHeadphonesMode()
                } catch {
                    if !(error is CancellationError) {
                        Log.headphones.error("Error requesting headphones mode \(error, privacy: .public)")
                    }
                    throw error
                }

                try await withThrowingDiscardingTaskGroup { rtcpGroup in
                    rtcpGroup.addTask {
                        // Audio playback is intentionally NOT coupled to the
                        // RTCP handshake. Roku is forgiving about a missing
                        // VDLY/NCLI exchange and will keep streaming audio. A
                        // failed handshake here only means we never confirmed
                        // the requested buffer delay — it must not bring down
                        // the audio task.
                        do {
                            try await withTimeout(delay: 6.0) {
                                try await rtpSession.performRTCPHandshake()
                            }
                        } catch is CancellationError {
                            return
                        } catch {
                            Log.headphones
                                .warning("RTCP handshake did not complete: \(error, privacy: .public). Continuing without it.")
                        }
                    }

                    rtcpGroup.addTask {
                        // Roku stops sending RTP audio after a few seconds
                        // if it doesn't see periodic RRs from us.
                        do {
                            try await rtpSession.sendRTCPReceiverReports()
                        } catch is CancellationError {
                            return
                        } catch {
                            Log.headphones.error("Error sending receiver reports: \(error, privacy: .public)")
                        }
                    }

                    // Keep the headphones session open until cancellation.
                    rtcpGroup.addTask {
                        await Task.sleepUntilCancelled()
                    }
                }
            }
        }
    } catch {
        Log.headphones.error("Error among headphones mode tasks \(error, privacy: .public)")
        throw error
    }
}

actor RTPSession {
    let videoBufferMs: UInt32 = 400
    let baseAudioTransitMs: UInt32 = 0

    var baseAudioDelayMs: UInt32 {
        videoBufferMs + baseAudioTransitMs
    }

    let rtcpInbox = RtcpInbox()
    let rtpStream: AsyncThrowingStream<RtpPacket, Error>
    let rtpStreamContinuation: AsyncThrowingStream<RtpPacket, Error>.Continuation
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

        // Bind outbound RTCP to the local RTP port (6970), NOT 6971.
        // Roku validates incoming RTCP against the source IP+port it
        // recorded from `set-audio-output`'s devname — which advertises
        // <ip>:6970. Packets arriving from any other source port (an
        // ephemeral port, or even 6971 per the RTP+1 convention) fail
        // that check and Roku silently drops them, including the empty
        // RR that keeps RTP alive — so the audio stream dies after a
        // few seconds. Sharing port 6970 with `rtpListener` is fine
        // because both sockets set `allowLocalEndpointReuse` and the
        // kernel demuxes by 4-tuple: RTP from Roku:<ephemeral> goes to
        // the listener (no remote set, less specific), RTCP from
        // Roku:5150 goes to this connection (specific remote match).
        let outboundRtcpParams = NWParameters.udp
        outboundRtcpParams.allowLocalEndpointReuse = true
        outboundRtcpParams.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("0.0.0.0"),
            port: NWEndpoint.Port(rawValue: localRTPPort)!
        )
        Log.headphones
            .notice(
                "Starting rtcp with outbound source port \(localRTPPort, privacy: .public), listener port \(localRTCPPort, privacy: .public), remote address \(remoteRTCPAddress, privacy: .public)"
            )
        remoteRtcpConnection = NWConnection(to: remoteRtcpEndpoint, using: outboundRtcpParams)

        let rtpParams = NWParameters.udp
        rtpParams.allowLocalEndpointReuse = true
        let rtcpListenerParams = NWParameters.udp
        rtcpListenerParams.allowLocalEndpointReuse = true

        rtpListener = try NWListener(using: rtpParams, on: NWEndpoint.Port(rawValue: localRTPPort)!)
        rtcpListener = try NWListener(using: rtcpListenerParams, on: NWEndpoint.Port(rawValue: localRTCPPort)!)

        remoteRtcpConnection.stateUpdateHandler = { state in
            switch state {
            case let .failed(err):
                Log.headphones.notice("remoteRtcpConnection failed with error \(err, privacy: .public)")
            case .cancelled:
                Log.headphones.notice("remoteRtcpConnection cancelled")
            case .ready:
                Log.headphones.notice("remoteRtcpConnection ready")
            case let .waiting(err):
                Log.headphones.notice("remoteRtcpConnection waiting \(err, privacy: .public)")
            default:
                Log.headphones.notice("remoteRtcpConnection state \(String(describing: state), privacy: .public)")
            }
        }
        // Intentionally do NOT call remoteRtcpConnection.start() yet. It
        // must bind AFTER rtpListener (both want port 6970). Listener binds
        // first as an unconnected SO_REUSEPORT socket; the connected
        // socket then joins via REUSEPORT and the kernel demuxes by
        // 4-tuple. If we start the connection first, its bind wins and
        // the listener gets EADDRINUSE. start() is deferred to
        // rtpListener's `.ready` callback (see startRtpStream).

        // Defensive: also drain any RTCP that the kernel routes to this
        // connection. In practice Roku addresses replies to local 6971,
        // which `rtcpListener` catches — but if a firmware variant sends
        // them to 6970 instead, the 4-tuple match against this connection
        // wins and the listener never sees them. Reading here makes both
        // paths feed the same inbox.
        let inbox = rtcpInbox
        let outboundConnection = remoteRtcpConnection
        @Sendable func receiveOutboundRtcp(
            _ data: Data?,
            _: NWConnection.ContentContext?,
            _: Bool,
            _ error: NWError?
        ) {
            // Stop the loop on connection close / cancel — otherwise the
            // recursion spins forever firing ECANCELED into the log.
            guard let data else {
                if let error {
                    Log.headphones
                        .notice("Outbound rtcp receive loop ending: \(error, privacy: .public)")
                }
                return
            }
            if let packet = RtcpPacket(data: data) {
                Task { await inbox.deliver(packet) }
            } else {
                Log.headphones.error("Error parsing rtcp packet on outbound connection")
            }
            outboundConnection.receiveMessage(completion: receiveOutboundRtcp)
        }
        remoteRtcpConnection.receiveMessage(completion: receiveOutboundRtcp)

        let (rtpStream, rtpContuation) = AsyncThrowingStream<RtpPacket, Error>.makeStream(
            of: RtpPacket.self,
            throwing: Error.self,
            bufferingPolicy: .bufferingNewest(512)
        )
        self.rtpStream = rtpStream
        rtpStreamContinuation = rtpContuation

        // Wire and start listeners synchronously, in init, so the rtpListener
        // wins the bind race with remoteRtcpConnection on port 6970.
        // rtcpListener (port 6971) has no conflict and is started for symmetry.
        startRtcpStream()
        startRtpStream()
    }

    deinit {
        Log.headphones.notice("Closing rtp listeners and connections")
        self.rtpListener.cancel()
        self.rtcpListener.cancel()
        self.remoteRtcpConnection.cancel()
    }

    /// Guards `remoteRtcpConnection.start()` so it runs exactly once, even
    /// if rtpListener emits `.ready` more than once (interface flips etc.).
    private var rtcpConnectionStarted = false
    private func startRemoteRtcpConnectionIfNeeded() {
        guard !rtcpConnectionStarted else { return }
        rtcpConnectionStarted = true
        remoteRtcpConnection.start(queue: .global())
    }

    nonisolated func startRtcpStream() {
        rtcpListener.stateUpdateHandler = { state in
            switch state {
            case let .failed(err):
                Log.headphones.notice("rtcpListener failed with error \(err, privacy: .public)")
            case .cancelled:
                Log.headphones.notice("rtcpListener cancelled")
            case .ready:
                Log.headphones.notice("rtcpListener ready")
            default:
                Log.headphones.notice("Getting new rtcp state \(String(describing: state), privacy: .public)")
            }
        }

        rtcpListener.newConnectionHandler = { [weak self] rtcpConnection in
            guard let inbox = self?.rtcpInbox else {
                Log.headphones.warning("No rtcp inbox when getting new connection")
                return
            }
            Log.headphones.notice("Got new rtcp connection \(String(describing: rtcpConnection), privacy: .public)")
            @Sendable func closure(_ data: Data?, _: NWConnection.ContentContext?, _: Bool, _ error: NWError?) {
                Log.headphones.notice("Got new rtcp packet \(String(describing: data), privacy: .public), error: \(error, privacy: .public)")
                guard let data else {
                    return
                }
                if let packet = RtcpPacket(data: data) {
                    Task { await inbox.deliver(packet) }
                } else {
                    Log.headphones.error("Error parsing rtcp packet")
                }
                rtcpConnection.receiveMessage(completion: closure)
            }

            rtcpConnection.receiveMessage(completion: closure)

            rtcpConnection.stateUpdateHandler = { state in
                switch state {
                case let .failed(err):
                    Log.headphones.notice("rtcpConnection connection failed with error \(err, privacy: .public)")
                case .cancelled:
                    Log.headphones.notice("rtcpConnection connection cancelled")
                    rtcpConnection.send(
                        content: RtcpPacket.bye(.init(ssrc: 0)).packet(),
                        completion: .contentProcessed { error in
                            Log.headphones.notice("Sent RTCP Bye with error \(error, privacy: .public)")
                        }
                    )
                case .ready:
                    Log.headphones.notice("rtcpConnection connection ready")
                default:
                    Log.headphones.notice("Getting new rtcpConnection connection state \(String(describing: state), privacy: .public)")
                }
            }
            rtcpConnection.start(queue: .global())
        }

        rtcpListener.start(queue: .global())
    }

    nonisolated func startRtpStream() {
        rtpListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case let .failed(err):
                Log.headphones.notice("rtpListener failed with error \(err, privacy: .public)")
                // Surface the bind failure to streamAudio's `for try await`
                // so the whole headphones-mode task group throws out and the
                // UI can flip the toggle off + show an alert. Logging alone
                // leaves the stream silent with no audio and no feedback.
                self?.rtpStreamContinuation.finish(throwing: HeadphonesModeError.rtpListenerFailed(underlying: err))
            case .cancelled:
                Log.headphones.notice("rtpListener cancelled")
                self?.rtpStreamContinuation.finish()
            case .ready:
                Log.headphones.notice("rtpListener ready")
                // Now that the listener owns port 6970 (unconnected, with
                // SO_REUSEPORT via allowLocalEndpointReuse), it's safe to
                // bring up the outbound RTCP connection that also wants to
                // bind 6970 — the kernel demuxes by 4-tuple. If we started
                // the connection first, its connected bind would block the
                // listener and we'd get EADDRINUSE.
                Task { [weak self] in await self?.startRemoteRtcpConnectionIfNeeded() }
            default:
                Log.headphones.notice("Getting new rtp state \(String(describing: state), privacy: .public)")
            }
        }

        rtpListener.newConnectionHandler = { [weak self] rtpConnection in
            guard let rtpStreamContinuation = self?.rtpStreamContinuation else {
                Log.headphones.warning("No rtp stream when getting new connection")
                return
            }

            Log.headphones.notice("Getting rtp connection \(String(describing: rtpConnection), privacy: .public)")

            @Sendable func closure(_ data: Data?, _: NWConnection.ContentContext?, _: Bool, _: NWError?) {
                guard let data else {
                    return
                }
                do {
                    let packet = try RtpPacket(data: data)

                    if case .terminated = rtpStreamContinuation.yield(packet) {
                        Log.headphones.warning("Error sending packet to closed channel")
                    }
                } catch {
                    Log.headphones.error("Error parsing rtp packet: \(error, privacy: .public)")
                }

                rtpConnection.receiveMessage(completion: closure)
            }

            rtpConnection.receiveMessage(completion: closure)
            rtpConnection.stateUpdateHandler = { state in
                switch state {
                case let .failed(err):
                    Log.headphones.notice("rtpConnection connection failed with error \(err, privacy: .public)")
                    rtpStreamContinuation.finish()
                case .cancelled:
                    Log.headphones.notice("rtpConnection connection cancelled")
                    rtpStreamContinuation.finish()
                case .ready:
                    Log.headphones.notice("rtpConnection connection ready")
                default:
                    Log.headphones.notice("Getting new rtpConnection connection state \(String(describing: state), privacy: .public)")
                }
            }
            rtpConnection.start(queue: .global())

            self?.rtpListener.stateUpdateHandler = { state in
                switch state {
                case let .failed(err):
                    Log.headphones.notice("RTPConnection failed with error \(err, privacy: .public)")
                    rtpConnection.cancel()
                    rtpStreamContinuation.finish()
                case .cancelled:
                    Log.headphones.notice("RTPConnection cancelled")
                    rtpConnection.cancel()
                    rtpStreamContinuation.finish()
                case .ready:
                    Log.headphones.notice("rtpConnection ready")
                default:
                    Log.headphones.notice("Getting new rtp state \(String(describing: state), privacy: .public)")
                }
            }
        }

        rtpListener.start(queue: .global())
    }

    func performVDLYHandshake() async throws {
        Log.headphones.notice("Performing VDLY handshake")

        // Register the waiter BEFORE sending so we never miss the response.
        // If sendVDLY throws, the implicit cancellation of `response` invokes
        // RtcpInbox.cancelWaiter, which removes the waiter and resumes it
        // with CancellationError.
        async let response: RtcpPacket = rtcpInbox.waitFor { packet in
            if case let .appSpecific(.xdly(xdly)) = packet,
               xdly.delayMicroseconds == globalHugeFixedVDLYMS * 1000 {
                return true
            }
            return false
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            remoteRtcpConnection.send(
                content: RtcpPacket.vdly(delayMs: globalHugeFixedVDLYMS).packet(),
                completion: .contentProcessed { error in
                    if let error {
                        Log.headphones.warning("Error sending VDLY packet \(error, privacy: .public)")
                        continuation.resume(throwing: error)
                    } else {
                        Log.headphones.notice("VDLY Sent \(globalHugeFixedVDLYMS, privacy: .public)")
                        continuation.resume(returning: ())
                    }
                }
            )
        }

        _ = try await response
        Log.headphones.notice("Got good xdly packet from rtcp as expected")
    }

    func performNewClientHandshake() async throws {
        Log.headphones.notice("Performing NCLI handshake")

        async let response: RtcpPacket = rtcpInbox.waitFor { packet in
            if case .appSpecific(.ncli) = packet { return true }
            return false
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            remoteRtcpConnection.send(
                content: RtcpPacket.cver(clientVersion: 2).packet(),
                completion: .contentProcessed { error in
                    if let error {
                        Log.headphones.warning("Error sending CVER packet \(error, privacy: .public)")
                        continuation.resume(throwing: error)
                    } else {
                        Log.headphones.notice("CVER Sent")
                        continuation.resume(returning: ())
                    }
                }
            )
        }

        _ = try await response
        Log.headphones.notice("Got ncli packet from rtcp as expected")
    }

    func performRTCPHandshake() async throws {
        Log.headphones.notice("Performing RTCP handshake")
        var timerStream = AsyncTimerSequence.repeating(every: .seconds(1)).makeAsyncIterator()
        while !Task.isCancelled {
            do {
                try await withTimeout(delay: 1) {
                    try await self.performVDLYHandshake()
                }
                break
            } catch {
                Log.headphones.error("Error performing VDLY handshake \(error, privacy: .public)")
                _ = await timerStream.next()
            }
        }
        // The retry loop also exits when the surrounding task is cancelled
        // — without this, a cancellation mid-loop would fall through and
        // we'd falsely log "Performed RTCP handshake successfully".
        try Task.checkCancellation()

        while !Task.isCancelled {
            do {
                try await withTimeout(delay: 1) {
                    try await self.performNewClientHandshake()
                }
                break
            } catch {
                Log.headphones.error("Error performing NCLI handshake \(error, privacy: .public)")
            }
        }
        try Task.checkCancellation()

        Log.headphones.notice("Performed RTCP handshake successfully")
    }

    func sendRTCPReceiverReport() async throws {
//        Log.headphones.notice("Sending receiver report")

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
        var timerStream = AsyncTimerSequence.repeating(every: .seconds(1)).makeAsyncIterator()
        while !Task.isCancelled {
            do {
                try await sendRTCPReceiverReport()
            } catch {
                Log.headphones.error("Error sending receiver report \(error, privacy: .public)")
            }
            _ = await timerStream.next()
        }
    }

    func streamAudio() async throws {
        let rtpAudioPlayer = AudioPlayer()
        #if !os(macOS)
            await rtpAudioPlayer.configureAudioSession()
            defer {
                Task {
                    await rtpAudioPlayer.makeInactive()
                }
            }
        #endif

        try await withThrowingDiscardingTaskGroup { taskGroup in

            Log.headphones.notice("Starting receiving rtp packets")
            let decoder: OpusDecoderWithJitterBuffer =
                try OpusDecoderWithJitterBuffer(audioBuffer: Double(videoBufferMs) / 1000)
            taskGroup.addTask {
                var count = 0
                var lsqNo: Int64 = 0

                for try await rtpPacket in self.rtpStream {
                    let seqNo = rtpPacket.sequenceNumber
                    if seqNo % 1000 == 0 {
                        Log.headphones.debug("Received packet in stream (every 1000 packets): \(seqNo, privacy: .public)")
                    }
                    // Drop first 5 packets because we want to have a reasonable sync packet and sometimes the first
                    // packet or two isn't valid
                    count += 1
                    if count < 5 {
                        continue
                    }

                    if lsqNo != Int64(seqNo) - 1 {
                        Log.headphones.notice("Packet with seqno received \(seqNo, privacy: .public) when expecting \(lsqNo + 1, privacy: .public)")
                    }
                    lsqNo = Int64(seqNo)

                    await decoder.addPacket(packet: rtpPacket)
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
                        if let lrt = try? await rtpAudioPlayer.lastRender() {
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
                    if let lrt = try? await rtpAudioPlayer.lastRender() {
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
                        Log.headphones.error("New latency event \(latency, privacy: .public)")
                        for await _ in AsyncTimerSequence.repeating(every: .milliseconds(200)) {
                            if let lrt = try? await rtpAudioPlayer.lastRender() {
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
                        Log.headphones.notice("Synced audio!")
                    }
                } else {
                    Log.headphones.error("Unable to get latency events stream")
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
                Log.headphones.notice("Settingup audio session")
                // Set the audio session category and mode.
                try audioSession.setCategory(.playback, mode: .default, policy: .longFormAudio)
                try audioSession.setActive(true)
            } catch {
                Log.headphones.error("Failed to set the audio session configuration: \(error, privacy: .public)")
            }
        }
    #endif
}

/// Inbox actor for incoming RTCP packets.
///
/// Each call to `waitFor(_:)` registers a waiter (predicate + continuation)
/// and suspends. `deliver(_:)` resumes the first waiter whose predicate
/// matches and removes it. Packets that match no waiter are silently dropped.
///
/// Cancellation safety: if the awaiting task is cancelled, the cancellation
/// handler removes the waiter from the registry before resuming with
/// CancellationError. Because both `deliver` and the cancellation path are
/// actor-isolated, they serialize, so the continuation is resumed exactly
/// once. A late delivery for a cancelled waiter cannot find a matching
/// predicate (the waiter is gone), so the late packet is just dropped.
actor RtcpInbox {
    typealias Predicate = @Sendable (RtcpPacket) -> Bool

    private struct Waiter {
        let id: UInt64
        let predicate: Predicate
        let continuation: CheckedContinuation<RtcpPacket, Error>
    }

    private var waiters: [Waiter] = []
    private var nextID: UInt64 = 0

    /// Resume the first waiter whose predicate matches, removing it from
    /// the registry. Late or unmatched packets are silently dropped.
    func deliver(_ packet: RtcpPacket) {
        guard let idx = waiters.firstIndex(where: { $0.predicate(packet) }) else {
            return
        }
        let waiter = waiters.remove(at: idx)
        waiter.continuation.resume(returning: packet)
    }

    /// Wait for the next packet matching `predicate`. Cancellation removes
    /// the waiter and resumes with `CancellationError` — never a late
    /// packet — so subsequent uses of the inbox are unaffected.
    func waitFor(_ predicate: @escaping Predicate) async throws -> RtcpPacket {
        nextID &+= 1
        let id = nextID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RtcpPacket, Error>) in
                // We are already on the actor; the body runs synchronously
                // here and finishes registering before we suspend, so any
                // cancellation Task scheduled below will see the waiter.
                self.waiters.append(Waiter(id: id, predicate: predicate, continuation: cont))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    /// Resume every pending waiter with `error`. Useful for explicit
    /// shutdown so callers don't hang waiting on responses that will
    /// never arrive.
    func cancelAll(error: Error = CancellationError()) {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.continuation.resume(throwing: error)
        }
    }

    private func cancelWaiter(id: UInt64) {
        guard let idx = waiters.firstIndex(where: { $0.id == id }) else {
            // Already removed by deliver() — its continuation has been
            // resumed with the matching packet, nothing to do here.
            return
        }
        let waiter = waiters.remove(at: idx)
        waiter.continuation.resume(throwing: CancellationError())
    }
}
