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

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ECPMonitor")

@MainActor @Observable
class ECPMonitor {
    var status: ECPWebsocketState = .disconnected(.distantPast)
    var textEditStatus: TextEditStatus = .off
    var ecpClient: ECPWebsocketClient?

    func setDevice(_ device: DeviceAppEntity?) {
        guard let device, let url = URL(string: device.location) else {
            logger.info("Could not parse URL \(device?.location ?? "nil", privacy: .public)")

            let oldEcpClient = self.ecpClient
            self.ecpClient = nil
            Task {
                await oldEcpClient?.cancel()
            }
            return
        }
        let ecpClient = ECPWebsocketClient(
            location: url,
            macs: device.macs(),
            websocketStateUpdated: {[weak self] state in
                guard let self = self else { return }
                logger.info("Getting new ws state \(state.debugDescription, privacy: .public)")
                DispatchQueue.main.async {
                    self.status = state
                }
            },
            notificationHandler: {[weak self] notification in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch notification {
                    case .texteditChanged(let state):
                        self.textEditStatus = .editing(state)
                    case .texteditOpened(let state):
                        self.textEditStatus = .editing(state)
                    case .texteditClosed:
                        self.textEditStatus = .off
                    }
                }
            }
        )
        let oldEcpClient = self.ecpClient
        self.ecpClient = ecpClient
        Task {
            await ecpClient.start()
            await oldEcpClient?.cancel()
            do {
                try await ecpClient.requestEventsNotify()
            } catch {
                logger.error("Error requesting events notify \(error, privacy: .public)")
            }
        }
    }
}
#endif
