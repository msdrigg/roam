import Foundation
import System

@MainActor
final class FileLock {
    enum Mode {
        case shared
        case exclusive
    }

    enum LockError: Error {
        case error(Error)
    }

    static let shared = FileLock(fileName: ".roamData.lock", appGroupIdentifier: mainAppGroup)

    private let fileName: String
    private let appGroupIdentifier: String

    init(fileName: String, appGroupIdentifier: String) {
        self.fileName = fileName
        self.appGroupIdentifier = appGroupIdentifier
    }

    func withLock<T>(mode: Mode, _ body: () throws -> T) throws -> T {
        Log.data.notice("Beginning file lock")
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            loggedFatalError("App group container not found: \(self.appGroupIdentifier)")
        }

        let lockFileURL = containerURL.appendingPathComponent(fileName)
        let path = lockFileURL.path

        if !FileManager.default.fileExists(atPath: path) {
            Log.data.notice("Creating file lock file")
            FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
        }

        let fd: FileDescriptor
        do {
            fd = try FileDescriptor.open(path, .readWrite)
        } catch {
            throw FileLock.LockError.error(error)
        }

        let op: Int32 = {
            switch mode {
            case .shared: return LOCK_SH
            case .exclusive: return LOCK_EX
            }
        }()

#if !os(macOS)
        let dontKillAssertion = QActivityRunInBackgroundAssertion(name: "OSFileLock")
        if dontKillAssertion.isReleased() {
            throw DataHandlerError.suspending
        }
#endif
        _ = flock(fd.rawValue, op)
        defer {
            Log.data.notice("Closing file lock")
            flock(fd.rawValue, LOCK_UN)
            try? fd.close()
            #if !os(macOS)
            dontKillAssertion.release()
            #endif
        }

        Log.data.notice("Executing body")
        let res = try body()
        Log.data.notice("Done executing body")
        return res
    }
}
