import Foundation
import MetricKit
import OSLog

struct DiagnosticsRequest: Codable, Sendable {
    let userId: String
    let metricsPayloads: [String]
    let diagnostics: DebugInfo
    let installationInfo: InstallationInfo
}

/// `MXDiagnosticPayload.jsonRepresentation()` omits `terminationReason` and
/// `virtualMemoryRegionInfo`, which are what name the policy behind an
/// `EXC_CRASH` / `SIGKILL` kill.
///
/// Read them off the diagnostic objects and merge them into
/// `diagnosticMetaData`, where the report generator looks. Falls back to the
/// unmodified representation if the shape is unexpected.
private func jsonRepresentationIncludingTerminationFields(_ payload: MXDiagnosticPayload) -> Data {
    let data = payload.jsonRepresentation()

    guard let crashDiagnostics = payload.crashDiagnostics, !crashDiagnostics.isEmpty,
        var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        var encodedCrashes = root["crashDiagnostics"] as? [[String: Any]],
        encodedCrashes.count == crashDiagnostics.count
    else {
        Log.backend.notice("Uploading MetricKit payload without merged termination fields")
        return data
    }

    var addedField = false
    for (index, crashDiagnostic) in crashDiagnostics.enumerated() {
        var encodedCrash = encodedCrashes[index]
        var metaData = encodedCrash["diagnosticMetaData"] as? [String: Any] ?? [:]

        if let terminationReason = crashDiagnostic.terminationReason,
            metaData["terminationReason"] == nil
        {
            metaData["terminationReason"] = terminationReason
            addedField = true
        }

        if let regionInfo = crashDiagnostic.virtualMemoryRegionInfo,
            metaData["virtualMemoryRegionInfo"] == nil
        {
            metaData["virtualMemoryRegionInfo"] = regionInfo
            addedField = true
        }

        encodedCrash["diagnosticMetaData"] = metaData
        encodedCrashes[index] = encodedCrash
    }

    guard addedField else { return data }
    root["crashDiagnostics"] = encodedCrashes

    guard let merged = try? JSONSerialization.data(withJSONObject: root) else {
        Log.backend.error("Failed to re-encode MetricKit payload with termination fields")
        return data
    }

    Log.backend.notice("Merged MetricKit termination fields into crash payload")
    return merged
}

final class RoamMetricManager: NSObject, MXMetricManagerSubscriber, Sendable {
    /// The process's subscriber. Construct no others.
    ///
    /// SwiftUI rebuilds the `App` value on every invalidation, so an instance
    /// stored in a property of `RoamApp` is re-created each time, and each
    /// re-creation is an `MXMetricManager` subscribe plus the discarded
    /// instance's unsubscribe. A runaway scene update ran that ~96 times.
    static let shared = RoamMetricManager()

    override init() {
        super.init()
        MXMetricManager.shared.add(self)
        // Background priority on purpose: nothing on screen is waiting for a
        // crash report, and a launch-time upload that outranks the first
        // message fetch is exactly how a slow link makes the app feel dead.
        Task(priority: .utility) {
            await uploadCachedDiagnostics()
            // Widget extensions cannot reach the backend themselves, so any
            // fatal error one logged is waiting in the shared app group.
            await DeferredBackendErrors.drain()
        }
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payload: [MXDiagnosticPayload]) {
        Log.backend.notice("Getting \(payload.count, privacy: .public) payloads in metric manager")
        let crashPayloads = payload.filter { $0.crashDiagnostics?.isEmpty == false }
        if !crashPayloads.isEmpty {
            let payloadData = crashPayloads.map {
                jsonRepresentationIncludingTerminationFields($0)
            }
            // The window the crashes happened in - always an earlier launch
            // than this one, since MetricKit only delivers on the next start.
            // It selects which run's logs get uploaded (see `getDebugInfo`).
            let crashWindow = crashPayloads.reduce(nil) { (window: DateInterval?, payload) in
                let payloadWindow = DateInterval(
                    start: payload.timeStampBegin,
                    end: max(payload.timeStampEnd, payload.timeStampBegin))
                guard let window else { return payloadWindow }
                return DateInterval(
                    start: min(window.start, payloadWindow.start),
                    end: max(window.end, payloadWindow.end))
            }
            Log.backend.notice(
                "Sending \(payloadData.count, privacy: .public) crash diagnostics reports for window \(String(describing: crashWindow), privacy: .public)..."
            )
            Task(priority: .utility) {
                await saveMetricKitDiagnostics(payloadData, crashWindow: crashWindow)
            }
        }
    }

