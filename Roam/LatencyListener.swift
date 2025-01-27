import Foundation
import os.log

#if os(iOS) || os(tvOS) || os(visionOS)
    import AVFoundation

    @MainActor
    class LatencyListener {
        private static nonisolated let logger = Logger(
            subsystem: getLogSubsystem(),
            category: String(describing: LatencyListener.self)
        )

        var latencyChangeHandler: ((Double) -> Void)?
        var observerTokens: [Any] = []
        let audioSession = AVAudioSession.sharedInstance()

        func startListening() throws {
            Self.logger.notice("Starting Latency observations")
            // Get the default notification center instance.
            let token = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let self {
                        self.latencyChangeHandler?(self.audioSession.outputLatency)
                    }
                }
            }

            self.observerTokens.append(token)
        }

        func stopListening() {
            Self.logger.notice("Stoping Latency observations")

            let ot = self.observerTokens
            self.observerTokens = []
            for token in ot {
                NotificationCenter.default.removeObserver(token)
            }
        }

        var events: AsyncStream<Double>? {
            AsyncStream { continuation in
                do {
                    try startListening()
                    self.latencyChangeHandler = { newValue in
                        continuation.yield(newValue)
                    }
                    continuation.onTermination = { @Sendable _ in
                        Task {
                            await self.stopListening()
                        }
                    }
                } catch {}
            }
        }
    }
#endif

#if os(macOS)
    import CoreAudio

    actor LatencyListener {
        private static nonisolated let logger = Logger(
            subsystem: getLogSubsystem(),
            category: String(describing: LatencyListener.self)
        )

        var latencyChangeHandler: ((Double) -> Void)?
        var audioDeviceChangeListener: AudioObjectPropertyListenerBlock?

        var defaultDeviceAddress: AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        }

        func getDeviceLatency(deviceID: AudioDeviceID) -> Double? {
            var latency: UInt32 = 0
            var propSize = UInt32(MemoryLayout<UInt32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyLatency,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )

            let err = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propSize, &latency)
            if err != kAudioHardwareNoError {
                Self.logger.error("Failed to get latency for device \(deviceID, privacy: .public), error: \(err, privacy: .public)")
                return nil
            }

            var sampleRate: Float64 = 0
            var size = UInt32(MemoryLayout.size(ofValue: sampleRate))
            var sampleRateAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )

            let sampleRateErr = AudioObjectGetPropertyData(deviceID, &sampleRateAddress, 0, nil, &size, &sampleRate)
            if sampleRateErr != kAudioHardwareNoError {
                Self.logger
                    .error("Failed to get sample rate for device \(deviceID, privacy: .public), error: \(err, privacy: .public). Defaulting to 48000")
                sampleRate = 48000
            }

            return Double(latency) / sampleRate
        }

        func latencyChangeHandlerIsolated(_ val: Double) {
            self.latencyChangeHandler?(val)
        }

        func startListening() {
            Self.logger.notice("Starting Latency observations")

            var defaultDeviceAddress = defaultDeviceAddress

            audioDeviceChangeListener = { _, _ in
                var size = UInt32(MemoryLayout<AudioDeviceID>.size)

                // Listener for latency changes on the default output device
                var listeningDeviceId: AudioDeviceID = 0
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &defaultDeviceAddress,
                    0,
                    nil,
                    &size,
                    &listeningDeviceId
                )

                self.latencyChangeHandlerIsolated(self.getDeviceLatency(deviceID: listeningDeviceId) ?? 0)
            }

            let err = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultDeviceAddress,
                nil,
                audioDeviceChangeListener!
            )

            if err != kAudioHardwareNoError {
                Self.logger.error("Error adding audio property listener for default output device: \(err, privacy: .public)")
            }
        }

        func stopListening() {
            Self.logger.notice("Stopping Latency observations")

            var defaultDeviceAddress = defaultDeviceAddress

            if let listener = self.audioDeviceChangeListener {
                AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject),
                    &defaultDeviceAddress,
                    nil,
                    listener
                )
            }
        }

        var events: AsyncStream<Double>? {
            AsyncStream { continuation in
                startListening()
                latencyChangeHandler = { newValue in
                    continuation.yield(newValue)
                }
                continuation.onTermination = { @Sendable _ in
                    Task {
                        await self.stopListening()
                    }
                }
            }
        }
    }
#endif
