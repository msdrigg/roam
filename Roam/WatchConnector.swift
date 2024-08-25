#if os(iOS)
    import os.log
    import SwiftData
    @preconcurrency import WatchConnectivity

    final class WatchConnectivity: NSObject, WCSessionDelegate, Sendable {
        private static nonisolated let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!,
            category: String(describing: WatchConnectivity.self)
        )

        static let shared = WatchConnectivity()
        override init() {
            super.init()

            if WCSession.isSupported() {
                WatchConnectivity.logger.info("Activating iOS WC Sender")
                let session = WCSession.default
                session.delegate = self
                session.activate()
            } else {
                WatchConnectivity.logger.info("Cannot activate WC receiver because not supported")
            }
        }

        func sessionReachabilityDidChange(_ session: WCSession) {
            WatchConnectivity.logger.info("WCSession reachability changed to \(session.isReachable)")
            if session.isReachable {
                Task {
                    do {
                        let container = getSharedModelContainer()
                        let devices = try await DataHandler(modelContainer: container).allDeviceEntities()
                        self.transferDevices(session, devices: devices)
                    } catch {
                        WatchConnectivity.logger.error("Error refreshing devices on session active: \(error)")
                    }
                }
            }
        }

        func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
            WatchConnectivity.logger.info("WCSession got message from watch to \(message). Sending devices")
            Task {
                do {
                    let container = getSharedModelContainer()
                    let devices = try await DataHandler(modelContainer: container).allDeviceEntities()
                    DispatchQueue.main.async {
                        self.transferDevices(session, devices: devices)
                    }
                } catch {
                    WatchConnectivity.logger.error("Error refreshing devices on session active: \(error)")
                }
            }
        }

        func transferDevices(_ session: WCSession, devices: [DeviceAppEntity]) {
            WatchConnectivity.logger
                .info("WCSession with activationState \(session.activationState.rawValue) trying to send devices \(devices)")
            if session.activationState == .activated {
                if devices.count == 0 {
                    WatchConnectivity.logger.info("Not transfering devices because devices is empty")
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
                    WatchConnectivity.logger.info("Not sending because all devices have been sent in the past day")
                    return
                }
                Self.logger.info("Transferring devices \(String(describing: devices)) to watch")
                WatchConnectivity.logger.info("Transfering devices \(deviceMap)")
                if session.outstandingUserInfoTransfers.count > 0 {
                    WatchConnectivity.logger.info("Cancelling ongoing transfer because we are creating a new one")
                    session.outstandingUserInfoTransfers.last?.cancel()
                }
                do {
                    try session.updateApplicationContext(deviceMap)
                } catch {
                    WatchConnectivity.logger.error("Error transfering app context \(deviceMap)")
                }

                session.sendMessage(deviceMap, replyHandler: { reply in
                    Task.detached {
                        let dataHandler = DataHandler(modelContainer: getSharedModelContainer())
                        for device in transferingDevices {
                            await dataHandler.sentToWatch(deviceId: device)
                        }
                    }
                    WatchConnectivity.logger.info("Successfully sent devices to watch with reply \(reply)")
                }, errorHandler: { error in
                    WatchConnectivity.logger.error("Error sending message \(deviceMap). \(error)")
                })

                session.transferUserInfo(deviceMap)
            } else {
                WatchConnectivity.logger
                    .info("Not transfering devices activation state not activated: \(session.activationState.rawValue)")
            }
        }

        func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error: (any Error)?) {
            if let error {
                WatchConnectivity.logger.error("WCSession activated with error: \(error)")
                Task {
                    await DataHandler(modelContainer: getSharedModelContainer()).watchPossiblyDead()
                }
            } else {
                WatchConnectivity.logger.info("WCSession activated no error")
                Task {
                    do {
                        let container = getSharedModelContainer()
                        let devices = try await DataHandler(modelContainer: container).allDeviceEntities()

                        DispatchQueue.main.async {
                            self.transferDevices(session, devices: devices)
                        }
                    } catch {
                        WatchConnectivity.logger.error("Error refreshing devices on session active: \(error)")
                    }
                }
            }
        }

        func sessionDidBecomeInactive(_: WCSession) {
            WatchConnectivity.logger.info("WatchConnectivity session became inactive")

            Task {
                await DataHandler(modelContainer: getSharedModelContainer()).watchPossiblyDead()
            }
        }

        func sessionDidDeactivate(_: WCSession) {
            WatchConnectivity.logger.info("WatchConnectivity session deactivated")

            Task {
                await DataHandler(modelContainer: getSharedModelContainer()).watchPossiblyDead()
            }
        }
    }
#endif
