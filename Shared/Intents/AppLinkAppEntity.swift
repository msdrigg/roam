import AppIntents
import Foundation
import SwiftData
import OSLog

private nonisolated let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "AppLinkAppEntity"
)

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct AppLinkAppEntity: Identifiable, Equatable, Hashable, Encodable, Sendable {
    var name: String
    public var id: String
    public var type: String
    public var modelId: PersistentIdentifier
    public var icon: Data?

    init(name: String, id: String, type: String, modelId: PersistentIdentifier, icon: Data? = nil) {
        self.name = name
        self.id = id
        self.type = type
        self.modelId = modelId
        self.icon = icon
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name
    }
}

#if !os(watchOS)
import CoreSpotlight

extension AppLinkAppEntity: IndexedEntity {}
#endif

#if !os(tvOS)
    extension AppLinkAppEntity: AppEntity {
        public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("TV App", comment: "TV App Selection option"))
        public static let defaultQuery = AppLinkAppEntityQuery()

        public struct AppLinkAppEntityQuery: EntityQuery {
            @IntentParameterDependency<LaunchAppIntent>(\.$device) var launchAppIntent

            public init() {}

            public func entities(for identifiers: [AppLinkAppEntity.ID]) async throws -> [AppLinkAppEntity] {
                let appLinkActor = DataHandler(modelContainer: getSharedModelContainer())
                return try await appLinkActor.appEntities(for: identifiers, deviceUid: launchAppIntent?.device.udn)
            }

            func entities(matching string: String) async throws -> [AppLinkAppEntity] {
                let appLinkActor = DataHandler(modelContainer: getSharedModelContainer())
                return try await appLinkActor.appEntities(matching: string, deviceUid: launchAppIntent?.device.udn)
            }

            public func suggestedEntities() async throws -> [AppLinkAppEntity] {
                let appLinkActor = DataHandler(modelContainer: getSharedModelContainer())
                return try await appLinkActor.appEntities(deviceUid: launchAppIntent?.device.udn)
            }
        }

        public var displayRepresentation: DisplayRepresentation {
            DisplayRepresentation(title: "\(name)", image: (icon != nil) ? DisplayRepresentation.Image(data: icon!) : DisplayRepresentation.Image(systemName: "app.dashed"))
        }
    }
#endif

public extension AppLink {
    func toAppEntity() -> AppLinkAppEntity {
        AppLinkAppEntity(name: name, id: id, type: type, modelId: persistentModelID)
    }

    func toAppEntityWithIcon() -> AppLinkAppEntity {
        AppLinkAppEntity(name: name, id: id, type: type, modelId: persistentModelID, icon: icon)
    }
}

public func launchApp(app: AppLinkAppEntity, device: DeviceAppEntity?) async throws {
    let modelContainer = getSharedModelContainer()
    let dataHandler = DataHandler(modelContainer: modelContainer)

    var targetDevice = device
    if targetDevice == nil {
        targetDevice = await dataHandler.fetchSelectedDeviceAppEntity()
    }

    if let targetDevice {
        #if os(watchOS)
        do {
            try await openApp(location: targetDevice.location, app: app.id)
        } catch {
            logger.error("Error opening app: \(error, privacy: .public)")
            throw ApiError.deviceNotConnectable
        }
        #else
        let ecpSession: ECPSession?
        let ecpSessionState: ECPSessionState = await ECPSessionState()
        do {
            ecpSession = try ECPSession(device: targetDevice, status: ecpSessionState)
            try await ecpSession?.configure()
            try await ecpSession?.openApp(app)
        } catch {
            logger.error("Error creating ECPSession or opening app: \(error, privacy: .public)")
            throw ApiError.deviceNotConnectable
        }
        #endif
    } else {
        throw ApiError.noSavedDevices
    }
}

enum ApiError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noSavedDevices
    case deviceNotConnectable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noSavedDevices: LocalizedStringResource("No saved devices", comment: "Error message description")
        case .deviceNotConnectable: LocalizedStringResource("Couldn't connect to the device", comment: "Error message description")
        }
    }
}
