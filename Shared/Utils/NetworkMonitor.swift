import Network
import OSLog
import SwiftUI

@MainActor @Observable
final class NetworkMonitor {
    var networkConnection: NetworkType = .local
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue.networkQueue
#if !os(watchOS)
    weak var appDelegate: RoamAppDelegate?
#endif

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Log.network.notice("Getting new network path \(String(describing: path))")
            DispatchQueue.main.async { [weak self] in
                let previouslySatisfied = self?.networkConnection == .local
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
                Log.network
                    .notice(
                        "Getting new network \(String(describing: path), privacy: .public). Updating self type to \(String(describing: self?.networkConnection), privacy: .public)"
                    )

#if !os(watchOS)
                let nowSatisfied = self?.networkConnection == .local
                if !previouslySatisfied && nowSatisfied {
                    Task {
                        try? await self?.appDelegate?.ecpMonitor.ecpClient?.getDeviceInfo()
                    }
                }
#endif
            }
        }
    }

    func startMonitoring() {
        Log.network.notice("Starting to monitor network path updates for display")
        monitor.start(queue: queue)
    }

    enum NetworkType {
        case local
        case expensiveLocal
        case remote
        case other
        case none
    }
}
