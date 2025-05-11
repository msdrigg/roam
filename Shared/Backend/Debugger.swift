import Foundation
import os
import OSLog
import SwiftData

struct DebugError: Error {
    let message: String
}

struct BadResponseError: Error {
    let message: String
}

struct LogEntry: Encodable {
    let message: String
    let timestamp: Date
    let level: String?
    let category: String?
    let subsystem: String?

    init(entry: OSLogEntry) {
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
}

struct ResponseData: Encodable {
    let headers: [String: String]
    let statusCode: Int
    let data: String
}

struct DeviceDebugInfo: Encodable {
    let device: DeviceAppEntity
    let successResponse: ResponseData?
    let errorResponse: String?
}

public struct InstallationInfo: Encodable, Sendable {
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

public struct DebugLanguage: Encodable, Sendable {
    let deviceLanguageCode: String
    let translatedLanguageCode: String
}

public struct DebugInfo: Encodable, Sendable {
    let installationInfo: InstallationInfo
    let devices: [DeviceDebugInfo]
    let appLinks: [AppLinkAppEntity]
    let interfaces: [Addressed4NetworkInterface]
    var logs: [LogEntry]
    let debugErrors: [String]
    let language: DebugLanguage
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

func getDebugInfo() async -> DebugInfo {
    var debugErrors: [String] = []
    var entries: [LogEntry] = []
    do {
        entries = try getLogEntries()
    } catch {
        debugErrors.append("Error Getting Log Entries: \n\(error)")
    }
    Log.backend.info("Got \(entries.count) log entries")

    var devices: [DeviceAppEntity] = []
    do {
        devices = try await RoamDataHandler().allDeviceEntitiesIncludingDeleted()
    } catch {
        debugErrors.append("Error Getting Devices: \n\(error)")
    }
    var deviceDebugInfos: [DeviceDebugInfo] = []

    for device in devices {
        do {
            let deviceInfoURL = "\(device.location)query/device-info"
            guard let url = URL(string: deviceInfoURL) else {
                throw DebugError(message: "Bad URL \(deviceInfoURL)")
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 1.5
            request.httpMethod = "GET"

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                guard let dataString = String(data: data, encoding: .utf8) else {
                    throw BadResponseError(message: "Nonutf8 response from /query/device-info")
                }

                var headers: [String: String] = [:]

                for (key, value) in httpResponse.allHeaderFields {
                    if let keyString = key as? String, let valueString = value as? String {
                        headers[keyString] = valueString
                    }
                }
                let responseData = ResponseData(headers: headers, statusCode: statusCode, data: dataString)
                deviceDebugInfos.append(DeviceDebugInfo(
                    device: device,
                    successResponse: responseData,
                    errorResponse: nil
                ))
            } else {
                throw BadResponseError(
                    message: "Got non-http response trying to query device info \(String(describing: response))"
                )
            }
        } catch {
            deviceDebugInfos.append(DeviceDebugInfo(device: device, successResponse: nil, errorResponse: "\(error)"))
        }
    }

    let localInterfaces = await allAddressedInterfaces()

    var appLinks: [AppLinkAppEntity] = []
    do {
        appLinks = try await RoamDataHandler().allAppEntities()
    } catch {
        debugErrors.append("Error Getting AppLinks: \n\(error)")
    }

    return DebugInfo(
        installationInfo: InstallationInfo(),
        devices: deviceDebugInfos,
        appLinks: appLinks,
        interfaces: localInterfaces,
        logs: entries,
        debugErrors: debugErrors,
        language: DebugLanguage(
            deviceLanguageCode: Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "none",
            translatedLanguageCode: String(localized: "locale.translated")
        )
    )
}

func getLogEntries(limit: Int = 500000) throws -> [LogEntry] {
    let logStore = try OSLogStore(scope: .currentProcessIdentifier)
    let date = Date.now.addingTimeInterval(2)
    let position = logStore.position(date: date)

    var logEntries: [LogEntry] = []

    do {
        let sequence = try logStore.getEntries(with: .reverse, at: position, matching: NSPredicate(format: "subsystem != 'com.apple.network'"))
        for entry in sequence.prefix(limit) {
            if let logEntry = entry as? OSLogEntryLog, logEntries.count < limit {
                logEntries.append(LogEntry(entry: logEntry))
            }
        }
    } catch {
        os_log(.error, "Error fetching log entries: \(error)")
    }

    return logEntries
}
