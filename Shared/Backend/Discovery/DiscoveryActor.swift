import Foundation
import Network
import os
import SwiftData
import SwiftUI
import XMLCoder

actor DeviceDiscoveryActor {
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DeviceDiscoveryActor.self)
    )

    let dataHandler: DataHandler

    init(modelContainer: ModelContainer) {
        dataHandler = DataHandler(modelContainer: modelContainer)
    }

    func refreshDevice(id: PersistentIdentifier) async {
        await dataHandler.refreshDevice(id)
    }

    @discardableResult
    func addDevice(location: String) async -> Bool {
        guard let deviceInfo = await fetchDeviceInfo(location: location) else {
            Self.logger.error("Error getting device info for found device \(location)")
            return false
        }

        if let device = await dataHandler.deviceEntityForUdn(udn: deviceInfo.udn) {
            if device.location == location {
                return false
            }
        }

        if let pid = await dataHandler.addOrReplaceDevice(
            location: location,
            friendlyDeviceName: deviceInfo.friendlyDeviceName ?? "New device",
            udn: deviceInfo.udn
        ) {
            Self.logger.info("Saved new device \(deviceInfo.udn), \(location)")
            await refreshDevice(id: pid)
            return true
        } else {
            return false
        }
    }

    func refreshSelectedDeviceContinually(id: PersistentIdentifier) async {
        // Refresh every 30 seconds
        Self.logger.debug("Refreshing device \(String(describing: id))")
        await refreshDevice(id: id)
        for await _ in interval(time: 30) {
            if Task.isCancelled {
                return
            }
            Self.logger.debug("Refreshing device \(String(describing: id))")
            await refreshDevice(id: id)
        }
    }

    #if !os(watchOS)
        func scanIPV4Once() async {
            // Don't scan IPV4 in previews
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                return
            }

            Self.logger.info("Starting to scan ipv4 range")

            let maxConcurrentScanned = 37

            let scannableInterfaces = await allAddressedInterfaces().filter { $0.isIPV4 && $0.isEthernetLike }
            let sem = AsyncSemaphore(value: maxConcurrentScanned)

            await withDiscardingTaskGroup { taskGroup in
                for iface in scannableInterfaces {
                    let range = iface.scannableIPV4NetworkRange
                    if range.count > 1024 {
                        Self.logger.error("IPV4 range has \(range.count) items. Max is 1024")
                    } else {
                        Self.logger.debug("Manually scanning \(range.count) devices in network range \(range)")
                    }
                    var idx = 0

                    for ipAddress in range {
                        idx += 1
                        if Task.isCancelled {
                            break
                        }
                        taskGroup.addTask {
                            try? await sem.waitUnlessCancelled()
                            if Task.isCancelled {
                                return
                            }
                            defer {
                                sem.signal()
                            }

                            let location = "http://\(ipAddress.addressString):8060/"
                            Self.logger.trace("Scanning address \(ipAddress.addressString)")

                            if await !canConnectTCP(location: location, timeout: 1.2, interface: iface.nwInterface) {
                                // This device is a potential item
                                return
                            }
                            if Task.isCancelled {
                                return
                            }

                            await self.addDevice(location: location)
                        }

                        if idx > 1024 {
                            break
                        }
                    }
                }
            }
            Self.logger.info("Done scanning ipv4 range")
        }

        func scanSSDPContinually() async {
            let stream: AsyncThrowingStream<SSDPService, any Error>
            do {
                stream = try scanDevicesContinually()
            } catch {
                Self.logger.error("Error getting async device stream \(error)")
                return
            }

            await withDiscardingTaskGroup { taskGroup in
                do {
                    for try await device in stream {
                        Self.logger.info("Found SSDP service at \(device.location ?? "--")")
                        if let location = device.location {
                            taskGroup.addTask {
                                await self.addDevice(location: location)
                            }
                        }
                    }
                } catch {
                    Self.logger.error("Error in SSDP stream \(error)")
                }
            }
        }
    #endif
}
