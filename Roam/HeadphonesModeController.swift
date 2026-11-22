#if !os(macOS)
import AVFoundation
import Foundation
import Observation
import os

/// Owns the headphones mode stream for the whole app, so it outlives the
/// remote page that started it. Pager pages are torn down and rebuilt on
/// rotation and while swiping, and a stream tied to one of them stopped with it.
@MainActor @Observable
final class HeadphonesModeController {
    /// The device currently streaming, or nil when headphones mode is off.
    private(set) var deviceId: String?
    var error: Error?
    private(set) var errorCount = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var visibleRemotes = 0
    @ObservationIgnored private var noRemoteStopTask: Task<Void, Never>?

    func isEnabled(for deviceId: String?) -> Bool {
        deviceId != nil && self.deviceId == deviceId
    }

    func toggle(device: Device?, ecpSession: ECPWebsocketClient?) {
        if let device, isEnabled(for: device.id) {
            stop()
        } else {
            start(device: device, ecpSession: ecpSession)
        }
    }

    /// Stops the stream when the user has settled on a different device.
    func deviceSelected(_ id: String) {
        if let deviceId, deviceId != id {
            stop()
        }
    }

    func remoteAppeared() {
        visibleRemotes += 1
        noRemoteStopTask?.cancel()
        noRemoteStopTask = nil
    }

    /// Stops the stream once no remote is left on screen, e.g. after going
    /// back to the device grid. The grace period covers a page being rebuilt
    /// on rotation, where the new page can appear after the old one leaves.
    func remoteDisappeared() {
        visibleRemotes = max(0, visibleRemotes - 1)
        guard visibleRemotes == 0 else { return }
        noRemoteStopTask?.cancel()
        noRemoteStopTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, visibleRemotes == 0 else { return }
            stop()
        }
    }

    /// The stream's task deactivates the audio session itself once it has wound down.
    func stop() {
        guard deviceId != nil else { return }
        Log.headphones.notice("Stopping headphones mode")
        generation += 1
        task?.cancel()
        deviceId = nil
    }

    private func start(device: Device?, ecpSession: ECPWebsocketClient?) {
        guard let device, let ecpSession else { return }
        // The previous stream must release the audio session and port 6970 before this one claims them.
        let previous = task
        previous?.cancel()
        generation += 1
        let generation = generation
        let location = device.location
        let rtcpPort = device.rtcpPort
        deviceId = device.id
        task = Task {
            await previous?.value
            do {
                try Task.checkCancellation()
                try await listenContinually(
                    ecpSession: ecpSession,
                    location: location,
                    rtcpPort: rtcpPort
                )
                Log.headphones.notice("Listencontinually returned \(#fileID, privacy: .public)")
            } catch HeadphonesModeError.headphonesDisconnected {
                Log.headphones.notice("Headphones disconnected, stopping headphones mode")
            } catch {
                Log.headphones.warning("Catching error in pl handler \(error, privacy: .public)")
                if !(error is CancellationError), generation == self.generation {
                    errorCount += 1
                    self.error = error
                }
            }
            if generation == self.generation {
                deviceId = nil
            }
            await deactivateAudioSession()
            if generation == self.generation {
                task = nil
            }
        }
    }

    private func deactivateAudioSession() async {
        #if os(iOS)
            do {
                try await AudioSessionConfigurator.shared.deactivate(category: .ambient)
            } catch {
                Log.headphones.notice(
                    "Unable to set AVAudioSession category to background: \(error, privacy: .public)")
            }
        #endif
    }
}
#endif