    private func saveMetricKitDiagnostics(_ diagnostics: [Data], crashWindow: DateInterval?) async {
        let metricsPayloads = diagnostics.compactMap { data in
            String(data: data, encoding: .utf8)
        }

        let diagnosticsRequest = DiagnosticsRequest(
            userId: getSystemInstallID(),
            metricsPayloads: metricsPayloads,
            diagnostics: await getDebugInfo(crashWindow: crashWindow),
            installationInfo: InstallationInfo()
        )

        do {
            let responseCode = try await uploadDiagnosticsV2(diagnosticsRequest)
            Log.backend.notice(
                "Send diagnostics successfully with code \(responseCode, privacy: .public)")
            return
        } catch {
            Log.backend.notice("Failed to send diagnostics, caching: \(error, privacy: .public)")
        }

        Log.backend.notice("Saving diagnostics reports...")
        do {
            let encoder = JSONEncoder()
            encoder.dataEncodingStrategy = .base64
            encoder.dateEncodingStrategy = .iso8601
            let codedReport = try encoder.encode(diagnosticsRequest)

            guard let containerURL = roamAppGroupContainerURL() else {
                Log.backend.error("Failed to get app group container URL")
                return
            }

            let diagnosticsDir = containerURL.appendingPathComponent(
                "diagnostics", isDirectory: true)
            try FileManager.default.createDirectory(
                at: diagnosticsDir, withIntermediateDirectories: true)

            let dateFormatter = ISO8601DateFormatter()
            let dateString = dateFormatter.string(from: Date())
            let filename = "diagnostics_\(dateString).json"
            let fileURL = diagnosticsDir.appendingPathComponent(filename, isDirectory: false)
            try codedReport.write(to: fileURL)

            Log.backend.notice("Saved diagnostics to \(fileURL.path, privacy: .public)")
        } catch {
            Log.backend.error("Failed to save diagnostics: \(error, privacy: .public)")
        }
        await uploadCachedDiagnostics()
    }

