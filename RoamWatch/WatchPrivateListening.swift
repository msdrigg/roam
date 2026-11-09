import AVFoundation
import Foundation
import Observation
import os

enum WatchPrivateListeningError: Error, LocalizedError {
    case badURL
    case noAudioRoute
    case notConnected

    var errorDescription: String? {
        switch self {
        case .badURL:
            return String(localized: "Invalid device address for headphones mode.", comment: "Error when the TV address can't be parsed")
        case .noAudioRoute:
            return String(
                localized: "Connect Bluetooth headphones to listen privately on your watch.",
                comment: "Error when no headphones were picked for watch private listening"
            )
        case .notConnected:
            return String(
                localized: "Couldn't reach the TV from your watch. Make sure the watch is on the same Wi-Fi network as the TV.",
                comment: "Error when the watch can't open a connection to the TV for private listening"
            )
        }
    }
}

/// Private listening on the watch. TN3135 only lets watchOS apps use the Network framework while
/// a long-form audio session is active, so the session comes up before the ECP websocket and the
/// RTP listeners open, and stays up until the stream ends.
@MainActor @Observable
final class WatchPrivateListening {
    private(set) var deviceId: String?
    var error: Error?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    func isEnabled(for deviceId: String?) -> Bool {
        deviceId != nil && self.deviceId == deviceId
    }

    func toggle(device: Device?) {
        if let device, isEnabled(for: device.id) {
            stop()
        } else {
            start(device: device)
        }
    }

    func stop() {
        guard deviceId != nil || task != nil else { return }
        Log.headphones.notice("Stopping watch private listening")
        generation += 1
        task?.cancel()
        task = nil
        deviceId = nil
    }

    private func start(device: Device?) {
        guard let device else { return }
        // The previous stream must release the audio session and port 6970 before this one claims them.
        let previous = task
        stop()
        let generation = generation
        let location = device.location
        let rtcpPort = device.rtcpPort
        deviceId = device.id
        task = Task {
            await previous?.value
            do {
                try Task.checkCancellation()
                try await Self.stream(location: location, rtcpPort: rtcpPort)
            } catch {
                Log.headphones.warning("Watch private listening ended: \(error, privacy: .public)")
                if !(error is CancellationError), generation == self.generation {
                    self.error = error
                }
            }
            if generation == self.generation {
                task = nil
                deviceId = nil
            }
        }
    }

    private nonisolated static func stream(location: String, rtcpPort: UInt16?) async throws {
        guard let url = URL(string: location) else {
            throw WatchPrivateListeningError.badURL
        }
        let session = WatchAudioSession()
        try await session.activate()

        let (states, stateContinuation) = AsyncStream<ECPWebsocketState>.makeStream()
        let ecpSession = ECPWebsocketClient(location: url, websocketStateUpdated: { stateContinuation.yield($0) })
        await ecpSession.start()

        let result: Result<Void, Error>
        do {
            // `requestHeadphonesMode` reads the local address off the connection's path, which a
            // connection that is still coming up doesn't have yet.
            try await withTimeout(delay: 10) {
                for await state in states where state == .connected {
                    return
                }
                throw WatchPrivateListeningError.notConnected
            }
            try await withThrowingDiscardingTaskGroup { group in
                group.addTask { await session.keepNetworkGranted() }
                group.addTask { try await session.waitForHeadphonesRemoved() }
                group.addTask {
                    try await listenContinually(ecpSession: ecpSession, location: location, rtcpPort: rtcpPort)
                }
            }
            result = .success(())
        } catch is TimeoutError {
            result = .failure(WatchPrivateListeningError.notConnected)
        } catch {
            result = .failure(error)
        }

        // Outside the cancelled task, so deactivate's retry delay still waits.
        await Task {
            await ecpSession.shutdown()
            await session.deactivate()
        }.value
        try result.get()
    }
}

/// Keeps the AVAudioSession IPC off the main actor.
private actor WatchAudioSession {
    // watchOS 26 withdraws the network grant about 36 s after each activation, even while audio
    // plays (FB24377808). Re-activating ahead of that keeps the RTP stream alive.
    private static let reactivateInterval: Duration = .seconds(30)

    func activate() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        // `setActive(true)` can succeed on watchOS without unlocking the network; only the
        // asynchronous activation does.
        guard try await session.activate(options: []) else {
            throw WatchPrivateListeningError.noAudioRoute
        }
        Log.headphones.notice("Watch audio session active on \(session.currentRoute.outputs.map(\.portName), privacy: .public)")
    }

    func keepNetworkGranted() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.reactivateInterval)
            guard !Task.isCancelled else { return }
            do {
                try await activate()
            } catch {
                Log.headphones.warning("Re-activating watch audio session failed: \(error, privacy: .public)")
            }
        }
    }

    /// Ends the stream when the headphones go away. AudioPlayer only stops the engine, which would
    /// leave the network running and the toggle on with nothing playing.
    func waitForHeadphonesRemoved() async throws {
        let notifications = NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification)
        for await notification in notifications {
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            if reason == .oldDeviceUnavailable {
                throw WatchPrivateListeningError.noAudioRoute
            }
        }
    }

    // RokuSession stops the audio engine from unstructured tasks, so it can still be running here,
    // and deactivating a session with running I/O fails.
    func deactivate() async {
        for attempt in 1 ... 5 {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                return
            } catch {
                Log.headphones.notice("Unable to deactivate watch audio session (attempt \(attempt, privacy: .public)): \(error, privacy: .public)")
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
}
