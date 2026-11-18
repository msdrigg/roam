import Foundation
import os
import OSLog

struct DebugError: Error {
    let message: String
}

struct BadResponseError: Error {
    let message: String
}

struct LogEntry: Codable {
    let message: String
    let timestamp: Date
    let level: String?
    let category: String?
    let subsystem: String?
    /// Which launch wrote the line. `nil` for entries read live out of
    /// `OSLogStore`, which by definition come from the running process;
    /// `"previous-run"` for lines replayed from `FileLog` after a crash;
    /// `"file-log"` for this run's own lines read from `FileLog` because
    /// `OSLogStore` had none. The distinction travels with the entry rather
    /// than being inferred from timestamps at the far end.
    let source: String?

    init(entry: OSLogEntry) {
        source = nil
        message = entry.composedMessage
        timestamp = entry.date

        if let logEntry = entry as? OSLogEntryLog {
            switch logEntry.level {
            case .info:
                level = "Info"
            case .debug:
                level = "Debug"
            case .error:
                level = "Error"
            case .fault:
                level = "Fault"
            case .notice:
                level = "Notice"
            case .undefined:
                level = "Undefined"
            default:
                level = "Unknown"
            }
        } else {
            level = nil
        }

        if let payloadEntry = entry as? any OSLogEntryWithPayload {
            category = payloadEntry.category
            subsystem = payloadEntry.subsystem
        } else {
            category = nil
            subsystem = nil
        }
    }

    /// A line read back from a file log.
    init(fileEntry: FileLogEntry, source: String = "previous-run") {
        message = fileEntry.message
        timestamp = fileEntry.date
        level = fileEntry.level
        category = fileEntry.category
        subsystem = Log.getLogSubsystem()
        self.source = source
    }
}

struct ResponseData: Codable {
    let headers: [String: String]
    let statusCode: Int
    let data: String
}

struct DeviceDebugInfo: Codable {
    let device: Device
    let successResponse: ResponseData?
    let errorResponse: String?
    /// Result of querying `query/apps`. A Roku that answers `query/device-info` but
    /// rejects this one with a 403 is refusing control from apps, which looks identical
    /// to a healthy device from discovery alone.
    let appsResponse: ResponseData?
    let appsErrorResponse: String?
}

public struct InstallationInfo: Codable, Sendable {
    let userId: String
    let buildVersion: String?
    let releaseVersion: String?
    let osPlatform: String?
    let osVersion: String?
    let userLocale: String?

    init() {
        osVersion = ProcessInfo().operatingSystemVersionString
        #if os(iOS)
            osPlatform = "iOS"
        #elseif os(macOS)
            osPlatform = "macOS"
        #elseif os(watchOS)
            osPlatform = "watchOS"
        #elseif os(visionOS)
            osPlatform = "visionOS"
        #endif

        if let infoPlist = Bundle.main.infoDictionary,
           let currentProjectVersion = infoPlist["CURRENT_PROJECT_VERSION"] as? String
        {
            buildVersion = currentProjectVersion
            releaseVersion = infoPlist["CFBundleShortVersionString"] as? String
        } else {
            buildVersion = nil
            releaseVersion = nil
        }
        userId = getSystemInstallID()
        userLocale = Locale.autoupdatingCurrent.language.languageCode?.identifier
    }
}

public struct DebugLanguage: Codable, Sendable {
    let deviceLanguageCode: String
    let translatedLanguageCode: String
}

public struct DebugInfo: Codable, Sendable {
    let installationInfo: InstallationInfo
    let userDefaults: [String: String]
    let spaceOnDevice: Int64?
    let devices: [DeviceDebugInfo]
    let appLinks: [ AppLink]
    let interfaces: [Addressed4NetworkInterface]
    var logs: [LogEntry]
    let debugErrors: [String]
    let language: DebugLanguage
    /// Backtraces written by `CrashStackTrap` from inside the fatal signal
    /// handler of a previous run. Optional so diagnostics cached by an older
    /// build still decode.
    let faultingThreadBacktraces: [String]?
}

