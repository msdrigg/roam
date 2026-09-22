@preconcurrency import AVFoundation
import CoreAudio
import Opus
import os

struct AudioFrame {
    let frame: AVAudioPCMBuffer
    let scheduleAt: AVAudioFramePosition
}

#if !os(macOS)
    /// Serializes AVAudioSession configuration off the main actor.
    ///
    /// `setCategory`/`setActive` block on synchronous IPC to mediaserverd, which
    /// can take hundreds of milliseconds when the route is changing or another
    /// app holds the session. Calling them from the main actor hangs the UI, so
    /// every configuration call goes through here instead.
    actor AudioSessionConfigurator {
        static let shared = AudioSessionConfigurator()

        /// Releases the session so other apps can resume playback.
        func deactivate(category: AVAudioSession.Category) throws {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(category)
            try session.setActive(false)
        }

        /// The system output volume, as reported by the shared session.
        var outputVolume: Float {
            AVAudioSession.sharedInstance().outputVolume
        }

        /// The current output latency, which changes as the route changes.
        var outputLatency: TimeInterval {
            AVAudioSession.sharedInstance().outputLatency
        }
    }
#endif

actor OpusDecoderWithJitterBuffer {
    var jitterBuffer = MaxHeap<RtpPacket>()
    let opusDecoder: Opus.RoamDecoder
    var packetsPerSec: Int64 {
        1000 / globalPacketSizeMS
    }

    var lastPacketNumber: Int64 = 0
    var syncPacket: RtpPacket?
    var lastSampleTime: AVAudioTime?
    let audioBufferDuration: TimeInterval
    var rollingSequenceNumber: Int64?
    var decodedRealPackets: Int64 = 0
    var concealedPackets: Int64 = 0
    var bufferFillConcealedPackets: Int64 = 0

    init(audioBuffer: TimeInterval) throws {
        guard
            let opusFormat = AVAudioFormat(
                opusPCMFormat: .float32, sampleRate: Double(globalClockRate), channels: 2)
        else {
            loggedFatalError("Error initializing opus av format. This is a bug")
        }
        do {
            opusDecoder = try Opus.RoamDecoder(format: opusFormat)
        } catch {
            Log.headphones.error("Error initializing opus decoder \(error, privacy: .public)")
            throw error
        }
        self.audioBufferDuration = audioBuffer
    }

    func syncAudio(time: AVAudioTime, additionalAudioDelay: TimeInterval) -> Bool {
        guard let syncPacket else {
            Log.headphones.notice("Not synced packet yet. Can't sync audio yet")
            return false
        }
        Log.headphones.notice(
            "Syncing time with additional audio delay \(additionalAudioDelay, privacy: .public) buffer \(self.audioBufferDuration, privacy: .public)"
        )

        let packetsInBuffer = Int64(audioBufferDuration * Double(packetsPerSec))

        // Estimating getting 100 packets per second
        let currentEstimatedPacketNumber =
            Int64(
                (machTimeToSeconds(time.hostTime) - machTimeToSeconds(syncPacket.receivedAt))
                    * Double(packetsPerSec)) + Int64(syncPacket.sequenceNumber)
        // Don't wrap into UInt16 - rolling sequence numbers live in Int64
        // space, and a "negative" lastPacketNumber is the correct way to
        // express "we haven't filled the buffer yet, hold packets until
        // playback catches up".
        lastPacketNumber = currentEstimatedPacketNumber - packetsInBuffer
        lastSampleTime = AVAudioTime(
            hostTime: time.hostTime + secondsToMachTime(additionalAudioDelay),
            sampleTime: time.sampleTime + Int64(time.sampleRate * additionalAudioDelay),
            atRate: time.sampleRate
        )
        rollingSequenceNumber = lastPacketNumber + packetsInBuffer

        return true
    }

    func addPacket(packet: RtpPacket) {
        if syncPacket == nil {
            syncPacket = packet
        }
        var packet = packet
        rollingSequenceNumber = packet.updateWithRollingSequenceNumber(rollingSequenceNumber)

        // Check payload type
        if packet.payloadType != PayloadType(97) || packet.ssrc != 0 {
            // Invalid payload
            Log.headphones.error(
                "Error bad packet ssrc (\(packet.ssrc, privacy: .public) or payload type (\(packet.payloadType.rawValue, privacy: .public))"
            )
        }
        if lastPacketNumber < packet.sequenceNumber {
            //            Log.headphones.debug("Adding packet with seqNo \(packet.packet.sequenceNumber) when current seqNo is
            //            \(self.lastPacketNumber)")
            jitterBuffer.insert(packet)
        } else {
            Log.headphones
                .error(
                    "Error bad packet with seqNo \(packet.unwrappedSequenceNumber, privacy: .public) when current seqNo is \(self.lastPacketNumber, privacy: .public) rollingSeqNo \(self.rollingSequenceNumber ?? 0, privacy: .public)"
                )
        }
    }

    func nextPacket(atTime _: sending AVAudioTime) -> sending (AVAudioPCMBuffer, AVAudioTime)? {
        guard let lastSampleTime else {
            return nil
        }

        // No need to worry about wrapping because we get several years of stream before we wrap
        var nextPacket: RtpPacket?
        while true {
            if let np = jitterBuffer.peek(),
                np.sequenceNumber <= lastPacketNumber + 1
            {
                if let destroyed = nextPacket {
                    Log.headphones
                        .error(
                            "Destroying packet \(destroyed.sequenceNumber, privacy: .public) when lastPacket \(self.lastPacketNumber, privacy: .public) next packet \(np.sequenceNumber, privacy: .public)"
                        )
                }
                nextPacket = jitterBuffer.remove()
            } else {
                break
            }
        }

        // During the initial buffer-fill window (before any real packet
        // has been decoded), `nextPacket == nil` is *expected*: lpn is
        // intentionally seeded negative by `syncAudio` so PLC silence
        // covers the gap until the buffer reaches its target depth. Only
        // log/count concealments as real losses once playback has begun.
        let inBufferFill = decodedRealPackets == 0
        if nextPacket == nil, !inBufferFill {
            Log.headphones
                .error(
                    "Missing packet \(String(describing: self.jitterBuffer.peek()), privacy: .public), lpn \(self.lastPacketNumber)"
                )
        }

        // Need to get schedule time for when to schedule the packet
        let sampleTime = AVAudioTime(
            hostTime: secondsToMachTime(Double(globalPacketSizeMS) / 1000)
                + lastSampleTime.hostTime,
            sampleTime: lastSampleTime.sampleTime + Int64(lastSampleTime.sampleRate)
                / packetsPerSec,
            atRate: lastSampleTime.sampleRate
        )

        self.lastSampleTime = sampleTime
        lastPacketNumber += 1

        let nextPcm: AVAudioPCMBuffer
        do {
            if let np = nextPacket {
                nextPcm = try opusDecoder.decode(np.payload)
                decodedRealPackets += 1
                if decodedRealPackets == 1 {
                    Log.headphones
                        .notice(
                            "Buffer fill complete: emitted \(self.bufferFillConcealedPackets, privacy: .public) concealment frames before first real packet at seqNo \(np.sequenceNumber, privacy: .public)"
                        )
                }
                if decodedRealPackets % 100 == 0 {
                    Log.headphones
                        .notice(
                            "Decoded \(self.decodedRealPackets, privacy: .public) real packets, concealed \(self.concealedPackets, privacy: .public) (+\(self.bufferFillConcealedPackets, privacy: .public) buffer-fill), lpn \(self.lastPacketNumber, privacy: .public)"
                        )
                }
            } else {
                nextPcm = try opusDecoder.decode_loss_concealment(
                    sampleCount: Int64(globalClockRate) / packetsPerSec)
                if inBufferFill {
                    bufferFillConcealedPackets += 1
                } else {
                    concealedPackets += 1
                    Log.headphones.error(
                        "Getting loss concealment packet for sqNo \(self.lastPacketNumber, privacy: .public)"
                    )
                }
            }
        } catch {
            Log.headphones.error("Error decoding packet \(error, privacy: .public)")
            return nil
        }

        guard sampleTime.isSampleTimeValid else {
            return nil
        }

        return (
            nextPcm,
            AVAudioTime(
                hostTime: secondsToMachTime(Double(globalPacketSizeMS) / 1000)
                    + lastSampleTime.hostTime,
                sampleTime: lastSampleTime.sampleTime + Int64(lastSampleTime.sampleRate)
                    / packetsPerSec,
                atRate: lastSampleTime.sampleRate
            )
        )
    }
}

