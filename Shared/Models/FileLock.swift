import Foundation
import System

public enum FileLockError<E: Sendable>: Error, LocalizedError {
    case suspending
    case groupContainerFailed
    case fileLockFailed
    case fileError(error: Error)
    case inner(E)
}

final class FileLock {
    enum Mode {
        case shared
        case exclusive
    }

    enum LockError: Error {
        case error(Error)
    }

    @MainActor
    static let shared = FileLock(fileName: ".roamData.lock", appGroupIdentifier: mainAppGroup)

    private let fileName: String
    private let appGroupIdentifier: String

    init(fileName: String, appGroupIdentifier: String) {
        self.fileName = fileName
        self.appGroupIdentifier = appGroupIdentifier
    }

    func withLock<T, E>(mode: Mode, _ body: () throws (E) -> T) throws (FileLockError<E>) -> T {
        Log.data.notice("Beginning file lock")
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw FileLockError.groupContainerFailed
        }

        let lockFileURL = containerURL.appendingPathComponent(fileName)
        let path = lockFileURL.path

        if !FileManager.default.fileExists(atPath: path) {
            Log.data.notice("Creating file lock file")
            let created = FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
            if !created {
                Log.data.notice("File lock NOT created")
            }
        } else {
            Log.data.notice("File lock already exists")
        }

        let fd: FileDescriptor
        do {
            fd = try FileDescriptor.open(path, .readWrite)
        } catch {
            throw FileLockError.fileError(error: error)
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
            throw FileLockError.suspending
        }
#endif
        let lockResult = flock(fd.rawValue, op)

        if lockResult == -1 {
            let error = errno
            logErrorMessage(error)
            throw FileLockError.fileLockFailed
        }

        defer {
            Log.data.notice("Closing file lock")
            let unlockResult = flock(fd.rawValue, LOCK_UN)
            if unlockResult == -1 {
                let error = errno
                logErrorMessage(error, isUnlock: true)
            }

            try? fd.close()
            #if !os(macOS)
            dontKillAssertion.release()
            #endif
        }

        Log.data.notice("Executing body")
        do {
            let res = try body()
            Log.data.notice("Done executing body")
            return res
        } catch {
            throw .inner(error)
        }
    }
}

func logErrorMessage(_ error: Int32, isUnlock: Bool = false) {
    let errorMessage = String(cString: strerror(error))
    switch error {
    case EBADF:
        Log.data.error("Invalid file descriptor for lock operation unlock=\(isUnlock, privacy: .public)")
    case EINVAL:
        Log.data.error("Invalid lock operation specified")
    case EWOULDBLOCK, EAGAIN:
        // Lock would block and LOCK_NB was specified
        Log.data.error("Lock is held by another process (non-blocking mode) unlock=\(isUnlock, privacy: .public)")
    case ENOLCK:
        Log.data.error("System lock table is full - no locks available unlock=\(isUnlock, privacy: .public)")
    case ENOTSUP, EOPNOTSUPP:
        Log.data.error("File system doesn't support locking unlock=\(isUnlock, privacy: .public)")
    case EACCES, EPERM:
        Log.data.error("Permission denied for lock operation unlock=\(isUnlock, privacy: .public)")
    default:
        Log.data.error("Lock operation failed: \(errorMessage) (errno: \(error)) unlock=\(isUnlock, privacy: .public)")
    }
}
