import SwiftData
import OSLog

let legacyContainerAppGroup = "group.com.msdrigg.roam.models"
let mainAppGroup = "group.com.msdrigg.roam"

public final class GlobalModelContainer {
    @MainActor
    fileprivate static let sharedModelContainerOrFailure = getModelContainerOrFailure()
}

public enum ModelContainerFailureReason: Error, LocalizedError {
    case schemaMigrationImpossible
    case noSpaceOnDisk
    case schemaInvalidState
    case unknown
}

public typealias ModelContainerResult = Result<ModelContainer, ModelContainerFailureReason>

@MainActor
public func getModelContainerFailureReason() -> ModelContainerFailureReason {
    return .unknown
}

@MainActor
public func getSharedModelContainerResult() -> ModelContainerResult {
    return GlobalModelContainer.sharedModelContainerOrFailure
}

@MainActor
public func getSharedModelContainerChecked() throws (ModelContainerFailureReason) -> ModelContainer {
    return try GlobalModelContainer.sharedModelContainerOrFailure.get()
}

@MainActor
public func getSharedModelContainer() -> ModelContainer {
    let mc: ModelContainer
    do {
        mc = try GlobalModelContainer.sharedModelContainerOrFailure.get()
    } catch {
        loggedFatalError("Error getting shared model container: \(error)")
    }
    return mc
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
private func getModelContainerOrFailure() -> Result<ModelContainer, ModelContainerFailureReason> {
    return _getSharedModelContainer()
}

@MainActor
private func _getSharedModelContainer() -> Result<ModelContainer, ModelContainerFailureReason> {
    let schema = Schema(
        versionedSchema: SchemaV5.self
    )

    let modelConfiguration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        groupContainer: .identifier(legacyContainerAppGroup),
    )

    do {
        let mc = try FileLock.shared.withLock(mode: .exclusive) {
            return try ModelContainer(
                for: schema,
                migrationPlan: RoamSchemaMigrationPlan.self,
                configurations: modelConfiguration
            )
        }
        return .success(mc)
    } catch {
        Log.data.error("Error getting model container: \(error)")
        return .failure(getModelContainerFailureReason())
    }
}
