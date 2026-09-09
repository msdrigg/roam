import Darwin
import Foundation
import os

public let roamAppGroup = "group.com.msdrigg.roam"

/// The app group container's URL, resolved once per process.
///
/// `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` is a
/// synchronous XPC round-trip whose result is fixed per process, so calling it
/// from a computed property put it on the main thread once per body evaluation.
/// Resolve through here instead. `nil` means the entitlement is missing or the
/// container could not be created.
public func roamAppGroupContainerURL() -> URL? {
    AppGroupContainer.url
}

private enum AppGroupContainer {
    static let url: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: roamAppGroup)
}

/// Durable, per-run diagnostics that outlive the process that wrote them.
///
/// `OSLogStore(scope: .currentProcessIdentifier)` covers the reading process,
/// and MetricKit delivers a payload to the launch after the one that died, so
/// crash reports shipped the relaunch's log.
///
/// Every `DualLogger` line is mirrored into a file named for the run that wrote
/// it, and the next launch reads the dead run's file back (see
/// `FileLog.collect(around:)`). `CrashStackTrap` below covers the other half of
/// the gap, where MetricKit cannot unwind a blown stack.
public enum FileLog {
    private static let directoryName = "process-logs"
    private static let maxBytesPerRun = 1_500_000
    private static let maxRunFiles = 8
    private static let flushThresholdBytes = 16 * 1024
    private static let flushInterval: TimeInterval = 1
    /// How often a still-failing sink is allowed to say so again.
    private static let failureLogInterval: TimeInterval = 60
    /// How long after launch to write through instead of batching.
    ///
    /// `flushNow()` only fires on background/terminate, so a run that dies
    /// inside `flushInterval` leaves nothing on disk and its crash reads as
    /// having no log at all -- which is exactly what a `SIGKILL` seconds into a
    /// background resume looks like. The launch window is both the most likely
    /// place to die unflushed and the cheapest to write through, so pay for it
    /// there and batch normally afterwards.
    private static let eagerFlushWindow: TimeInterval = 10

    private static let queue = DispatchQueue(
        label: "com.msdrigg.roam.file-log", qos: .utility)

    private static let selfLog = Logger(subsystem: Log.getLogSubsystem(), category: "FileLog")

    public static let pid = Int(ProcessInfo.processInfo.processIdentifier)
    private static let processName = ProcessInfo.processInfo.processName
    static let launchedAt = Date()