enum AudioPlayerError: Error, LocalizedError {
    case engineNotRunningOnPlay
    /// The output device reports a format nothing can be rendered into -- zero
    /// channels or a zero sample rate. Seen on macOS between the old default
    /// output device going away and a new one being picked.
    case noUsableOutputFormat(AVAudioFormat)
    /// No converter could be built from Opus's 48 kHz stereo float into the
    /// device's current format.
    case cannotConvertToOutputFormat(AVAudioFormat)
    /// AVFAudio raised an Objective-C exception. Carries its reason.
    case avfAudioRaised(String)

    var errorDescription: String? {
        switch self {
        case .engineNotRunningOnPlay:
            "The audio engine would not start."
        case .noUsableOutputFormat(let format):
            "The audio output device reported an unusable format: \(format)."
        case .cannotConvertToOutputFormat(let format):
            "Audio cannot be converted into the output device's format: \(format)."
        case .avfAudioRaised(let reason):
            "The audio engine rejected playback: \(reason)."
        }
    }
}

/// Runs `body`, turning an Objective-C exception raised inside AVFAudio into a
/// thrown `AudioPlayerError` instead of a `SIGABRT`. See `ObjCExceptionTrap.h`.
private func catchingAVFAudioExceptions(_ body: () -> Void) throws {
    var error: NSError?
    if !roamRunCatchingNSException(body, &error) {
        let reason = error?.localizedDescription ?? "unknown reason"
        Log.headphones.error("AVFAudio raised: \(reason, privacy: .public)")
        throw AudioPlayerError.avfAudioRaised(reason)
    }
}

