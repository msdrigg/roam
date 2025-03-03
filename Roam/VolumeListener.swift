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
                Log.userInteraction.error("Cannot activate audiosession to listen to volume: \(error, privacy: .public)")
                throw error
            }
            Log.userInteraction.notice("Starting volume observations")

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
            Log.userInteraction.notice("Stoping volume observations")
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
