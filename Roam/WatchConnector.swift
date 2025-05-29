#if os(iOS)
    import os.log
    import SwiftData
    @preconcurrency import WatchConnectivity

    final class WatchConnectivity: NSObject, WCSessionDelegate, Sendable {
        static let shared = WatchConnectivity()
        override init() {
            super.init()

            if WCSession.isSupported() {
                Log.watch.notice("Activating iOS WC Sender")
                let session = WCSession.default
                session.delegate = self
                session.activate()
            } else {
                Log.watch.notice("Cannot activate WC receiver because not supported")
            }
        }

        func sessionReachabilityDidChange(_ session: WCSession) {
            Log.watch.notice("WCSession reachability changed to \(session.isReachable, privacy: .public)")
            if session.isReachable {
                Task {
                    do {
                        let devices = try await RoamDataHandler.checkedCreate().allDeviceEntities()
                        DispatchQueue.main.async {
                            self.transferDevices(session, devices: devices)
                        }
                    } catch {
                        Log.watch.error("Error refreshing devices on session active: \(error, privacy: .public)")
                    }
                }
            }
        }

        func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
            Log.watch.notice("WCSession got message from watch to \(message, privacy: .public). Sending devices")
            DispatchQueue.main.async {
                Task {
                    do {
                        let devices = try await RoamDataHandler.checkedCreate().allDeviceEntities()
                        DispatchQueue.main.async {
                            self.transferDevices(session, devices: devices)
                        }
                    } catch {
                        Log.watch.error("Error refreshing devices on session active: \(error, privacy: .public)")
                    }
                }
            }
        }

        @MainActor
        func transferDevices(_ session: WCSession, devices: [DeviceAppEntity]) {
            let tuple = "\(session.activationState == .activated)-\(session.isPaired)-\(session.isWatchAppInstalled)-\(session.isReachable)"
            Log.watch
                .notice("WCSession with activated-paired-installed-reachable \(tuple, privacy: .public) trying to send devices \(devices.map(\.name), privacy: .public)")
            if session.activationState == .activated && session.isPaired && session.isWatchAppInstalled {
                if devices.count == 0 {
                    Log.watch.notice("Not transfering devices because devices is empty")
                    return
                }
                var deviceMap: [String: [String: String]] = [:]
                var transferingDevicesBuilder: [PersistentIdentifier] = []
                let sendTimeout = Date(timeIntervalSinceNow: 60 * 60 * 24 * 7)
                for device in devices.filter({ $0.lastSentToWatch ?? Date.distantPast < sendTimeout }) {
                    var map = ["location": device.location, "name": device.name]
                    if let hiddenAt = device.hiddenAt?.ISO8601Format() {
                        map["hiddenAt"] = hiddenAt
                    }
                    deviceMap[device.id] = map

                    transferingDevicesBuilder.append(device.modelId)
                }
                let transferingDevices = transferingDevicesBuilder
                let completeDeviceMap = deviceMap
                if completeDeviceMap.isEmpty {
                    Log.watch.notice("Not sending because all devices have been sent in the past day")
                    return
                }
                Log.watch.notice("Transferring devices \(devices.map(\.name), privacy: .public) to watch")
                if session.outstandingUserInfoTransfers.count > 0 {
                    Log.watch.notice("Cancelling ongoing transfer because we are creating a new one")
                    session.outstandingUserInfoTransfers.last?.cancel()
                }
                do {
                    try session.updateApplicationContext(completeDeviceMap)
                } catch {
                    Log.watch.error("Error transfering app context \(completeDeviceMap, privacy: .public)")
                }

                session.sendMessage(completeDeviceMap, replyHandler: { @Sendable reply in
                    Task {
                        guard let dataHandler = try? await RoamDataHandler.checkedCreate() else {
                            return
                        }
                        for device in transferingDevices {
                            await dataHandler.sentToWatch(deviceId: device)
                        }
                    }
                    Log.watch.notice("Successfully sent devices to watch with reply \(reply, privacy: .public)")
                }, errorHandler: { @Sendable error in
                    Log.watch.error("Error sending message \(completeDeviceMap, privacy: .public). \(error, privacy: .public)")
                })

                session.transferUserInfo(deviceMap)
            } else {
                Log.watch
                    .notice("Not transfering devices activation state not activated-paired-installed \(tuple)")
            }
        }

        func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error: (any Error)?) {
            if let error {
                Log.watch.error("WCSession activated with error: \(error, privacy: .public)")
                Task {
                    try? await RoamDataHandler.checkedCreate().watchPossiblyDead()
                }
            } else {
                Log.watch.notice("WCSession activated no error")
                Task {
                    do {
                        let devices = try await RoamDataHandler.checkedCreate().allDeviceEntities()

                        DispatchQueue.main.async {
                            self.transferDevices(session, devices: devices)
                        }
                    } catch {
                        Log.watch.error("Error refreshing devices on session active: \(error, privacy: .public)")
                    }
                }
            }
        }

        func sessionDidBecomeInactive(_: WCSession) {
            Log.watch.notice("WatchConnectivity session became inactive")

            Task {
                try? await RoamDataHandler.checkedCreate().watchPossiblyDead()
            }
        }

        func sessionDidDeactivate(_: WCSession) {
            Log.watch.notice("WatchConnectivity session deactivated")

            Task {
                try? await RoamDataHandler.checkedCreate().watchPossiblyDead()
            }
        }
    }
#endif
