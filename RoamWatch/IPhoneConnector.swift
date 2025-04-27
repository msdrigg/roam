import os.log
import WatchConnectivity

final class WatchConnectivity: NSObject, WCSessionDelegate, Sendable {
    static let shared = WatchConnectivity()

    override init() {
        super.init()

        if WCSession.isSupported() {
            Log.watch.notice("Activating watchOS WC Receiver")
            let session = WCSession.default
            session.delegate = self
            session.activate()
        } else {
            Log.watch.notice("Cannot activate WC receiver because not supported")
        }
    }

    func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Log.watch.notice("Got application context from iphone \(applicationContext, privacy: .public)")
        handleAddDevices(applicationContext)
    }

    func session(
        _: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Log.watch.notice("Got message from iphone \(message, privacy: .public)")
        handleAddDevices(message)

        replyHandler([:])
    }

    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Log.watch.notice("Got user info from iphone \(userInfo, privacy: .public)")
        handleAddDevices(userInfo)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Log.watch.notice("WCSession reachablilty changed from watchOS to: \(session.isReachable, privacy: .public)")
        // Send message to iphone
        session.sendMessage(["message": "please send devices"], replyHandler: { reply in
            self.handleAddDevices(reply)
        }, errorHandler: { error in
            Log.watch.notice("Tried to send from watch with error \(error, privacy: .public)")
        })
    }

    func handleAddDevices(_ devices: [String: Any]) {
        if let deviceMap = devices as? [String: [String: String]] {
            Log.watch.notice("Trying to add devices \(deviceMap, privacy: .public)")
            Task {
                let modelContainer = await getSharedModelContainer()
                let dataHandler = DataHandler(modelContainer: modelContainer)
                for device in deviceMap {
                    if let existingDevice = await dataHandler.deviceEntityForUdn(udn: device.key) {
                        Log.watch
                            .notice("Device aleady exists, only updating name, location \(device.key, privacy: .public)")
                        if let location = device.value["location"] {
                            let name = device.value["name"] ?? existingDevice.name
                            let hiddenAtIso8601 = device.value["hiddenAt"]
                            let hiddenAt = hiddenAtIso8601.flatMap {
                                let formatter = ISO8601DateFormatter()
                                return formatter.date(from: $0)
                            }
                            await dataHandler.updateDevice(
                                existingDevice.modelId,
                                name: name,
                                location: location,
                                hidden: hiddenAt != nil
                            )
                        }
                        continue
                    }
                    if let location = device.value["location"], let udn = device.value["udn"], let serial = device.value["serial"] {
                        let hiddenAtIso8601 = device.value["hiddenAt"]
                        let hiddenAt = hiddenAtIso8601.flatMap {
                            let formatter = ISO8601DateFormatter()
                            return formatter.date(from: $0)
                        }
                        let name = device.value["name"] ?? getGlobalNewDeviceName()
                        await dataHandler.addDeviceIndistriminantly(
                            location: location,
                            friendlyDeviceName: name,
                            udn: udn,
                            serial: serial,
                            hidden: hiddenAt != nil
                        )
                    }
                }
            }
        } else {
            Log.watch
                .warning("Error parsing devices as [String: [String: String]]: \(String(describing: devices))")
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error: (any Error)?) {
        if let error {
            Log.watch.notice("WCSession activated from watchOS with error \(error, privacy: .public)")
        } else {
            Log.watch.notice("WCSession activated from watchOS successfully!")
        }
        // Send message to iphone
        session.sendMessage(["message": "please send devices"], replyHandler: { reply in
            self.handleAddDevices(reply)
        }, errorHandler: { error in
            Log.watch.notice("Tried to send from watch with error \(error, privacy: .public)")
        })
    }
}
