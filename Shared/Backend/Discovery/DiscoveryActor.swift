import Foundation
import Network
import os
import SwiftData
import SwiftUI
import XMLCoder

actor DeviceDiscoveryActor {
    let dataHandler: DataHandler
    let updater: @Sendable @MainActor () -> Void

    init(modelContainer: ModelContainer, updater: @Sendable @MainActor @escaping () -> Void) {
        dataHandler = DataHandler(modelContainer: modelContainer)
        self.updater = updater
    }

    #if !os(watchOS)
    @discardableResult
    func addDevice(location: String, serial: String?) async -> Bool {
        guard URL(string: location) != nil else {
            Log.scanning.error("Not adding device with location \(location, privacy: .public) b/c it's not a valid url")
            return false
        }
        Log.scanning.notice("Trying to add device with location \(location, privacy: .public)")

        if await dataHandler.addOrReplaceDevice(location: location, serial: serial) != nil {
            Log.scanning.notice("Saved new device \(location, privacy: .public), \(location, privacy: .public)")
            return true
        } else {
            return false
        }
    }

    func scanIPV4Once() async {
        // Don't scan IPV4 in previews
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || inScreenshotTestingContext() {
            return
        }

        Log.scanning.notice("Starting to scan ipv4 range")

        let maxConcurrentScanned = 37

        let ifaces = await  allAddressedInterfaces()
        let scannableInterfaces = ifaces.filter { $0.isIPv4 }
        let unscannableInterfaces = ifaces.filter { !$0.isIPv4 }.map(\.name)
        let scannableIfaceNames = scannableInterfaces.map(\.name)

        Log.scanning.notice("Scanning IPV4 interfaces \(scannableIfaceNames, privacy: .public), but ignoring \(unscannableInterfaces, privacy: .public)")

        let sem = AsyncSemaphore(value: maxConcurrentScanned)

        await withDiscardingTaskGroup { taskGroup in
            for iface in scannableInterfaces {
                let range = iface.scannableIPV4NetworkRange
                if range.count > 1024 {
                    Log.scanning.error("IPV4 range for \(iface.name, privacy: .public) has \(range.count, privacy: .public) items. Max is 1024")
                } else {
                    Log.scanning.notice("Manually scanning \(range.count, privacy: .public) devices in network range \(range, privacy: .public) with name \(iface.name, privacy: .public)")
                }
                var idx = 0

                for ipAddress in range {
                    idx += 1
                    if Task.isCancelled {
                        break
                    }
                    taskGroup.addTask {
                        try? await sem.waitUnlessCancelled()
                        defer {
                            sem.signal()
                        }
                        if Task.isCancelled {
                            return
                        }

                        let location = "http://\(ipAddress.addressString):8060/"
                        Log.scanning.debug("Scanning address \(ipAddress.addressString, privacy: .public)")

                        if await !canConnectTCP(location: location, timeout: 1.2, interface: iface.nwInterface) {
                            // This device is a potential item
                            return
                        }
                        if Task.isCancelled {
                            return
                        }

                        await self.addDevice(location: location, serial: nil)
                    }

                    if idx > 1024 {
                        break
                    }
                }
            }
        }
        Log.scanning.notice("Done scanning ipv4 range")
    }

    private func internalScanSSDPContinually() async throws {
        if inScreenshotTestingContext() {
            return
        }
        let ifaces = await allAddressedInterfaces()
        let scannableInterfaces = ifaces.filter { $0.isIPv4 }.map(\.name)
        let unscannableInterfaces = ifaces.filter { !$0.isIPv4 }.map(\.name)

        Log.scanning.notice("Scanning SSDP \(scannableInterfaces, privacy: .public), but ignoring \(unscannableInterfaces, privacy: .public)")
        var streams: [AsyncThrowingStream<SSDPService, any Error>] = []
        for interface in scannableInterfaces {
            do {
                streams.append(try scanDevicesContinually(interface: interface))
            } catch {
                Log.scanning.error("Error getting async device stream \(error, privacy: .public)")
                return
            }
        }

        try await withThrowingDiscardingTaskGroup { outerTaskGroup in
            for stream in streams {
                outerTaskGroup.addTask {
                    try await withThrowingDiscardingTaskGroup { taskGroup in
                        do {
                            for try await device in stream {
                                Log.scanning.notice("Found SSDP service at \(device.location ?? "--", privacy: .public)")
                                if let location = device.location {
                                    taskGroup.addTask {
                                        await self.addDevice(location: location, serial: device.uniqueServiceName?.stripPrefix("uuid:").stripPrefix("roku:ecp:"))
                                    }
                                }
                            }
                        } catch {
                            Log.scanning.error("Error in SSDP stream \(error, privacy: .public)")
                            throw error
                        }
                    }
                }
            }
        }
    }

    private func scanSSDPContinuallyBackoff() async {
        for await _ in exponentialBackoff(min: 2, max: 30) {
            if Task.isCancelled {
                return
            }
            do {
                try await self.internalScanSSDPContinually()
            } catch {
                Log.scanning.warning("Restarting ssdp scan due to error \(error, privacy: .public)")
            }
        }
    }

    func scanSSDPContinually() async {
        let queue = DispatchQueue(label: "NetworkMonitor")

        let pathStream: AsyncStream<[NWInterface]> = AsyncStream<[NWInterface]> { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                DispatchQueue.main.async {
                    continuation.yield(
                        path.availableInterfaces
                    )
                }
            }
            monitor.start(queue: queue)
            continuation.onTermination = { @Sendable _ in
                monitor.cancel()
          }
        }
        await withDiscardingTaskGroup { taskGroup in
            for await paths in pathStream {
                Log.scanning.notice("Paths changed to \(paths, privacy: .public), restarting scanning")
                taskGroup.cancelAll()
                if Task.isCancelled {
                    return
                }
                taskGroup.addTask {
                    await self.scanSSDPContinuallyBackoff()
                }
            }
        }
    }
    #endif
}