    private func uploadCachedDiagnostics() async {
        guard let containerURL = roamAppGroupContainerURL() else {
            Log.backend.error("Failed to get app group container URL for cached diagnostics")
            return
        }

        let diagnosticsDir = containerURL.appendingPathComponent("diagnostics")

        guard FileManager.default.fileExists(atPath: diagnosticsDir.path) else {
            Log.backend.notice("No diagnostics directory found")
            return
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: diagnosticsDir, includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "json" }
            var fileCount = files.count

            Log.backend.notice("Found \(files.count, privacy: .public) cached diagnostic files")

            for fileURL in files {
                do {
                    let diagnosticsRequest: DiagnosticsRequest

                    do {
                        let data = try Data(contentsOf: fileURL)
                        let decoder = JSONDecoder()
                        decoder.dataDecodingStrategy = .base64
                        decoder.dateDecodingStrategy = .iso8601
                        diagnosticsRequest = try decoder.decode(DiagnosticsRequest.self, from: data)
                    } catch {
                        do {
                            try FileManager.default.removeItem(at: fileURL)
                            fileCount -= 1
                            Log.backend.notice(
                                "Removed corrupted diagnostic file: \(fileURL.lastPathComponent, privacy: .public)"
                            )
                        } catch {
                            Log.backend.error(
                                "Failed to remove corrupted file: \(error, privacy: .public)")
                        }
                        continue
                    }

                    let statusCode = try await uploadDiagnosticsV2(diagnosticsRequest)

                    // Only a delivered payload may be dropped. This used to
                    // remove the file for any status, so a 401, a 429 or a 500
                    // discarded the crash report instead of leaving it to be
                    // retried on the next launch.
                    guard statusCode == 200 else {
                        Log.backend.error(
                            "Keeping cached diagnostic file after status \(statusCode, privacy: .public): \(fileURL.lastPathComponent, privacy: .public)"
                        )
                        continue
                    }

                    try FileManager.default.removeItem(at: fileURL)
                    fileCount -= 1
                    Log.backend.notice(
                        "Uploaded and removed cached diagnostic file: \(fileURL.lastPathComponent, privacy: .public)"
                    )
                } catch {
                    Log.backend.error(
                        "Failed to process cached diagnostic file \(fileURL.lastPathComponent, privacy: .public): \(error, privacy: .public)"
                    )

                    // Clean up old files if directory has too many files
                    if fileCount > 10 {
                        let calendar = Calendar.current
                        let thirtyOneDaysAgo =
                            calendar.date(byAdding: .day, value: -31, to: Date()) ?? Date()

                        do {
                            let attributes = try FileManager.default.attributesOfItem(
                                atPath: fileURL.path)
                            if let creationDate = attributes[.creationDate] as? Date,
                                creationDate < thirtyOneDaysAgo
                            {
                                try FileManager.default.removeItem(at: fileURL)
                                fileCount -= 1
                                Log.backend.notice(
                                    "Removed old diagnostic file older than 31 days: \(fileURL.lastPathComponent, privacy: .public)"
                                )
                            }
                        } catch {
                            Log.backend.error(
                                "Failed to check or remove old diagnostic file: \(error, privacy: .public)"
                            )
                        }
                    }
                }
            }
        } catch {
            Log.backend.error("Failed to read diagnostics directory: \(error, privacy: .public)")
        }
    }
}


// Throws on connection error, returns status code for any error. Logs response
private func uploadDiagnosticsV2(_ request: DiagnosticsRequest) async throws -> Int {
    guard let url = URL(string: "\(globalBackendURL)/v2/upload-diagnostics") else {
        throw URLError(.badURL)
    }

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.timeoutInterval = BackendTimeout.send
    // A crash report is worth uploading but nobody is waiting on it, so tell
    // the system it may yield the radio to anything the user is actually doing.
    // This is a courtesy, not a fix for anything: the reason messages once
    // queued behind diagnostics was a lock in our own outbox, not contention on
    // the connection.
    urlRequest.networkServiceType = .background

    let encoder = JSONEncoder()
    encoder.dataEncodingStrategy = .base64
    encoder.dateEncodingStrategy = .iso8601

    do {
        let jsonData = try encoder.encode(request)
        urlRequest.httpBody = jsonData
    } catch {
        Log.backend.error("Failed to encode diagnostics request: \(error, privacy: .public)")
        throw error
    }

    let (data, response) = try await BackendAuth.shared.authorizedData(for: urlRequest)

    guard let httpResponse = response as? HTTPURLResponse else {
        Log.backend.error(
            "Received non-http response \(String(describing: response), privacy: .public)")
        throw URLError(.badServerResponse)
    }

    let statusCode = httpResponse.statusCode

    if let responseData = String(data: data, encoding: .utf8) {
        if statusCode == 200 {
            Log.backend.notice(
                "Successfully uploaded diagnostics: \(responseData, privacy: .public)")
        } else {
            Log.backend.error(
                "Failed to upload diagnostics with status \(statusCode, privacy: .public): \(responseData, privacy: .public)"
            )
        }
    } else {
        Log.backend.notice(
            "Diagnostics upload response could not be converted to String, status: \(statusCode, privacy: .public)"
        )
    }

    return statusCode
}