func trimmedDebugInfoIfNeeded(_ debugInfo: DebugInfo, maxFileSize: Int = 9 * 1024 * 1024) -> Data? {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    var trimmedDebugInfo = debugInfo

    do {
        var data = try encoder.encode(trimmedDebugInfo)
        if data.count <= maxFileSize {
            return data
        }

        // Iteratively remove log entries until the size is within the limit
        while trimmedDebugInfo.logs.count > 1 {
            let removeCount = max(trimmedDebugInfo.logs.count / 10, 1) // Remove 10% at a time
            trimmedDebugInfo.logs.removeLast(removeCount)

            data = try encoder.encode(trimmedDebugInfo)
            if data.count <= maxFileSize {
                return data
            }
        }

        // If removing all logs still doesn't fit, return the struct without logs
        trimmedDebugInfo.logs = []
        data = try encoder.encode(trimmedDebugInfo)

        return data.count <= maxFileSize ? data : nil
    } catch {
        return nil
    }
}

/// Queries one ECP endpoint and records the whole exchange, whatever the status.
///
/// Non-200 replies are captured rather than discarded: the status and body are exactly
/// what distinguishes a device refusing control from one that is unreachable.
private func probeDeviceEndpoint(
    location: String,
    path: String,
    timeout: TimeInterval = 1.5
) async -> (response: ResponseData?, error: String?) {
    let endpoint = "\(location)\(path)"
    do {
        guard let url = URL(string: endpoint) else {
            throw DebugError(message: "Bad URL \(endpoint)")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BadResponseError(
                message: "Got non-http response trying to query \(path) \(String(describing: response))"
            )
        }
        guard let dataString = String(data: data, encoding: .utf8) else {
            throw BadResponseError(message: "Nonutf8 response from /\(path)")
        }

        return (
            ResponseData(
                headers: headerDictionary(httpResponse),
                statusCode: httpResponse.statusCode,
                data: dataString
            ),
            nil
        )
    } catch {
        return (nil, "\(error)")
    }
}

/// Assemble the diagnostics bundle.
///
/// `crashWindow` is MetricKit's payload window, and changes where the logs come
/// from. Without it the logs are this process's, read live out of `OSLogStore`.
/// With it they are the **dead** run's, replayed from `FileLog`: MetricKit only
/// delivers a payload to the launch after the crash, so the live store holds
/// the relaunch and says nothing about what crashed.
func getDebugInfo(userInitiated: Bool = false, crashWindow: DateInterval? = nil) async -> DebugInfo {
    var debugErrors: [String] = []
    var entries: [LogEntry] = []
    var faultingThreadBacktraces: [String] = []

    if crashWindow != nil {
        entries = FileLog.collect(around: crashWindow).map { LogEntry(fileEntry: $0) }
        if entries.isEmpty {
            // No file log yet - a build from before this existed, or a first
            // launch that crashed. Say so rather than silently shipping the
            // relaunch's log as if it were the crash's.
            debugErrors.append(
                "No file-log entries for the crash window; falling back to this process's log, which is the launch after the crash."
            )
            do {
                entries = try getLogEntries()
            } catch {
                debugErrors.append("Error Getting Log Entries: \n\(error)")
            }
        }
        faultingThreadBacktraces = CrashStackTrap.collectPrevious()
    } else {
        let current = currentRunLogEntries()
        entries = current.entries
        debugErrors.append(contentsOf: current.notes)
    }
    Log.backend.info("Got \(entries.count) log entries")

    var devices: [Device] = []
    do {
        devices = try await RoamDataHandler.sharedChecked().requestAllDevices(RoamDataHandler.sharedChecked().requestDeviceList())
    } catch {
        debugErrors.append("Error Getting Devices: \n\(error)")
    }
    var deviceDebugInfos: [DeviceDebugInfo] = []

    for device in devices {
        // Probed independently: a blocked Roku answers device-info but rejects apps, and
        // that difference is the whole diagnosis.
        let deviceInfo = await probeDeviceEndpoint(location: device.location, path: "query/device-info")
        let apps = await probeDeviceEndpoint(location: device.location, path: "query/apps")

        deviceDebugInfos.append(DeviceDebugInfo(
            device: device,
            successResponse: deviceInfo.response,
            errorResponse: deviceInfo.error,
            appsResponse: apps.response,
            appsErrorResponse: apps.error
        ))
    }

    let localInterfaces = await allAddressedInterfaces()

    var appLinks: [AppLink] = []
    do {
        for device in devices {
            for app in try await RoamDataHandler.sharedChecked().requestDeviceApps(deviceId: device.id) {
                appLinks.append(app)
            }
        }
    } catch {
        debugErrors.append("Error getting device apps: \n\(error)")
    }

    let userDefaults = UserDefaults.standard.dictionaryRepresentation().mapValues { anyValue in
        switch anyValue {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let data as Data:
            return data.base64EncodedString()
        case let array as [Any]:
            return array.map { String(describing: $0) }.joined(separator: ", ")
        default:
            return String(describing: anyValue)
        }
    }

    let spaceOnDevice: Int64? = if userInitiated {
        getAvailableSpaceOnDevice()
    } else {
        nil
    }

    return DebugInfo(
        installationInfo: InstallationInfo(),
        userDefaults: userDefaults,
        spaceOnDevice: spaceOnDevice,
        devices: deviceDebugInfos,
        appLinks: appLinks,
        interfaces: localInterfaces,
        logs: entries,
        debugErrors: debugErrors,
        language: DebugLanguage(
            deviceLanguageCode: Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "none",
            translatedLanguageCode: String(localized: "locale.translated")
        ),
        faultingThreadBacktraces: faultingThreadBacktraces.isEmpty ? nil : faultingThreadBacktraces
    )
}

