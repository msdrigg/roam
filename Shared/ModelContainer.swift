import SwiftData
import OSLog

#if os(macOS)
let mainAppGroup = "2865NTZ7H3.com.msdrigg.roam.models"
let tipsAppGroup = "2865NTZ7H3.com.msdrigg.roam.tips"
let loadAppGroup = "2865NTZ7H3.com.msdrigg.roam.load"
let mainAppGroupBackup: String? = "group.com.msdrigg.roam.models"
#else
let mainAppGroup = "group.com.msdrigg.roam.models"
let tipsAppGroup = "group.com.msdrigg.roam.tips"
let loadAppGroup = "group.com.msdrigg.roam.load"
let mainAppGroupBackup: String? = nil
#endif

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "ModelContainer"
)

public class GlobalModelContainer {
    static let sharedModelContainer = demandSharedModelContainer()
}

public func getSharedModelContainer() -> ModelContainer {
    GlobalModelContainer.sharedModelContainer
}

private func demandSharedModelContainer() -> ModelContainer {
    do {
        return try _getSharedModelContainer()
    } catch {
        fatalError("Error getting shared model container \(error))")
    }
}

private func _getSharedModelContainer() throws -> ModelContainer {
    let schema = Schema(
        versionedSchema: SchemaV2.self
    )

//    if !UserDefaults.standard.bool(forKey: UserDefaultKeys.usingNewAppGroup) {
//        do {
//            if let mainAppGroupBackup {
//                let oldModelConfiguration = ModelConfiguration(
//                    schema: schema,
//                    isStoredInMemoryOnly: false,
//                    groupContainer: .identifier(mainAppGroupBackup)
//                )
//
//                let oldModelContainer = try ModelContainer(
//                    for: schema,
//                    migrationPlan: RoamSchemaMigrationPlan.self,
//                    configurations: [oldModelConfiguration]
//                )
//
//                let modelConfiguration = ModelConfiguration(
//                    schema: schema,
//                    isStoredInMemoryOnly: false,
//                    groupContainer: .identifier(mainAppGroup)
//                )
//
//                let newModelContainer = try ModelContainer(
//                    for: schema,
//                    migrationPlan: RoamSchemaMigrationPlan.self,
//                    configurations: [modelConfiguration]
//                )
//
//                DispatchQueue.main.async {
//                    logger.error("Starting backup process")
//                    let oldMainContext = oldModelContainer.mainContext
//                    let newMainContext = newModelContainer.mainContext
//                    do {
//                        let devices = try oldMainContext.fetch(Device.fetchAllRequest())
//                        let apps = try oldMainContext.fetch(AppLink.fetchAllRequest())
//                        let messages = try oldMainContext.fetch(Message.fetchAllRequest())
//
//                        for model in devices {
//                            let device = Device(name: model.name, location: model.location, udn: model.udn)
//                            device.supportsDatagram = model.supportsDatagram
//                            device.rtcpPort = model.rtcpPort
//                            device.deletedAt = model.deletedAt
//                            device.deviceIcon = model.deviceIcon
//                            device.ethernetMAC = model.ethernetMAC
//                            device.lastOnlineAt = model.lastOnlineAt
//                            device.lastSelectedAt = model.lastSelectedAt
//                            device.networkType = model.networkType
//                            device.powerMode = model.powerMode
//                            device.wifiMAC = model.wifiMAC
//                            newMainContext.insert(device)
//                        }
//                        for model in apps {
//                            let app = AppLink(id: model.id, type: model.type, name: model.name)
//                            app.deviceUid = model.deviceUid
//                            app.lastSelected = model.lastSelected
//                            app.icon = model.icon
//
//                            newMainContext.insert(app)
//                        }
//                        for model in messages {
//                            let message = Message(
//                                id: model.id,
//                                message: model.message,
//                                author: model.author,
//                                fetchedBackend: model.fetchedBackend,
//                                messageTitle: model.messageTitle,
//                                robotMessage: model.robotMessage
//                            )
//                            message.viewed = model.viewed
//
//                            newMainContext.insert(message)
//                        }
//
//                        try newMainContext.save()
//                    } catch {
//                        logger.error("Error migrating to new app group manually \(error)")
//                    }
//                }
//            }
//        } catch  {
//            logger.error("Error migrating to new app group \(error)")
//        }
//
//        UserDefaults.standard.set(true, forKey: UserDefaultKeys.usingNewAppGroup)
//    }

    let modelConfiguration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        groupContainer: .identifier(mainAppGroup)
    )

    return try ModelContainer(
        for: schema,
        migrationPlan: RoamSchemaMigrationPlan.self,
        configurations: [modelConfiguration]
    )
}
