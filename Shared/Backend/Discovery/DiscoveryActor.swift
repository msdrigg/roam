import Foundation
import Network
import os
import SwiftUI

actor DeviceDiscoveryActor {
    @MainActor
    init() {}

    #if !os(watchOS)
    func addDevice(location: String, serial: String?) async throws {
        guard URL(string: location) != nil else {
            Log.scanning.error("Not adding device with location \(location, privacy: .public) b/c it's not a valid url")
            throw APIError.badURLError(location)
        }
        Log.scanning.notice("Trying to add device with location \(location, privacy: .public)")

        do {
            try await RoamDataHandler.shared.addOrReplaceDevice(location: location, serial: serial)
        } catch {
            Log.scanning.notice("Failed to add scanned device \(error, privacy: .public)")
        }
    }

    func scanIPV4Once() async {
        // Don't scan IPV4 in previews
        let runningInPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let runningInScreenshotTests = inScreenshotTestingContext()
        if runningInPreview || runningInScreenshotTests {
            Log.scanning.notice(
                "Skipping IPV4 scan runningInPreview=\(runningInPreview, privacy: .public) runningInScreenshotTests=\(runningInScreenshotTests, privacy: .public)"
            )
            return
        }

        Log.scanning.notice("Starting to scan ipv4 range")

        let maxConcurrentScanned = 37

        let ifaces = await  allAddressedInterfaces()
        let scannableInterfaces = ifaces.filter { $0.isIPv4 }
        let unscannableInterfaces = ifaces.filter { !$0.isIPv4 }.map(\.name)
        let scannableIfaceNames = scannableInterfaces.map(\.name)

        Log.scanning.notice("Scanning IPV4 interfaces \(scannableIfaceNames, privacy: .public), but ignoring \(unscannableInterfaces, privacy: .public)")

        var ifaceAddressPairs: [(Addressed4NetworkInterface, IP4Address)] = []

        for iface in scannableInterfaces {
            let range = iface.scannableIPV4NetworkRange
            if range.count > 1024 {
                Log.scanning.error("IPV4 range for \(iface.name, privacy: .public) has \(range.count, privacy: .public) items. Max is 1024. Only queuing 1024")
            } else {
                Log.scanning.notice("Queuing \(range.count, privacy: .public) devices in network range \(range, privacy: .public) with name \(iface.name, privacy: .public)")
            }
            var idx = 0

            for prioritizedRange in iface.preferredScannableIPV4Ranges {
                for ipAddress in prioritizedRange {
                    idx += 1
                    ifaceAddressPairs.append((iface, ipAddress))

                    if idx > 1024 {
                        break
                    }
                }

                if idx > 1024 {
                    break
                }
            }
        }

        let output = processConcurrently(items: ifaceAddressPairs, maxConcurrent: maxConcurrentScanned) { pair in await scanAddress(pair) }

        for await location in output {
            if let location {
                do {
                    try await self.addDevice(location: location, serial: nil)
                } catch {}
            }
        }

        Log.scanning.notice("Done scanning ipv4 range")
    }

    private func internalScanSSDPContinually() async throws {
        let runningInScreenshotTests = inScreenshotTestingContext()
        if runningInScreenshotTests {
            Log.scanning.notice("Skipping SSDP scan runningInScreenshotTests=\(runningInScreenshotTests, privacy: .public)")
            return
        }
        Log.scanning.notice("Starting internal SSDP scan")
        let ifaces = await allAddressedInterfaces()
        let scannableInterfaces = ifaces.filter { $0.isIPv4 }.map(\.name)
        let unscannableInterfaces = ifaces.filter { !$0.isIPv4 }.map(\.name)

        Log.scanning.notice("Scanning SSDP \(scannableInterfaces, privacy: .public), but ignoring \(unscannableInterfaces, privacy: .public)")
        if scannableInterfaces.isEmpty {
            Log.scanning.warning("No scannable IPv4 interfaces available for SSDP")
        }
        try await withThrowingDiscardingTaskGroup { outerTaskGroup in
            for interface in scannableInterfaces {
                outerTaskGroup.addTask {
                    Log.scanning.notice("Starting SSDP stream consumer for interface \(interface, privacy: .public)")
                    do {
                        try await scanDevicesContinually(interface: interface) { device in
                            Log.scanning.notice("Found SSDP service at \(device.location ?? "--", privacy: .public)")
                            if let location = device.location {
                                let serial = device.uniqueServiceName?.stripPrefix("uuid:").stripPrefix("roku:ecp:")
                                do {
                                    try await self.addDevice(location: location, serial: serial)
                                } catch {}
                            }
                        }
                    } catch {
                        Log.scanning.error("Error in SSDP stream for interface \(interface, privacy: .public): \(error, privacy: .public)")
                        throw error
                    }
                }
            }
        }
    }

    private func scanSSDPContinuallyBackoff() async {
        Log.scanning.notice("Starting SSDP continual scan backoff loop taskIsCancelled=\(Task.isCancelled, privacy: .public)")
        for await _ in exponentialBackoff(min: 2, max: 30) {
            if Task.isCancelled {
                Log.scanning.notice("SSDP continual scan backoff loop cancelled")
                return
            }
            do {
                Log.scanning.notice("Starting SSDP scan attempt from backoff loop")
                try await self.internalScanSSDPContinually()
                Log.scanning.notice("SSDP internal scan returned without error")
            } catch {
                Log.scanning.warning("Restarting ssdp scan due to error \(error, privacy: .public)")
            }
        }
        Log.scanning.notice("SSDP continual scan backoff stream ended taskIsCancelled=\(Task.isCancelled, privacy: .public)")
    }

    func scanSSDPOnce(duration: TimeInterval = 6) async {
        Log.scanning.notice("Starting one-shot SSDP scan with duration \(duration, privacy: .public)")
        do {
            try await withTimeout(delay: duration, priority: .background) {
                try await self.internalScanSSDPContinually()
            }
            Log.scanning.notice("One-shot SSDP scan returned before timeout")
        } catch is TimeoutError {
            Log.scanning.notice("One-shot SSDP scan completed after \(duration, privacy: .public)s timeout")
        } catch is CancellationError {
            Log.scanning.notice("One-shot SSDP scan cancelled")
        } catch {
            Log.scanning.warning("One-shot SSDP scan failed with error \(error, privacy: .public)")
        }
    }

    func scanSSDPContinually() async {
        Log.scanning.notice("Starting scanSSDPContinually")
        let queue = DispatchQueue.networkQueue

        let pathStream: AsyncStream<[NWInterface]> = AsyncStream<[NWInterface]> { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                let interfaceNames = path.availableInterfaces.map(\.name)
                let discoveryInterfaceNames = discoveryNWInterfaceNames(path.availableInterfaces)
                Log.scanning.notice(
                    "SSDP NWPathMonitor update status=\(String(describing: path.status), privacy: .public) interfaces=\(interfaceNames, privacy: .public) discoveryInterfaces=\(discoveryInterfaceNames, privacy: .public)"
                )
                DispatchQueue.main.async {
                    continuation.yield(
                        path.availableInterfaces
                    )
                }
            }
            monitor.start(queue: queue)
            continuation.onTermination = { @Sendable _ in
                Log.scanning.notice("Terminating SSDP NWPathMonitor stream")
                monitor.cancel()
          }
        }
        var scanTask: Task<Void, Never>?
        var previousDiscoveryInterfaceNames: [String]?
        defer {
            Log.scanning.notice("Cancelling current SSDP scan task while scanSSDPContinually exits")
            scanTask?.cancel()
        }

        for await paths in pathStream {
            let interfaceNames = paths.map(\.name)
            let discoveryInterfaceNames = discoveryNWInterfaceNames(paths)
            Log.scanning.notice(
                "SSDP paths changed to \(interfaceNames, privacy: .public), discovery paths \(discoveryInterfaceNames, privacy: .public), evaluating restart"
            )
            if previousDiscoveryInterfaceNames == discoveryInterfaceNames {
                Log.scanning.notice("Skipping SSDP restart because discovery interface set did not change")
                continue
            }
            previousDiscoveryInterfaceNames = discoveryInterfaceNames
            if let scanTask {
                Log.scanning.notice("Cancelling previous SSDP continual scan task before restart")
                scanTask.cancel()
            }
            if Task.isCancelled {
                Log.scanning.notice("scanSSDPContinually cancelled before restarting scan")
                return
            }

            scanTask = Task(priority: .background) {
                Log.scanning.notice(
                    "Launching SSDP continual scan task for path update taskIsCancelled=\(Task.isCancelled, privacy: .public)"
                )
                await self.scanSSDPContinuallyBackoff()
                Log.scanning.notice(
                    "SSDP continual scan task returned taskIsCancelled=\(Task.isCancelled, privacy: .public)"
                )
            }
        }
        Log.scanning.notice("SSDP path stream ended")
        Log.scanning.notice("scanSSDPContinually ended")
    }
    #endif
}

#if !os(watchOS)
private func discoveryNWInterfaceNames(_ interfaces: [NWInterface]) -> [String] {
    Array(Set(interfaces.map(\.name).filter { !isUnsupportedDiscoveryInterfaceName($0) })).sorted()
}

private func scanAddress(_ address: (Addressed4NetworkInterface, IP4Address)) async -> String? {
    let (iface, ipAddress) = address
    if Task.isCancelled {
        return nil
    }

    let location = "http://\(ipAddress.addressString):8060/"
    Log.scanning.debug("Scanning address \(ipAddress.addressString, privacy: .public)")

    if await !canConnectTCP(location: location, timeout: 1.2, interface: iface.nwInterface) {
        // This device is a potential item
        return nil
    }
    return location
}
#endif
