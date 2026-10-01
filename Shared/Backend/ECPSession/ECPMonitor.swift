#if !os(watchOS)
import SwiftUI
import OSLog

enum TextEditStatus: Equatable, Hashable {
    case editing(TextEditState)
    case off

    var isActive: Bool {
        return switch self {
        case .editing: true
        case .off: false
        }
    }

    var text: String? {
        return switch self {
        case let .editing(state): state.text ?? ""
        case .off: nil
        }
    }

    var texteditId: String? {
        return switch self {
        case let .editing(state):
            if state.texteditId == "none" || state.texteditId == "" {
                nil
            } else {
                state.texteditId
            }
        case .off: nil
        }
    }
}

@MainActor @Observable
final class ECPMonitor {
    var status: ECPWebsocketState = .disconnected(.distantPast)
    var textEditStatus: TextEditStatus = .off
    var ecpClient: ECPWebsocketClient?

    // Incremented on every client switch. Callbacks capture the value they
    // were created under and no-op once it moves on.
    private var generation = 0
    private var reconnectTask: Task<Void, Never>?
    private var lastPathKick: Date?
    private static let minPathKickInterval: TimeInterval = 2

    func setDevice(_ device: Device?) {
        // Re-selecting the current device must not tear down the session; the
        // reconnect loop already revives an unhealthy one.
        if let device, let current = ecpClient, current.location.absoluteString == device.location {
            return
        }

        generation += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        let oldEcpClient = self.ecpClient
        self.ecpClient = nil

        guard let device, let url = URL(string: device.location) else {
            if device != nil {
                Log.connection.error("Could not parse URL for selected device \(device?.location ?? "nil", privacy: .public)")
            }
            status = .disconnected(.now)
            textEditStatus = .off
            Task {
                await oldEcpClient?.shutdown()
            }
            return
        }
        let generation = self.generation
        let ecpClient = ECPWebsocketClient(
            location: url,
            macs: device.macs(),
            websocketStateUpdated: {[weak self] state in
                Log.connection.notice("Getting new ws state \(state.debugDescription, privacy: .public)")
                DispatchQueue.main.async {
                    self?.handleStateChange(state, generation: generation)
                }
            },
            notificationHandler: {[weak self] notification in
                DispatchQueue.main.async {
                    self?.handleNotification(notification, generation: generation)
                }
            }
        )
        self.ecpClient = ecpClient
        self.status = .connecting(.now)
        self.textEditStatus = .off
        // One serialized task, so the old client is retired before the new one
        // starts and a racing `setDevice` cannot leave an orphan connection.
        Task {
            await oldEcpClient?.shutdown()
            await ecpClient.start()
            do {
                try await ecpClient.requestEventsNotify()
            } catch {
                Log.connection.error("Error requesting events notify \(error, privacy: .public)")
            }
        }
    }

    private func handleStateChange(_ state: ECPWebsocketState, generation: Int) {
        guard generation == self.generation else {
            Log.connection.notice("Ignoring ws state \(state.debugDescription, privacy: .public) from retired client")
            return
        }
        status = state
        switch state {
        case .connected:
            reconnectTask?.cancel()
            reconnectTask = nil
        case .disconnected:
            scheduleReconnect(generation: generation)
        case .connecting:
            break
        }
    }

    private func handleNotification(_ notification: ECPNotification, generation: Int) {
        guard generation == self.generation else { return }
        switch notification {
        case .texteditChanged(let state), .texteditOpened(let state):
            textEditStatus = .editing(state)
        case .texteditClosed:
            textEditStatus = .off
        }
    }

    /// Restarts a running reconnect loop from its shortest delay. A Wi-Fi roam
    /// or link-quality change keeps the same interface, so the backoff would
    /// otherwise sleep up to a minute past the moment the TV became reachable.
    func networkPathChanged() {
        guard reconnectTask != nil, case .disconnected = status else { return }
        if let lastPathKick, Date.now.timeIntervalSince(lastPathKick) < Self.minPathKickInterval {
            return
        }
        lastPathKick = .now
        Log.connection.notice("Network path changed while disconnected, reconnecting now")
        reconnectTask?.cancel()
        reconnectTask = nil
        scheduleReconnect(generation: generation)
    }

    /// Retries `start()` on an exponential backoff whenever the client reports
    /// disconnected, until it connects or the monitor moves on.
    private func scheduleReconnect(generation: Int) {
        guard reconnectTask == nil else { return }
        Log.connection.notice("Scheduling ECP reconnect loop")
        reconnectTask = Task { [weak self] in
            for await _ in exponentialBackoff(min: 2, max: 60) {
                guard let self, !Task.isCancelled, generation == self.generation,
                      let client = self.ecpClient else { return }
                if case .connected = self.status { return }
                Log.connection.notice("Attempting ECP reconnect after backoff")
                await client.start()
            }
        }
    }
}
#endif
