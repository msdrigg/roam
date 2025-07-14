import MetricKit
import Foundation
import OSLog

struct DiagnosticsRequest: Codable, Sendable {
    let userId: String
    let metricsPayloads: [String]
    let diagnostics: DebugInfo
    let installationInfo: InstallationInfo
}

final class RoamMetricManager: NSObject, MXMetricManagerSubscriber, Sendable {
    override init() {
        super.init()
        MXMetricManager.shared.add(self)
        Task {
            await uploadCachedDiagnostics()
        }
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payload: [MXDiagnosticPayload]) {
        Log.backend.notice("Getting \(payload.count, privacy: .public) payloads in metric manager")
        if payload.contains(where: { payload in
            payload.crashDiagnostics?.isEmpty == false
        }) {
            let payloadData = payload.filter { $0.crashDiagnostics?.isEmpty == false }.map{ $0.jsonRepresentation() }
            Log.backend.notice("Sending \(payloadData.count, privacy: .public) crash diagnostics reports...")
            Task {
                await saveMetricKitDiagnostics(payloadData)
            }
        }
    }

    private func saveMetricKitDiagnostics(_ diagnostics: [Data]) async {
        let metricsPayloads = diagnostics.compactMap { data in
            String(data: data, encoding: .utf8)
        }

        let diagnosticsRequest = DiagnosticsRequest(
            userId: getSystemInstallID(),
            metricsPayloads: metricsPayloads,
            diagnostics: await getDebugInfo(),
            installationInfo: InstallationInfo()
        )

        do {
            let responseCode = try await uploadDiagnosticsV2(diagnosticsRequest)
            Log.backend.notice("Send diagnostics successfully with code \(responseCode, privacy: .public)")
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

            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.msdrigg.roam") else {
                Log.backend.error("Failed to get app group container URL")
                return
            }

            let diagnosticsDir = containerURL.appendingPathComponent("diagnostics", isDirectory: true)
            try FileManager.default.createDirectory(at: diagnosticsDir, withIntermediateDirectories: true)

            let dateFormatter = ISO8601DateFormatter()
            let dateString = dateFormatter.string(from: Date())
            let filename = "diagnostics_\(dateString).json"
            let fileURL = diagnosticsDir.appendingPathComponent(filename, isDirectory: false)
            try codedReport.write(to: fileURL)

            Log.backend.notice("Saved diagnostics to \(fileURL.path, privacy: .public)")
        } catch {
            Log.backend.error("Failed to save diagnostics: \(error, privacy: .public)")
        }
    }

    private func uploadCachedDiagnostics() async {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.msdrigg.roam") else {
            Log.backend.error("Failed to get app group container URL for cached diagnostics")
            return
        }

        let diagnosticsDir = containerURL.appendingPathComponent("diagnostics")

        guard FileManager.default.fileExists(atPath: diagnosticsDir.path) else {
            Log.backend.notice("No diagnostics directory found")
            return
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: diagnosticsDir, includingPropertiesForKeys: nil)
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
                            Log.backend.notice("Removed corrupted diagnostic file: \(fileURL.lastPathComponent, privacy: .public)")
                        } catch {
                            Log.backend.error("Failed to remove corrupted file: \(error, privacy: .public)")
                        }
                        continue
                    }

                    let statusCode = try await uploadDiagnosticsV2(diagnosticsRequest)

                    try FileManager.default.removeItem(at: fileURL)
                    fileCount -= 1
                    Log.backend.notice("Successfully upload attempted with code \(statusCode, privacy: .public) and removed cached diagnostic file: \(fileURL.lastPathComponent, privacy: .public)")
                } catch {
                    Log.backend.error("Failed to process cached diagnostic file \(fileURL.lastPathComponent, privacy: .public): \(error, privacy: .public)")

                    // Clean up old files if directory has too many files
                    if fileCount > 10 {
                        let calendar = Calendar.current
                        let thirtyOneDaysAgo = calendar.date(byAdding: .day, value: -31, to: Date()) ?? Date()

                        do {
                            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                            if let creationDate = attributes[.creationDate] as? Date,
                               creationDate < thirtyOneDaysAgo {
                                try FileManager.default.removeItem(at: fileURL)
                                fileCount -= 1
                                Log.backend.notice("Removed old diagnostic file older than 31 days: \(fileURL.lastPathComponent, privacy: .public)")
                            }
                        } catch {
                            Log.backend.error("Failed to check or remove old diagnostic file: \(error, privacy: .public)")
                        }
                    }
                }
            }
        } catch {
            Log.backend.error("Failed to read diagnostics directory: \(error, privacy: .public)")
        }
    }
}

private let globalBackendURL = "https://backend.roam.msd3.io"

private func getAPIKey() -> String? {
    let apiKey = Bundle.main.infoDictionary?["BACKEND_API_KEY"] as? String
    Log.backend.notice("Got api key \(apiKey ?? "--", privacy: .public)")
    return apiKey
}

// Throws on connection error, returns status code for any error. Logs response
private func uploadDiagnosticsV2(_ request: DiagnosticsRequest) async throws -> Int {
    guard let url = URL(string: "\(globalBackendURL)/diagnostics") else {
        throw URLError(.badURL)
    }

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.addValue(getAPIKey() ?? "", forHTTPHeaderField: "x-api-key")
    urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

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

    let (data, response) = try await URLSession.shared.data(for: urlRequest)

    guard let httpResponse = response as? HTTPURLResponse else {
        Log.backend.error("Received non-http response \(String(describing: response), privacy: .public)")
        throw URLError(.badServerResponse)
    }

    let statusCode = httpResponse.statusCode

    if let responseData = String(data: data, encoding: .utf8) {
        if statusCode == 200 {
            Log.backend.notice("Successfully uploaded diagnostics: \(responseData, privacy: .public)")
        } else {
            Log.backend.error("Failed to upload diagnostics with status \(statusCode, privacy: .public): \(responseData, privacy: .public)")
        }
    } else {
        Log.backend.notice("Diagnostics upload response could not be converted to String, status: \(statusCode, privacy: .public)")
    }

    return statusCode
}
