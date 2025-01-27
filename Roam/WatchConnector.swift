#if os(iOS)
    import os.log
    import SwiftData
    @preconcurrency import WatchConnectivity

    final class WatchConnectivity: NSObject, WCSessionDelegate, Sendable {
        private static nonisolated let logger = Logger(
            subsystem: getLogSubsystem(),
            category: String(describing: WatchConnectivity.self)
        )

        static let shared = WatchConnectivity()
        override init() {
            super.init()

            if WCSession.isSupported() {
                WatchConnectivity.logger.notice("Activating iOS WC Sender")
                let session = WCSession.default
                session.delegate = self
                session.activate()
            } else {
                WatchConnectivity.logger.notice("Cannot activate WC receiver because not supported")
            }
        }

        func sessionReachabilityDidChange(_ session: WCSession) {
            WatchConnectivity.logger.notice("WCSession reachability changed to \(session.isReachable, privacy: .public)")
            if session.isReachable {
                Task {
                    do {
                        let devices = try await DataHandler(modelContainer: getSharedModelContainer()).allDeviceEntities()
                        DispatchQueue.main.async {
                            self.transferDevices(session, devices: devices)
                        }
                    } catch {
                        WatchConnectivity.logger.error("Error refreshing devices on session active: \(error, privacy: .public)")
                    }
                }
            }
        }

        func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
            WatchConnectivity.logger.notice("WCSession got message from watch to \(message, privacy: .public). Sending devices")
            Task {
                do {
                    let devices = try await DataHandler(modelContainer: getSharedModelContainer()).allDeviceEntities()
                    DispatchQueue.main.async {
                        self.transferDevices(session, devices: devices)
                    }
                } catch {
                    WatchConnectivity.logger.error("Error refreshing devices on session active: \(error, privacy: .public)")
                }
            }
        }

        @MainActor
        func transferDevices(_ session: WCSession, devices: [DeviceAppEntity]) {
            let tuple = "\(session.activationState == .activated)-\(session.isPaired)-\(session.isWatchAppInstalled)-\(session.isReachable)"
            WatchConnectivity.logger
                .info("WCSession with activated-paired-installed-reachable \(tuple, privacy: .public) trying to send devices \(devices.map(\.name), privacy: .public)")
            if session.activationState == .activated && session.isPaired && session.isWatchAppInstalled {
                if devices.count == 0 {
                    WatchConnectivity.logger.notice("Not transfering devices because devices is empty")
                    return
                }
                var deviceMap: [String: [String: String]] = [:]
                var transferingDevicesBuilder: [PersistentIdentifier] = []
                let sendTimeout = Date(timeIntervalSinceNow: 60 * 60 * 24 * 7)
                for device in devices.filter({ $0.lastSentToWatch ?? Date.distantPast < sendTimeout }) {
                    deviceMap[device.id] = ["location": device.location, "name": device.name]
                    transferingDevicesBuilder.append(device.modelId)
                }
                let transferingDevices = transferingDevicesBuilder
                if deviceMap.isEmpty {
                    WatchConnectivity.logger.notice("Not sending because all devices have been sent in the past day")
                    return
                }
                Self.logger.notice("Transferring devices \(devices.map(\.name), privacy: .public) to watch")
                WatchConnectivity.logger.notice("Transfering devices \(deviceMap, privacy: .public)")
                if session.outstandingUserInfoTransfers.count > 0 {
                    WatchConnectivity.logger.notice("Cancelling ongoing transfer because we are creating a new one")
                    session.outstandingUserInfoTransfers.last?.cancel()
                }
                do {
                    try session.updateApplicationContext(deviceMap)
                } catch {
                    WatchConnectivity.logger.error("Error transfering app context \(deviceMap, privacy: .public)")
                }

                session.sendMessage(deviceMap, replyHandler: { reply in
                    Task.detached {
                        let dataHandler = await DataHandler(modelContainer: getSharedModelContainer())
                        for device in transferingDevices {
                            await dataHandler.sentToWatch(deviceId: device)
                        }
                    }
                    WatchConnectivity.logger.notice("Successfully sent devices to watch with reply \(reply, privacy: .public)")
                }, errorHandler: { error in
                    WatchConnectivity.logger.error("Error sending message \(deviceMap, privacy: .public). \(error, privacy: .public)")
                })

                session.transferUserInfo(deviceMap)
            } else {
                WatchConnectivity.logger
                    .info("Not transfering devices activation state not activated-paired-installed \(tuple)")
            }
        }

        func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error: (any Error)?) {
            if let error {
                WatchConnectivity.logger.error("WCSession activated with error: \(error, privacy: .public)")
                Task {
                    await DataHandler(modelContainer: getSharedModelContainer()).watchPossiblyDead()
                }
            } else {
                WatchConnectivity.logger.notice("WCSession activated no error")
                Task {
                    do {
                        let devices = try await DataHandler(modelContainer: getSharedModelContainer()).allDeviceEntities()

                        DispatchQueue.main.async {
                            self.transferDevices(session, devices: devices)
                        }
                    } catch {
                        WatchConnectivity.logger.error("Error refreshing devices on session active: \(error, privacy: .public)")
                    }
                }
            }
        }

        func sessionDidBecomeInactive(_: WCSession) {
            WatchConnectivity.logger.notice("WatchConnectivity session became inactive")

            Task {
                await DataHandler(modelContainer: getSharedModelContainer()).watchPossiblyDead()
            }
        }

        func sessionDidDeactivate(_: WCSession) {
            WatchConnectivity.logger.notice("WatchConnectivity session deactivated")

            Task {
                await DataHandler(modelContainer: getSharedModelContainer()).watchPossiblyDead()
            }
        }
    }
#endif
