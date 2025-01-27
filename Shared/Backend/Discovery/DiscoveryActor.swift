import Foundation
import Network
import os
import SwiftData
import SwiftUI
import XMLCoder

actor DeviceDiscoveryActor {
    private nonisolated static let logger = Logger(
        subsystem: getLogSubsystem(),
        category: String(describing: DeviceDiscoveryActor.self)
    )

    let dataHandler: DataHandler
    let updater: @Sendable @MainActor () -> Void

    init(modelContainer: ModelContainer, updater: @Sendable @MainActor @escaping () -> Void) {
        dataHandler = DataHandler(modelContainer: modelContainer)
        self.updater = updater
    }

    func refreshDevice(id: PersistentIdentifier) async {
        await dataHandler.refreshDevice(id)
        let updater = updater
        await MainActor.run {
            updater()
        }
    }
    func refreshSelectedDeviceContinually(id: PersistentIdentifier) async {
        // Refresh every 20 minutes
        do {
            try await Task.sleep(duration: 1)
            Self.logger.info("Refreshing device initially \(String(describing: id), privacy: .public)")
            await refreshDevice(id: id)
        } catch {}
        for await _ in interval(time: 1200) {
            if Task.isCancelled {
                return
            }
            Self.logger.info("Refreshing device \(String(describing: id), privacy: .public)")
            await refreshDevice(id: id)
        }
    }

    #if !os(watchOS)
    @discardableResult
    func addDevice(location: String) async -> Bool {
        Self.logger.notice("Trying to add device with location \(location, privacy: .public)")
        var deviceInfo: DeviceInfo?
        do {
            guard let url = URL(string: location) else {
                return false
            }
            deviceInfo = try await ECPWebsocketClient(location: url).oneOff { session in
                return try await session.getDeviceInfo()
            }
        } catch {
            Self.logger.error("Error creating ECPSession getting device info: \(error, privacy: .public)")
            return false
        }

        guard let deviceInfo else {
            Self.logger.error("Error getting device info for found device \(location, privacy: .public)")
            return false
        }
        Self.logger.notice("Got device info to add device with location \(location, privacy: .public)")

        if let device = await dataHandler.deviceEntityForUdn(udn: deviceInfo.udn) {
            if device.location == location {
                return false
            }
        }

        if let pid = await dataHandler.addOrReplaceDevice(
            location: location,
            friendlyDeviceName: deviceInfo.friendlyDeviceName ?? getGlobalNewDeviceName(),
            udn: deviceInfo.udn
        ) {
            Self.logger.notice("Saved new device \(deviceInfo.udn, privacy: .public), \(location, privacy: .public)")
            await refreshDevice(id: pid)
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

        Self.logger.notice("Starting to scan ipv4 range")

        let maxConcurrentScanned = 37

        let ifaces = await  allAddressedInterfaces()
        let scannableInterfaces = ifaces.filter { $0.isIPv4 }
        let unscannableInterfaces = ifaces.filter { !$0.isIPv4 }.map(\.name)
        let scannableIfaceNames = scannableInterfaces.map(\.name)

        Self.logger.notice("Scanning IPV4 interfaces \(scannableIfaceNames, privacy: .public), but ignoring \(unscannableInterfaces, privacy: .public)")

        let sem = AsyncSemaphore(value: maxConcurrentScanned)

        await withDiscardingTaskGroup { taskGroup in
            for iface in scannableInterfaces {
                let range = iface.scannableIPV4NetworkRange
                if range.count > 1024 {
                    Self.logger.error("IPV4 range for \(iface.name, privacy: .public) has \(range.count, privacy: .public) items. Max is 1024")
                } else {
                    Self.logger.info("Manually scanning \(range.count, privacy: .public) devices in network range \(range, privacy: .public) with name \(iface.name, privacy: .public)")
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
                        Self.logger.debug("Scanning address \(ipAddress.addressString, privacy: .public)")

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
        Self.logger.notice("Done scanning ipv4 range")
    }

    func _scanSSDPContinuallyWithRestart() async throws {
        if inScreenshotTestingContext() {
            return
        }
        let ifaces = await  allAddressedInterfaces()
        let scannableInterfaces = ifaces.filter { $0.isIPv4 }.map(\.name)
        let unscannableInterfaces = ifaces.filter { !$0.isIPv4 }.map(\.name)

        Self.logger.notice("Scanning SSDP \(scannableInterfaces, privacy: .public), but ignoring \(unscannableInterfaces, privacy: .public)")
        var streams: [AsyncThrowingStream<SSDPService, any Error>] = []
        for interface in scannableInterfaces {
            do {
                streams.append(try scanDevicesContinually(interface: interface))
            } catch {
                Self.logger.error("Error getting async device stream \(error, privacy: .public)")
                return
            }
        }

        try await withThrowingDiscardingTaskGroup { outerTaskGroup in
            for stream in streams {
                outerTaskGroup.addTask {
                    try await withThrowingDiscardingTaskGroup { taskGroup in
                        do {
                            for try await device in stream {
                                Self.logger.notice("Found SSDP service at \(device.location ?? "--", privacy: .public)")
                                if let location = device.location {
                                    taskGroup.addTask {
                                        await self.addDevice(location: location)
                                    }
                                }
                            }
                        } catch {
                            Self.logger.error("Error in SSDP stream \(error, privacy: .public)")
                            throw error
                        }
                    }
                }
            }
        }
    }

    func scanSSDPContinually() async {
        for await _ in exponentialBackoff(min: 2, max: 30) {
            if Task.isCancelled {
                return
            }
            do {
                try await self._scanSSDPContinuallyWithRestart()
            } catch {
                Self.logger.warning("Restarting ssdp scan due to error \(error, privacy: .public)")
            }
        }
    }
    #endif
}
