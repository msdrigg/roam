import os.log
import WatchConnectivity

final class WatchConnectivity: NSObject, WCSessionDelegate, Sendable {
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: WatchConnectivity.self)
    )

    static let shared = WatchConnectivity()

    override init() {
        super.init()

        if WCSession.isSupported() {
            WatchConnectivity.logger.info("Activating watchOS WC Receiver")
            let session = WCSession.default
            session.delegate = self
            session.activate()
        } else {
            WatchConnectivity.logger.info("Cannot activate WC receiver because not supported")
        }
    }

    func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        WatchConnectivity.logger.info("Got application context from iphone \(applicationContext)")
        handleAddDevices(applicationContext)
    }

    func session(
        _: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        WatchConnectivity.logger.info("Got message from iphone \(message)")
        handleAddDevices(message)

        replyHandler([:])
    }

    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        WatchConnectivity.logger.info("Got user info from iphone \(userInfo)")
        handleAddDevices(userInfo)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        WatchConnectivity.logger.info("WCSession reachablilty changed from watchOS to: \(session.isReachable)")
        // Send message to iphone
        session.sendMessage(["message": "please send devices"], replyHandler: { reply in
            self.handleAddDevices(reply)
        }, errorHandler: { error in
            WatchConnectivity.logger.info("Tried to send from watch with error \(error)")
        })
    }

    func handleAddDevices(_ devices: [String: Any]) {
        if let deviceMap = devices as? [String: [String: String]] {
            WatchConnectivity.logger.info("Trying to add devices \(deviceMap)")
            Task {
                let modelContainer = getSharedModelContainer()
                let dataHandler = DataHandler(modelContainer: modelContainer)
                for device in deviceMap {
                    if let existingDevice = await dataHandler.deviceEntityForUdn(udn: device.key) {
                        WatchConnectivity.logger
                            .info("Device aleady exists, only updating name, location \(device.key)")
                        if let location = device.value["location"] {
                            let name = device.value["name"] ?? existingDevice.name
                            await dataHandler.updateDevice(
                                existingDevice.modelId,
                                name: name,
                                location: location,
                                udn: existingDevice.udn
                            )
                            await dataHandler.refreshDevice(existingDevice.modelId)
                        }
                        continue
                    }
                    if let location = device.value["location"] {
                        let name = device.value["name"] ?? "New device"
                        if let pid = await dataHandler.addOrReplaceDevice(
                            location: location,
                            friendlyDeviceName: name,
                            udn: device.key
                        ) {
                            await dataHandler.refreshDevice(pid)
                        }
                    }
                }
            }
        } else {
            WatchConnectivity.logger
                .warning("Error parsing devices as [String: [String: String]]: \(String(describing: devices))")
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error: (any Error)?) {
        if let error {
            WatchConnectivity.logger.info("WCSession activated from watchOS with error \(error)")
        } else {
            WatchConnectivity.logger.info("WCSession activated from watchOS successfully!")
        }
        // Send message to iphone
        session.sendMessage(["message": "please send devices"], replyHandler: { reply in
            self.handleAddDevices(reply)
        }, errorHandler: { error in
            WatchConnectivity.logger.info("Tried to send from watch with error \(error)")
        })
    }
}
