import SwiftData
import OSLog

let mainAppGroup = "group.com.msdrigg.roam.models"
let tipsAppGroup = "group.com.msdrigg.roam.tips"
let loadAppGroup = "group.com.msdrigg.roam.load"

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
        loggedFatalError("Error getting shared model container \(error))")
    }
}

@MainActor
private func _getSharedModelContainer() throws -> ModelContainer {
    let schema = Schema(
        versionedSchema: SchemaV4.self
    )

    let modelConfiguration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        groupContainer: .identifier(mainAppGroup)
    )

    let mc = try catchObjc {
        return try ModelContainer(
            for: schema,
            migrationPlan: RoamSchemaMigrationPlan.self,
            configurations: [modelConfiguration]
        )
    }
    
    mc.mainContext.autosaveEnabled = false
    return mc
}
