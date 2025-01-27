#if os(iOS)
    import AVFoundation
    import Foundation
    import os

    enum VolumeClicked: String, CaseIterable {
        case up
        case down
    }

    struct VolumeEvent {
        let direction: VolumeClicked
        let volume: Float
    }

    actor VolumeListener {
        private static nonisolated let logger = Logger(
            subsystem: getLogSubsystem(),
            category: String(describing: VolumeListener.self)
        )

        var volumeObservation: NSKeyValueObservation?
        var lastVolume: Float = 0.5
        var volumeChangeHandler: ((VolumeClicked, Float) -> Void)?
        let session: AVAudioSession

        init(session: AVAudioSession) {
            self.session = session
        }

        func startListening() throws {
            do {
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                lastVolume = session.outputVolume
            } catch {
                Self.logger.error("Cannot activate audiosession to listen to volume: \(error, privacy: .public)")
                throw error
            }
            Self.logger.notice("Starting volume observations")

            volumeObservation = session.observe(
                \.outputVolume,
                options: [.new],
                changeHandler: { [weak self] session, _ in
                    guard let self else { return }
                    Task {
                        if !Task.isCancelled {
                            await self.newVolumeObserved(session.outputVolume)
                        }
                    }
                }
            )
        }

        func newVolumeObserved(_ newVolume: Float) {
            if newVolume > lastVolume {
                volumeChangeHandler?(.up, newVolume)
            } else if newVolume < lastVolume {
                volumeChangeHandler?(.down, newVolume)
            }

            lastVolume = newVolume
        }

        func stopListening() {
            Self.logger.notice("Stoping volume observations")
            volumeObservation?.invalidate()
            volumeObservation = nil
        }

        var events: AsyncStream<VolumeEvent>? {
            AsyncStream { continuation in
                do {
                    try startListening()
                    self.volumeChangeHandler = { direction, volume in
                        continuation.yield(VolumeEvent(direction: direction, volume: volume))
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