func getAvailableSpaceOnDevice() -> Int64? {
    // Use app's documents directory instead of root for sandbox compatibility
    guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        Log.backend.notice("Could not get documents directory")
        return nil
    }

    do {
        #if os(watchOS)
        // `volumeAvailableCapacity` is an `Int`, which is 32 bits on arm64_32
        // watches and wraps above 2 GB. The file system attribute is an
        // `NSNumber` and keeps all 64.
        let attributes = try FileManager.default.attributesOfFileSystem(
            forPath: documentsPath.path(percentEncoded: false))
        #else
        let values = try documentsPath.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        #endif

        // Try the preferred key first (iOS 11+, more accurate)
        #if os(watchOS)
        if let capacity = (attributes[.systemFreeSize] as? NSNumber)?.int64Value {
            Log.backend.notice("Available disk capacity: \(capacity, privacy: .public)")
            return capacity
        }
        #else
        if let capacity = values.volumeAvailableCapacityForImportantUsage {
            Log.backend.notice("Available capacity for important usage: \(capacity, privacy: .public)")
            return Int64(capacity)
        }
        #endif

        Log.backend.notice("No available capacity information found")
        return nil
    } catch {
        Log.backend.notice("Available capacity check errored: \(error, privacy: .public)")
        return nil
    }
}

func getLogEntries(limit: Int = 500000) throws -> [LogEntry] {
    let logStore = try OSLogStore(scope: .currentProcessIdentifier)
    let date = Date.now.addingTimeInterval(2)
    let position = logStore.position(date: date)

    var logEntries: [LogEntry] = []

    let sequence = try logStore.getEntries(with: .reverse, at: position, matching: NSPredicate(format: "subsystem != 'com.apple.network'"))
    for entry in sequence.prefix(limit) {
        if let logEntry = entry as? OSLogEntryLog, logEntries.count < limit {
            logEntries.append(LogEntry(entry: logEntry))
        }
    }

    return logEntries
}

/// This process's log, oldest first, with notes on where it came from.
///
/// `OSLogStore` yields nothing on some watches (seen on arm64_32 hardware from
/// 1.59 to 1.63, with no error surfaced), so an empty or failed read falls
/// back to this run's `FileLog`, which holds the app's own lines only.
func currentRunLogEntries() -> (entries: [LogEntry], notes: [String]) {
    var notes: [String] = []
    do {
        let entries = try getLogEntries()
        if !entries.isEmpty {
            return (entries, notes)
        }
        notes.append("OSLogStore returned no entries for this process; logs are from the file log.")
    } catch {
        notes.append("Error Getting Log Entries, logs are from the file log: \n\(error)")
    }

    let entries = FileLog.collectCurrentRun().map {
        LogEntry(fileEntry: $0, source: "file-log")
    }
    if entries.isEmpty {
        notes.append("The file log for this run is empty as well.")
    }
    return (entries, notes)
}