actor AudioPlayer {
    private let engine: AVAudioEngine
    private let streamAudioNode: AVAudioPlayerNode
    /// Built against `graphFormat`, and rebuilt with it. Not `let`: on macOS the
    /// default output device can change under a live engine, and a converter
    /// producing the old device's format makes `scheduleBuffer` raise.
    private var converter: AVAudioConverter?
    /// The output format the current graph and `converter` were negotiated
    /// against, or nil before the first successful `start()`.
    private var graphFormat: AVAudioFormat?

    /// Opus decodes to this, and it is the converter's input format throughout.
    private static let opusFormat = AVAudioFormat(
        opusPCMFormat: .float32, sampleRate: 48000, channels: 2)!

    public init() {
        engine = AVAudioEngine()
        streamAudioNode = AVAudioPlayerNode()
        engine.attach(streamAudioNode)
    }

    /// Points the graph at whatever the output device is now.
    ///
    /// The connections and the converter used to be made once in `init` and kept
    /// for the life of the player. That holds on iOS, where a route change tears
    /// the session down and `handleRouteChange` rebuilds it, but not on macOS,
    /// which has no equivalent observer here: the user switches default output
    /// device, `engine.start()` succeeds against the new one, and the player node
    /// is still connected with the *old* device's format. `play()` then raises,
    /// which is `SIGABRT`, which is the 1.51 crash on thread 1540766480533291048.
    ///
    /// Re-reading the format on every `start()` costs nothing and removes the
    /// stale-format window entirely.
    private func prepareGraph() throws {
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        guard outputFormat.channelCount > 0, outputFormat.sampleRate > 0 else {
            throw AudioPlayerError.noUsableOutputFormat(outputFormat)
        }

        if let graphFormat, graphFormat.isEqual(outputFormat), converter != nil {
            return
        }

        Log.headphones
            .notice(
                "Rebuilding audio graph for output format \(outputFormat, privacy: .public) (was \(String(describing: self.graphFormat), privacy: .public))"
            )

        // Invalidate before touching the graph, not after building it: every
        // path out of here from this point either completes the rebuild or
        // throws, and a throw must not leave a format cached that would make the
        // next call take the early return above against a half-rebuilt graph.
        graphFormat = nil
        converter = nil

        // Connecting with `format: nil` lets each node adopt the format of what
        // it is being connected to, so this re-derives the whole chain from the
        // device rather than from whatever it was built against last time.
        try catchingAVFAudioExceptions {
            engine.connect(streamAudioNode, to: engine.mainMixerNode, format: nil)
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        }

        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: Self.opusFormat, to: mixerFormat) else {
            throw AudioPlayerError.cannotConvertToOutputFormat(mixerFormat)
        }
        self.converter = converter
        graphFormat = outputFormat
    }

    #if !os(macOS)
        func makeInactive() {
            do {
                try AVAudioSession.sharedInstance().setActive(false)
            } catch {
                Log.headphones.error(
                    "Failed to disable audio session active: \(error, privacy: .public)")
            }
        }
        func configureAudioSession() {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [])
            try? session.setActive(true)
            self.setupNotifications()
        }

        private func setupNotifications() {
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard
                    let info = notification.userInfo,
                    let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                    let type = AVAudioSession.InterruptionType(rawValue: typeValue)
                else { return }

                let reasonValue = info[AVAudioSessionInterruptionReasonKey] as? UInt ?? 0
                let reason = AVAudioSession.InterruptionReason(rawValue: reasonValue)

                let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                Task {
                    await self?.handleInterruption(reason: reason, options: options, type: type)
                }
            }

            NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard
                    let info = notification.userInfo,
                    let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                    let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
                else { return }
                Task { await self?.handleRouteChange(reason: reason) }
            }

            NotificationCenter.default.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { await self?.handleMediaServicesReset() }
            }
        }

        private func handleInterruption(
            reason: AVAudioSession.InterruptionReason?, options: AVAudioSession.InterruptionOptions,
            type: AVAudioSession.InterruptionType
        ) {
            switch type {
            case .began:
                stop()
            case .ended:
                if options.contains(.shouldResume) {
                    restartAudio()
                }
            @unknown default:
                break
            }
        }

        private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
            switch reason {
            case .oldDeviceUnavailable:
                stop()
            case .newDeviceAvailable, .routeConfigurationChange:
                restartAudio()
            default:
                break
            }
        }

        private func handleMediaServicesReset() {
            stop()
            engine.reset()
            engine.attach(streamAudioNode)
            // `reset()` drops the connections, so the cached format no longer
            // describes a graph that exists. Clearing it is what makes
            // `prepareGraph` rebuild rather than take its early return.
            graphFormat = nil
            converter = nil
            restartAudio()
        }
    #endif

    public func start() throws {
        // Before starting: `engine.start()` needs a graph that already reaches
        // the output node. `init` no longer builds one, so this is what makes
        // the first start valid.
        try prepareGraph()
        try engine.start()
        guard engine.isRunning else {
            throw AudioPlayerError.engineNotRunningOnPlay
        }
        // And again now that the engine has bound to a device, which is the
        // point the format becomes authoritative. Rebuilds only if it moved
        // between the two calls; otherwise it takes the early return and costs a
        // format comparison.
        try prepareGraph()
        try catchingAVFAudioExceptions { streamAudioNode.play() }
        Log.headphones
            .notice(
                "AudioPlayer started - engine running=\(self.engine.isRunning, privacy: .public), player playing=\(self.streamAudioNode.isPlaying, privacy: .public), output format=\(String(describing: self.engine.mainMixerNode.outputFormat(forBus: 0)), privacy: .public)"
            )
    }

    public func isHealthy() -> Bool {
        engine.isRunning && streamAudioNode.isPlaying
    }

    #if os(macOS)
        func getOutputLatency() -> TimeInterval {
            engine.outputNode.presentationLatency
        }
    #else
        func getOutputLatency() -> TimeInterval {
            AVAudioSession.sharedInstance().outputLatency
        }
    #endif

    private var scheduledCount: Int64 = 0

    public func scheduleAudioBytes(
        buffer: sending AVAudioPCMBuffer,
        atTime: sending AVAudioTime
    ) async {
        // nil between construction and the first successful `start()`, and again
        // if a graph rebuild failed. Dropping the buffer is right either way:
        // there is no format to render it into.
        guard let converter else {
            Log.headphones.error("Dropping audio buffer: no converter, graph is not prepared")
            return
        }

        guard
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: converter.outputFormat,
                frameCapacity: AVAudioFrameCount(converter.outputFormat.sampleRate)
                    * buffer.frameLength
                    / AVAudioFrameCount(buffer.format.sampleRate)
            )
        else {
            Log.headphones
                .error(
                    "Dropping audio buffer: could not allocate output buffer in \(converter.outputFormat, privacy: .public)"
                )
            return
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { [buffer] _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            Log.headphones.error("Error converting buffers \(error, privacy: .public)")
            return
        }

        scheduledCount += 1
        if scheduledCount % 100 == 1 {
            Log.headphones
                .notice(
                    "Scheduling buffer #\(self.scheduledCount, privacy: .public) at sampleTime=\(atTime.sampleTime, privacy: .public) (engine running=\(self.engine.isRunning, privacy: .public), player playing=\(self.streamAudioNode.isPlaying, privacy: .public))"
                )
        }
        // `scheduleBuffer` raises if the buffer's format does not match what the
        // node is connected with. `prepareGraph` keeps those in step, but a
        // device change landing between the convert above and this call would
        // still abort the process, so take the same backstop as `play()`.
        do {
            try catchingAVFAudioExceptions { streamAudioNode.scheduleBuffer(outputBuffer, at: atTime) }
        } catch {
            Log.headphones.error("Dropping audio buffer: \(error, privacy: .public)")
        }
    }

    /// `playerTime(forNodeTime:)` raises "player did not see an IO cycle" when
    /// the engine stops rendering under a playing node, as it does across a
    /// macOS output-device change.
    public func lastRender() throws -> AVAudioTime? {
        guard engine.isRunning, streamAudioNode.isPlaying,
            let lrt = streamAudioNode.lastRenderTime
        else {
            return nil
        }
        var playerTime: AVAudioTime?
        try catchingAVFAudioExceptions { playerTime = streamAudioNode.playerTime(forNodeTime: lrt) }
        return playerTime
    }

    public func stop() {
        Log.headphones.notice("Stopping audioplayer")
        engine.stop()
        streamAudioNode.stop()
    }

    /// Same contract as `start()`, but for the notification handlers, which have
    /// nowhere to throw to. Previously this called `play()` with no `isRunning`
    /// check at all -- strictly weaker than `start()` against the same raise.
    private func restartAudio() {
        do {
            try start()
        } catch {
            Log.headphones.error("Failed to restart audio: \(error, privacy: .public)")
        }
    }
}

func machTimeToSeconds(_ machTime: UInt64) -> Double {
    var timebaseInfo = mach_timebase_info()
    mach_timebase_info(&timebaseInfo)
    let machTimeInNanoseconds =
        Double(machTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
    let machTimeInSeconds = machTimeInNanoseconds / 1_000_000_000.0
    return machTimeInSeconds
}

func secondsToMachTime(_ seconds: Double) -> UInt64 {
    var timebaseInfo = mach_timebase_info()
    mach_timebase_info(&timebaseInfo)
    let machTimeInNanoseconds = max(seconds * 1_000_000_000.0, 0.0)
    let machTime =
        UInt64(machTimeInNanoseconds) * UInt64(timebaseInfo.denom) / UInt64(timebaseInfo.numer)
    return machTime
}

extension AVAudioTime {
    func offsetFromNow() -> TimeInterval {
        let timeNow = mach_absolute_time()
        let machTime = Int64(hostTime) - Int64(timeNow)

        var timebaseInfo = mach_timebase_info()
        mach_timebase_info(&timebaseInfo)
        let machTimeInNanoseconds =
            Double(machTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
        let machTimeInSeconds = machTimeInNanoseconds / 1_000_000_000.0
        return machTimeInSeconds
    }
}
