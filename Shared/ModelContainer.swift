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

public final class GlobalModelContainer {
    @MainActor
    static let sharedModelContainer = demandSharedModelContainer()
}

@MainActor
public func getSharedModelContainer() -> ModelContainer {
    GlobalModelContainer.sharedModelContainer
}

public func inScreenshotTestingContext() -> Bool {
    #if DEBUG
    return CommandLine.arguments.contains("-ScreenshotTesting")
    #else
    return false
    #endif
}

public func usingTestingDataContainer() -> Bool {
    #if DEBUG
    return CommandLine.arguments.contains("-SwiftDataTesting")
    #else
    return false
    #endif
}

public func loadTestingData() -> Bool {
    #if DEBUG
    return CommandLine.arguments.contains("-SwiftDataLoadTestingData")
    #else
    return false
    #endif
}

@MainActor
private func demandSharedModelContainer() -> ModelContainer {
    do {
        #if DEBUG
        if usingTestingDataContainer() {
            return getTestingContainer()
        } else {
            return try _getSharedModelContainer()
        }
        #else
        return try _getSharedModelContainer()
        #endif
    } catch {
        fatalError("Error getting shared model container \(error))")
    }
}

private func _getSharedModelContainer() throws -> ModelContainer {
    let schema = Schema(
        versionedSchema: SchemaV4.self
    )

    let modelConfiguration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        groupContainer: .identifier(mainAppGroup)
    )

    return try catchObjc {
        return try ModelContainer(
            for: schema,
            migrationPlan: RoamSchemaMigrationPlan.self,
            configurations: [modelConfiguration]
        )
    }
}
