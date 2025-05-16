@preconcurrency import AVFoundation
import CoreAudio
import os

struct AudioFrame {
    let frame: AVAudioPCMBuffer
    let scheduleAt: AVAudioFramePosition
}

actor OpusDecoderWithJitterBuffer {
    var jitterBuffer = MaxHeap<RtpPacket>()
    let opusDecoder: RoamDecoder
    var lastPacketNumber: Int64 = 0
    var syncPacket: RtpPacket?
    var lastSampleTime: AVAudioTime?
    let audioBufferDuration: TimeInterval
    var rollingSequenceNumber: Int64?

    init(audioBuffer: TimeInterval, outputFormat: AVAudioFormat) throws {
        guard let opusFormat = AVAudioFormat(opusPCMFormat: .float32, sampleRate: Double(globalClockRate), channels: 2)
        else {
            loggedFatalError("Error initializing opus av format. This is a bug")
        }
        do {
            opusDecoder = try RoamDecoder(opusFormat: opusFormat, outputFormat: outputFormat)
        } catch {
            Log.headphones.error("Error initializing opus decoder \(error, privacy: .public) with formats \(opusFormat, privacy: .public), \(outputFormat, privacy: .public) \(error, privacy: .public)")
            throw error
        }
        self.audioBufferDuration = audioBuffer
    }

    func syncAudio(time: AVAudioTime, additionalAudioDelay: TimeInterval) -> Bool {
        guard let syncPacket else {
            Log.headphones.notice("Not synced packet yet. Can't sync audio yet")
            return false
        }
        Log.headphones.notice("Syncing time with additional audio delay \(additionalAudioDelay, privacy: .public) buffer \(self.audioBufferDuration, privacy: .public)")

        let packetsInBuffer = Int64(audioBufferDuration * Double(globalPacketsPerSec))

        // Estimating getting 100 packets per second
        let currentEstimatedPacketNumber =
            Int64((machTimeToSeconds(time.hostTime) - machTimeToSeconds(syncPacket.receivedAt)) *
                Double(globalPacketsPerSec)) + Int64(syncPacket.sequenceNumber)
        lastPacketNumber = (currentEstimatedPacketNumber - packetsInBuffer + Int64(UInt16.max)) % Int64(UInt16.max)
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
            Log.headphones.error("Error bad packet ssrc (\(packet.ssrc, privacy: .public) or payload type (\(packet.payloadType.rawValue, privacy: .public))")
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

    func nextPacket(atTime _: sending AVAudioTime) -> (AVAudioPCMBuffer, AVAudioTime)? {
        guard let lastSampleTime else {
            Log.headphones.notice("Not returning packet because not synced yet")
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

        if nextPacket == nil {
            Log.headphones
                .error("Missing packet \(String(describing: self.jitterBuffer.peek()), privacy: .public), lpn \(self.lastPacketNumber)")
        }

        // Need to get schedule time for when to schedule the packet
        let sampleTime = AVAudioTime(
            hostTime: secondsToMachTime(Double(globalPacketSizeMS) / 1000) + lastSampleTime.hostTime,
            sampleTime: lastSampleTime.sampleTime + Int64(lastSampleTime.sampleRate) / globalPacketsPerSec,
            atRate: lastSampleTime.sampleRate
        )

        self.lastSampleTime = sampleTime
        lastPacketNumber += 1

        let nextPcm: AVAudioPCMBuffer
        do {
            if let np = nextPacket {
                Log.headphones.notice("Decoding payload len \(np.payload.count)")
                nextPcm = try opusDecoder.decode(np.payload)
                Log.headphones.notice("Got decoded packet \(nextPcm.frameLength, privacy: .public)")
            } else {
                Log.headphones.error("Getting loss concealment packet for sqNo \(self.lastPacketNumber, privacy: .public)")
//                nextPcm = try opusDecoder.decodeLossConcealment(opusSampleCount: Int64(globalClockRate) / globalPacketsPerSec)
                    nextPcm = try opusDecoder.decodeLossConcealment()
                Log.headphones.notice("Got loss concealment \(nextPcm.frameLength, privacy: .public)")
            }
        } catch {
            Log.headphones.error("Error decoding packet \(error, privacy: .public)")
            return nil
        }

        guard sampleTime.isSampleTimeValid else {
            return nil
        }

        return (nextPcm, AVAudioTime(
            hostTime: secondsToMachTime(Double(globalPacketSizeMS) / 1000) + lastSampleTime.hostTime,
            sampleTime: lastSampleTime.sampleTime + Int64(lastSampleTime.sampleRate) / globalPacketsPerSec,
            atRate: lastSampleTime.sampleRate
        ))
    }
}

enum AudioPlayerError: Error, LocalizedError {
    case engineNotRunningOnPlay
}

actor AudioPlayer {
    private let engine: AVAudioEngine
    private let streamAudioNode: AVAudioPlayerNode
    var outputFormat: AVAudioFormat {
        engine.mainMixerNode.outputFormat(forBus: 0)
    }

    public init() {
        engine = AVAudioEngine()
        streamAudioNode = AVAudioPlayerNode()
        engine.attach(streamAudioNode)

        engine.connect(streamAudioNode, to: engine.mainMixerNode, format: nil)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
    }

#if !os(macOS)
    func makeInactive() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            Log.headphones.error("Failed to disable audio session active: \(error, privacy: .public)")
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
            Task { await self?.handleInterruption(reason: reason, options: options, type: type) }
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

    private func handleInterruption(reason: AVAudioSession.InterruptionReason?, options: AVAudioSession.InterruptionOptions, type: AVAudioSession.InterruptionType) {
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
        engine.connect(streamAudioNode, to: engine.mainMixerNode, format: nil)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        restartAudio()
    }
#endif

    public func start() throws {
        try engine.start()
        guard engine.isRunning else {
            throw AudioPlayerError.engineNotRunningOnPlay
        }
        streamAudioNode.play()
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

    public func scheduleAudioBytes(
        buffer: sending AVAudioPCMBuffer,
        atTime: sending AVAudioTime
    ) async {
        await streamAudioNode.scheduleBuffer(buffer, at: atTime)
    }

    public func lastRender() throws -> AVAudioTime? {
        if let lrt = streamAudioNode.lastRenderTime {
            return try catchObjc {
                streamAudioNode.playerTime(forNodeTime: lrt)
            }
        }
        return nil
    }

    public func stop() {
        Log.headphones.notice("Stopping audioplayer")
        engine.stop()
        streamAudioNode.stop()
    }

    private func restartAudio() {
        try? engine.start()
        streamAudioNode.play()
    }
}

func machTimeToSeconds(_ machTime: UInt64) -> Double {
    var timebaseInfo = mach_timebase_info()
    mach_timebase_info(&timebaseInfo)
    let machTimeInNanoseconds = Double(machTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
    let machTimeInSeconds = machTimeInNanoseconds / 1_000_000_000.0
    return machTimeInSeconds
}

func secondsToMachTime(_ seconds: Double) -> UInt64 {
    var timebaseInfo = mach_timebase_info()
    mach_timebase_info(&timebaseInfo)
    let machTimeInNanoseconds = max(seconds * 1_000_000_000.0, 0.0)
    let machTime = UInt64(machTimeInNanoseconds) * UInt64(timebaseInfo.denom) / UInt64(timebaseInfo.numer)
    return machTime
}

extension AVAudioTime {
    func offsetFromNow() -> TimeInterval {
        let timeNow = mach_absolute_time()
        let machTime = Int64(hostTime) - Int64(timeNow)

        var timebaseInfo = mach_timebase_info()
        mach_timebase_info(&timebaseInfo)
        let machTimeInNanoseconds = Double(machTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
        let machTimeInSeconds = machTimeInNanoseconds / 1_000_000_000.0
        return machTimeInSeconds
    }
}
