import Network
import OSLog
import SwiftUI

@MainActor @Observable
class NetworkMonitor {
    var networkConnection: NetworkType = .local
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private nonisolated static let logger = Logger(
        subsystem: getLogSubsystem(),
        category: String(describing: NetworkMonitor.self)
    )

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { [weak self] in
                if path.status == .satisfied {
                    if path.usesInterfaceType(.wifi) {
                        if path.isExpensive {
                            self?.networkConnection = .expensiveLocal
                        } else {
                            self?.networkConnection = .local
                        }
                    } else if path.usesInterfaceType(.wifi), !path.isExpensive {
                        self?.networkConnection = .expensiveLocal
                    } else if path.usesInterfaceType(.wiredEthernet) {
                        self?.networkConnection = .local
                    } else if path.usesInterfaceType(.cellular) {
                        self?.networkConnection = .remote
                    } else {
                        self?.networkConnection = .other
                    }
                } else {
                    self?.networkConnection = .none
                }
                Self.logger
                    .info(
                        "Getting new network \(String(describing: path), privacy: .public). Updating self type to \(String(describing: self?.networkConnection), privacy: .public)"
                    )
            }
        }
    }

    func startMonitoring() {
        Self.logger.notice("Starting to monitor network path updates for display")
        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor.cancel()
    }

    enum NetworkType {
        case local
        case expensiveLocal
        case remote
        case other
        case none
    }
}
