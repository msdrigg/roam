import Darwin
import Foundation

final class DatabaseFileLock: @unchecked Sendable {
    private let lockURL: URL

    init(lockURL: URL) {
        self.lockURL = lockURL
    }

    func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: lockURL.path) {
            FileManager.default.createFile(atPath: lockURL.path, contents: nil)
        }

        let fd = open(lockURL.path, O_RDWR)
        guard fd >= 0 else {
            throw DataHandlerError.fromPOSIX(errno: errno, fallback: .databaseLocked)
        }

        if flock(fd, LOCK_EX) != 0 {
            let lockErrno = errno
            close(fd)
            throw DataHandlerError.fromPOSIX(errno: lockErrno, fallback: .databaseLocked)
        }

        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }

        return try body()
    }
}
