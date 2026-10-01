import Network
import OSLog
import SwiftUI

@MainActor @Observable
final class NetworkMonitor {
    var networkConnection: NetworkType = .local
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue.makeNetworkQueue()
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
                if path.status == .satisfied {
                    self?.appDelegate?.ecpMonitor.networkPathChanged()
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

/// Live reachability for every device in a list, not just the connected one.
///
/// `Device.lastOnlineAt` is only stamped by `refreshDevice`, which runs against
/// the connected device, so every other status dot stayed grey. This asks each
/// device directly with one `query/device-info` GET while a list is on screen.
///
/// Results stay in memory: writing a timestamp per device per cycle would put
/// app-group writes in the path of a suspension (0xdead10cc). The record's own
/// `lastOnlineAt` remains the fallback until the first probe lands.
@MainActor @Observable
final class DeviceLivenessMonitor {
    static let shared = DeviceLivenessMonitor()

    /// How long a probe result is trusted before falling back to the record.
    private static let resultTTL: TimeInterval = 90
    /// Floor between two probes of the same device, so several views watching
    /// the same devices don't multiply the traffic.
    private static let minProbeInterval: TimeInterval = 8
    private static let probeTimeout: TimeInterval = 2
    private static let maxConcurrentProbes = 6
    private static let probeInterval: TimeInterval = 15

    private struct ProbeResult {
        let isOnline: Bool
        let checkedAt: Date
    }

    private var results: [String: ProbeResult] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    /// Whether the device is reachable right now, falling back to its own
    /// `lastOnlineAt` until this device has been probed.
    func isOnline(_ device: Device?) -> Bool {
        if inScreenshotTestingContext() { return true }
        guard let device else { return false }

        if let result = results[device.id],
            Date().timeIntervalSince(result.checkedAt) < Self.resultTTL
        {
            return result.isOnline
        }
        return device.isOnline()
    }

    /// Probes `deviceIds` on a loop until the surrounding task is cancelled.
    func probeContinually(deviceIds: [String]) async {
        while !Task.isCancelled {
            await probe(deviceIds: deviceIds)
            do {
                try await Task.sleep(for: .seconds(Self.probeInterval))
            } catch {
                return
            }
        }
    }

    func probe(deviceIds: [String]) async {
        guard !inScreenshotTestingContext(), !deviceIds.isEmpty else { return }

        let now = Date()
        let due = deviceIds.filter { id in
            guard !inFlight.contains(id) else { return false }
            guard let result = results[id] else { return true }
            return now.timeIntervalSince(result.checkedAt) >= Self.minProbeInterval
        }
        guard !due.isEmpty else { return }

        // Claimed before the first `await`, so two views watching the same
        // devices can't both get past the filter and probe them twice.
        inFlight.formUnion(due)
        defer { inFlight.subtract(due) }

        let targets = await RoamDataHandler.shared.requestAllDevices(due)
            .map { (id: $0.id, location: $0.location) }
        guard !targets.isEmpty else { return }

        let timeout = Self.probeTimeout
        let stream = processConcurrently(
            items: targets, maxConcurrent: Self.maxConcurrentProbes
        ) { target in
            (target.id, await deviceRespondsToECP(location: target.location, timeout: timeout))
        }

        for await (id, isOnline) in stream {
            results[id] = ProbeResult(isOnline: isOnline, checkedAt: Date())
        }
    }
}

/// A single cheap request to a device's ECP port, used only to decide whether
/// it is reachable right now.
///
/// The body is not parsed; a status line is all the caller needs, which keeps
/// this affordable for a whole device list. Asking for `query/device-info`
/// rather than opening a socket means a reassigned DHCP lease reads as
/// offline.
func deviceRespondsToECP(location: String, timeout: TimeInterval) async -> Bool {
    guard let url = URL(string: "\(location)query/device-info") else {
        return false
    }
    var request = URLRequest(
        url: url,
        cachePolicy: .reloadIgnoringLocalCacheData,
        timeoutInterval: timeout
    )
    request.httpMethod = "GET"

    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        // 403 is a Roku refusing control from apps. It is very much powered on
        // and worth showing as such - the remote surfaces that refusal itself.
        return (200...299).contains(http.statusCode) || http.statusCode == 403
    } catch {
        return false
    }
}

extension View {
    /// Keeps the online dots for `deviceIds` fresh while this view is on screen.
    ///
    /// Pass `isActive: false` to stand down when backgrounded or off screen.
    func probingDeviceLiveness(_ deviceIds: [String], isActive: Bool = true) -> some View {
        task(id: "\(isActive)-\(deviceIds.joined(separator: "|"))") {
            guard isActive else { return }
            await DeviceLivenessMonitor.shared.probeContinually(deviceIds: deviceIds)
        }
    }
}