    nonisolated(unsafe) private static var buffer = Data()
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) private static var bytesWritten = 0
    nonisolated(unsafe) private static var flushScheduled = false
    nonisolated(unsafe) private static var consecutiveFailures = 0
    nonisolated(unsafe) private static var lastFailureLogAt: TimeInterval = 0
    nonisolated(unsafe) private static var started = false

    public static func start() {
        queue.async {
            guard !started else { return }
            started = true
            pruneOldRuns()
        }
        // `collect` picks a file by recency and cannot prove it found the run
        // that died. The pid can: MetricKit's metadata carries one, so a reader
        // holding both can check rather than assume.
        append(
            level: "Notice", category: "Lifecycle",
            message: "Run started pid=\(pid) process=\(processName)")
        observeLifecycle()
    }

    /// Record how this run began, once the platform can say.
    ///
    /// A background resume and a user opening the app die differently -- the
    /// first to `0xdead10cc` while it holds a lock in the shared container, the
    /// second to a watchdog -- and the stacks alone do not separate them.
    /// `state` is caller-supplied to keep UIKit and AppKit out of this file.
    public static func recordLaunchState(_ state: String) {
        append(level: "Notice", category: "Lifecycle", message: "Launch state=\(state)")
    }

    /// Flush before the process suspends; the flush timer stops running then.
    /// Named rather than typed to keep UIKit/AppKit out of this file.
    private static func observeLifecycle() {
        let names = [
            "NSApplicationWillTerminateNotification",
            "NSApplicationDidResignActiveNotification",
            "UIApplicationWillTerminateNotification",
            "UIApplicationDidEnterBackgroundNotification",
        ]
        for name in names {
            NotificationCenter.default.addObserver(
                forName: Notification.Name(name), object: nil, queue: nil
            ) { _ in
                flushNow()
            }
        }
    }

    public static func append(level: String, category: String, message: String) {
        let timestamp = Date().timeIntervalSince1970
        queue.async {
            appendEncoded(timestamp: timestamp, level: level, category: category, message: message)
        }
    }

    public static func flushNow() {
        queue.sync { flush() }
    }

    // MARK: Writing

    public static func encodedLine(
        timestamp: TimeInterval, level: String, category: String, message: String
    ) -> String {
        var line = "{\"t\":"
        line += String(format: "%.3f", timestamp)
        line += ",\"l\":\""
        line += jsonEscaped(level)
        line += "\",\"c\":\""
        line += jsonEscaped(category)
        line += "\",\"m\":\""
        line += jsonEscaped(message)
        line += "\"}\n"
        return line
    }

    private static func appendEncoded(
        timestamp: TimeInterval, level: String, category: String, message: String
    ) {
        let line = encodedLine(
            timestamp: timestamp, level: level, category: category, message: message)
        buffer.append(contentsOf: Array(line.utf8))
        if buffer.count >= flushThresholdBytes
            || timestamp - launchedAt.timeIntervalSince1970 < eagerFlushWindow
        {
            flush()
        } else {
            scheduleFlush()
        }
    }

    private static func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + flushInterval) {
            flushScheduled = false
            flush()
        }
    }

    private static func flush() {
        guard !buffer.isEmpty else { return }
        let pending = buffer
        buffer.removeAll(keepingCapacity: true)
        do {
            let handle = try openHandle()
            try handle.write(contentsOf: pending)
            bytesWritten += pending.count
            if consecutiveFailures > 0 {
                selfLog.notice(
                    "file-log write recovered after \(consecutiveFailures, privacy: .public) failures"
                )
                consecutiveFailures = 0
            }
            if bytesWritten > maxBytesPerRun {
                trim()
            }
        } catch {
            noteFailure(error)
            try? handle?.close()
            handle = nil
        }
    }

    /// Report a write failure without letting it become the log.
    ///
    /// A failed flush drops its handle, so the next line retries from
    /// `openHandle()` and fails the same way: one `os_log` error per line
    /// written, 1:1 and unbounded. Two runs against a container they could not
    /// reach emitted 653 between them, which buries the one failure that
    /// matters under the noise it generates. Report the first immediately,
    /// then at most one a minute carrying the count, so a broken sink stays
    /// visible without crowding out everything else.
    ///
    /// The dropped lines are not recovered. `flush` clears the buffer before
    /// writing, and a container this process cannot reach stays unreachable
    /// for the life of the run, so holding them would grow memory to no end.
    private static func noteFailure(_ error: Error) {
        consecutiveFailures += 1
        let now = Date().timeIntervalSince1970
        guard consecutiveFailures == 1 || now - lastFailureLogAt >= failureLogInterval else {
            return
        }
        lastFailureLogAt = now
        if consecutiveFailures == 1 {
            selfLog.error("file-log write failed: \(error.localizedDescription, privacy: .public)")
        } else {
            selfLog.error(
                "file-log write failed: \(error.localizedDescription, privacy: .public) (\(consecutiveFailures, privacy: .public) failures so far)"
            )
        }
    }

    private static func openHandle() throws -> FileHandle {
        if let handle { return handle }
        guard let url = runFileURL() else { throw CocoaError(.fileNoSuchFile) }
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            try manager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // `createFile` reports failure in a `Bool`, and discarding it sent
            // the real reason to the floor: a container the process may not
            // touch surfaced one line later as `FileHandle`'s "the file does
            // not exist", which reads as a missing file rather than a denied
            // one. Debug builds run from DerivedData are denied this group
            // container, so that is the message the misleading version was
            // most likely to print. Read `errno` while it still describes
            // this call.
            guard manager.createFile(atPath: url.path, contents: nil) else {
                let code = errno
                throw NSError(
                    domain: NSPOSIXErrorDomain, code: Int(code),
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "could not create \(url.lastPathComponent): \(String(cString: strerror(code)))"
                    ])
            }
        }
        let opened = try FileHandle(forWritingTo: url)
        try opened.seekToEnd()
        bytesWritten = Int(try opened.offset())
        handle = opened
        return opened
    }

    private static func trim() {
        guard
            let url = runFileURL(),
            let data = try? Data(contentsOf: url)
        else { return }
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        var kept = data.count
        while kept > maxBytesPerRun, !lines.isEmpty {
            kept -= lines.removeFirst().count + 1
        }
        var out = Data(capacity: kept)
        for line in lines {
            out.append(contentsOf: line)
            out.append(0x0A)
        }
        try? handle?.close()
        handle = nil
        try? out.write(to: url, options: .atomic)
        bytesWritten = out.count
    }

    /// Keep the newest `maxRunFiles` runs per process, never our own. The
    /// widget shares this directory and launches far more often.
    private static func pruneOldRuns() {
        guard let directory = directoryURL() else { return }
        let manager = FileManager.default
        let ours = runFileURL()?.lastPathComponent
        let files =
            (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? []

        var byProcess: [String: [URL]] = [:]
        for file in files
            where file.pathExtension == "jsonl" && file.lastPathComponent != ours
        {
            let stem = file.deletingPathExtension().lastPathComponent
            let process = stem.split(separator: "-", maxSplits: 2).last.map(String.init) ?? stem
            byProcess[process, default: []].append(file)
        }

        for (_, runs) in byProcess {
            let stale = runs
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
                .dropFirst(maxRunFiles)
            for file in stale {
                try? manager.removeItem(at: file)
                try? manager.removeItem(at: file.deletingPathExtension().appendingPathExtension("stack"))
            }
        }
    }

    // MARK: Reading

    /// Entries from **previous** runs, newest last, centred on a crash.
    ///
    /// `window` is MetricKit's payload window. Anything logged after it belongs
    /// to a later launch and is dropped, including this run's own file.
    ///
    /// Selection is by **recency, not identity**: this returns the newest
    /// previous run that has lines in the window, which is usually the run that
    /// died but is not guaranteed to be. A run killed before its first flush
    /// contributes nothing and silently yields the run before it instead.
    /// Compare the `Run started pid=` marker against the report's pid before
    /// reading these lines as the crash's.
    public static func collect(around window: DateInterval?, limit: Int = 5000) -> [FileLogEntry] {
        guard let directory = directoryURL() else { return [] }
        let manager = FileManager.default
        let ours = runFileURL()?.lastPathComponent
        let files =
            (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? []

        let candidates =
            files
            .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent != ours }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        let cutoff = window.map { $0.end.addingTimeInterval(120) }

        var collected: [FileLogEntry] = []
        let decoder = JSONDecoder()
        for file in candidates {
            guard let data = try? Data(contentsOf: file) else { continue }
            var fromFile: [FileLogEntry] = []
            for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
                guard let entry = try? decoder.decode(FileLogEntry.self, from: Data(line))
                else { continue }
                if let cutoff, entry.date > cutoff { continue }
                fromFile.append(entry)
            }
            collected.insert(contentsOf: fromFile, at: 0)
            if collected.count >= limit { break }
        }

        if collected.count > limit {
            collected.removeFirst(collected.count - limit)
        }
        return collected
    }

    public static func deleteAll() {
        queue.async {
            try? handle?.close()
            handle = nil
            buffer.removeAll(keepingCapacity: false)
            bytesWritten = 0
            guard let directory = directoryURL() else { return }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: Paths

    static func directoryURL() -> URL? {
        let container = roamAppGroupContainerURL()
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return container?.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Sortable by age, and unique even when the OS recycles a pid.
    static func runFileName(extension pathExtension: String) -> String {
        let stamp = Int(launchedAt.timeIntervalSince1970 * 1000)
        return "\(stamp)-\(pid)-\(processName).\(pathExtension)"
    }

    private static func runFileURL() -> URL? {
        directoryURL()?.appendingPathComponent(runFileName(extension: "jsonl"))
    }

    private static func jsonEscaped(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count + 8)
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if character.value < 0x20 {
                    out += String(format: "\\u%04x", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out
    }
}

/// One line read back off disk. Short keys because they are written once per
/// log line; `FileLog` writes this shape by hand.
public struct FileLogEntry: Codable, Sendable {
    let t: TimeInterval
    let l: String
    let c: String
    let m: String

    var date: Date { Date(timeIntervalSince1970: t) }
    var level: String { l }
    var category: String { c }
    var message: String { m }
}

/// Writes the crashing thread's backtrace to disk from inside a `SIGSEGV`
/// handler running on its own signal stack.
///
/// MetricKit cannot unwind a stack overflow: the attributed thread arrives with
/// zero frames in the raw payload. An ordinary handler cannot help either,
/// since the overflowed thread has no stack left to run it on, so `sigaltstack`
/// gives the handler its own.
///
/// The handler touches only async-signal-safe calls (`open`, `write`,
/// `backtrace`, `backtrace_symbols_fd`), then restores the previous disposition
/// so the OS still produces the crash report MetricKit delivers.
public enum CrashStackTrap {
    private static let maxFrames = 192

    nonisolated(unsafe) private static var installed = false
    /// Preallocated at install time - a signal handler must not allocate.
    nonisolated(unsafe) private static var frames: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    nonisolated(unsafe) private static var alternateStack: UnsafeMutableRawPointer?
    nonisolated(unsafe) static var pathBuffer: UnsafeMutablePointer<CChar>?

    /// Install the handler. Idempotent, and a no-op on watchOS, where
    /// `sigaltstack` is unavailable.
    public static func install() {
        #if os(watchOS)
            return
        #else
            installHandler()
        #endif
    }

    #if !os(watchOS)
    private static func installHandler() {
        guard !installed else { return }
        guard let url = traceFileURL() else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Everything the handler touches is set up here, while it is still safe
        // to allocate: a lazily-initialised Swift global read for the first
        // time from inside a signal handler can deadlock on its own once-token.
        let path = url.path
        let bytes = Array(path.utf8CString)
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
        buffer.update(from: bytes, count: bytes.count)
        pathBuffer = buffer
        frames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: maxFrames)

        let stackSize = max(Int(SIGSTKSZ), 128 * 1024)
        let stack = UnsafeMutableRawPointer.allocate(
            byteCount: stackSize, alignment: MemoryLayout<UInt>.alignment)
        alternateStack = stack
        var signalStack = stack_t(ss_sp: stack, ss_size: stackSize, ss_flags: 0)
        guard sigaltstack(&signalStack, nil) == 0 else { return }

        var action = sigaction()
        action.__sigaction_u.__sa_sigaction = crashStackTrapHandler
        action.sa_flags = Int32(SA_ONSTACK | SA_SIGINFO | SA_RESETHAND)
        sigemptyset(&action.sa_mask)
        // SIGSEGV is the guard-page hit; SIGBUS is the same fault on a
        // misaligned or unmapped access and costs nothing to cover.
        sigaction(SIGSEGV, &action, nil)
        sigaction(SIGBUS, &action, nil)

        installed = true
    }
    #endif

    /// The backtrace left by a **previous** run, if one died on a bad access.
    /// Reading consumes it, so a trace is uploaded once.
    public static func collectPrevious() -> [String] {
        guard let directory = FileLog.directoryURL() else { return [] }
        let manager = FileManager.default
        let ours = traceFileURL()?.lastPathComponent
        let files =
            (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? []
        var traces: [String] = []
        for file in files
            where file.pathExtension == "stack" && file.lastPathComponent != ours
        {
            if let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty {
                traces.append(text)
            }
            try? manager.removeItem(at: file)
        }
        return traces
    }

    static func traceFileURL() -> URL? {
        FileLog.directoryURL()?.appendingPathComponent(FileLog.runFileName(extension: "stack"))
    }

    // Called from the signal handler. Kept here so the handler itself is a
    // plain C function with no Swift metadata work in its path.
    fileprivate static func writeTrace(signal: Int32) {
        guard let pathBuffer, let frames else { return }
        let fd = open(pathBuffer, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard fd >= 0 else { return }

        writeLiteral(fd, "Fatal access violation, signal ")
        writeInt(fd, Int(signal))
        writeLiteral(fd, ", at unix time ")
        writeInt(fd, Int(time(nil)))
        writeLiteral(fd, "\nBacktrace of the faulting thread (innermost first):\n")

        let count = backtrace(frames, Int32(maxFrames))
        // `backtrace_symbols_fd` writes straight to the descriptor; the
        // allocating `backtrace_symbols` would not be safe here.
        backtrace_symbols_fd(frames, count, fd)
        if count >= Int32(maxFrames) {
            writeLiteral(fd, "... truncated, the stack is at least this deep\n")
        }
        close(fd)
    }

    private static func writeLiteral(_ fd: Int32, _ text: StaticString) {
        _ = text.withUTF8Buffer { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return write(fd, base, buffer.count)
        }
    }

    /// Decimal, without `malloc`. A signal handler must not allocate - the
    /// process may well have crashed inside the allocator, and taking its lock
    /// again would hang instead of crashing.
    private static func writeInt(_ fd: Int32, _ value: Int) {
        let capacity = 24
        withUnsafeTemporaryAllocation(of: CChar.self, capacity: capacity) { digits in
            var value = value
            var index = capacity - 1
            if value <= 0 {
                digits[index] = CChar(UInt8(ascii: "0"))
                index -= 1
            }
            while value > 0, index >= 0 {
                digits[index] = CChar(UInt8(ascii: "0") + UInt8(value % 10))
                value /= 10
                index -= 1
            }
            let start = index + 1
            guard let base = digits.baseAddress else { return }
            _ = write(fd, base + start, capacity - start)
        }
    }
}

/// The `SA_SIGINFO` handler. A file-scope C function so no Swift closure
/// context is needed at signal time.
///
/// It writes the trace and returns. `SA_RESETHAND` has restored the default
/// disposition, so the faulting instruction re-executes and the process dies
/// with the same address, thread and frame. `raise` would instead hand the OS
/// crash reporter its own stack rather than the recursion's.
#if !os(watchOS)
private let crashStackTrapHandler:
    @convention(c) (Int32, UnsafeMutablePointer<siginfo_t>?, UnsafeMutableRawPointer?) -> Void = {
        signalNumber, _, _ in
        CrashStackTrap.writeTrace(signal: signalNumber)
    }
#endif
