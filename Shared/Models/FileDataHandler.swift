import Foundation
import OSLog

// MARK: - File Data Handler
class FileDataHandler {
    private let rootPath: String
    private let fileManager = FileManager.default

    init(rootPath: String) {
        self.rootPath = rootPath
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        guard !fileManager.fileExists(atPath: rootPath) else { return }

        do {
            try fileManager.createDirectory(atPath: rootPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Log.data.error("Failed to create root directory: \(error)")
        }
    }

    // MARK: - File Operations
    func path(for filename: String) -> String {
        return "\(rootPath)/\(filename.stripPrefix("/"))"
    }

    func fileExists(_ filename: String) -> Bool {
        return fileManager.fileExists(atPath: path(for: filename))
    }

    func loadJSON<T: Codable>(_ filename: String, as type: T.Type) throws -> T {
        let filePath = path(for: filename)
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        return try JSONDecoder().decode(type, from: data)
    }

    func saveJSON<T: Codable>(_ object: T, to filename: String) throws {
        let filePath = path(for: filename)
        Log.data.notice("Saving JSON to \(filePath, privacy: .public)")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // Optional: for readable files
        let data = try encoder.encode(object)
        try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }

    func createSymlink(from: String, to: String) throws {
        let fromPath = path(for: from)
        let toPath = path(for: to)

        // Remove existing symlink if it exists
        if fileManager.fileExists(atPath: fromPath) {
            Log.data.notice("Removing symlink for \(fromPath, privacy: .public)")
            try fileManager.removeItem(atPath: fromPath)
        }

        Log.data.notice("Creating symlink for \(fromPath, privacy: .public)")
        try fileManager.createSymbolicLink(atPath: fromPath, withDestinationPath: toPath)
    }

    func deleteFile(_ filename: String) throws {
        let filePath = path(for: filename)
        if fileManager.fileExists(atPath: filePath) {
            try fileManager.removeItem(atPath: filePath)
        }
    }

    func clearAllFiles() throws {
        guard fileManager.fileExists(atPath: rootPath) else { return }

        let contents = try fileManager.contentsOfDirectory(atPath: rootPath)
        for filename in contents {
            let filePath = path(for: filename)
            try fileManager.removeItem(atPath: filePath)
        }
    }
}

// MARK: - Error Handling
enum DataHandlerError: Error, LocalizedError {
    case suspending
    case noSpaceOnDisk
    case noContainerURL
    case deviceNotFound
    case rootError(LocalizedError)
    case unknown

    var errorDescription: String? {
        switch self {
        case .noContainerURL:
            return String(localized: "No valid container found")
        case .noSpaceOnDisk:
            return String(localized: "No disk storage left")
        case .suspending:
            return String(localized: "App currently shutting down.")
        case .deviceNotFound:
            return String(localized: "Cannot update device that is deleted.")
        case .unknown:
            return String(localized: "Operation failed.")
        case .rootError(let error):
            return error.errorDescription ?? String(localized: "Operation failed.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noContainerURL:
            return String(localized: "This is a bug. Please reach out to roam-support@msd3.io for help")
        case .noSpaceOnDisk:
            return String(localized: "Please delete some files to clear up some space and try again")
        case .suspending:
            return String(localized: "Please re-open the app and try again.")
        case .deviceNotFound:
            return String(localized: "Please make sure the device you are updating has been added.")
        case .unknown:
            return String(localized: "Please close and re-open the app and then try again.")
        case .rootError(let error):
            return error.recoverySuggestion ?? String(localized: "Please close and re-open the app and then try again.")
        }
    }

    static func from(error: Error) -> Self {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError {
            return .noSpaceOnDisk
        }
        if let error = error as? LocalizedError {
            return .rootError(error)
        }
        return .unknown
    }
}

// MARK: - File Storage Utilities
@discardableResult
func storeUserFileToDisk(data: Data, filename: String, path: [String]) throws -> URL {
    guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: mainAppGroup) else {
        throw DataHandlerError.noContainerURL
    }

    var targetDirectoryURL = containerURL
    for pathComponent in path {
        targetDirectoryURL = targetDirectoryURL.appendingPathComponent(pathComponent, isDirectory: true)
    }

    if !FileManager.default.fileExists(atPath: targetDirectoryURL.path) {
        try FileManager.default.createDirectory(at: targetDirectoryURL, withIntermediateDirectories: true)
    }

    let fileURL = targetDirectoryURL.appendingPathComponent(filename)

    do {
        try data.write(to: fileURL, options: .atomic)
    } catch let error as NSError {
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError {
            throw DataHandlerError.noSpaceOnDisk
        }
        throw error
    } catch {
        throw error
    }
    return fileURL
}

@discardableResult
func storeIconToDisk(iconData: Data, hash: String) throws -> URL {
    return try storeUserFileToDisk(data: iconData, filename: hash, path: ["roku-icons"])
}

@discardableResult
func storeAttachmentToDisk(attachmentData: Data, hash: String, filename: String) throws -> URL {
    return try storeUserFileToDisk(data: attachmentData, filename: filename, path: ["message-attachments", hash])
}

func loadAttachmentFromDisk(hash: String, filename: String) throws -> Data {
    guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: mainAppGroup) else {
        throw DataHandlerError.noContainerURL
    }

    let attachmentDirectoryURL = containerURL
        .appendingPathComponent("message-attachments", isDirectory: true)
        .appendingPathComponent(hash, isDirectory: true)

    let fileURL = attachmentDirectoryURL.appendingPathComponent(filename)
    return try Data(contentsOf: fileURL)
}
