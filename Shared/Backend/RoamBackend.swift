import Foundation
import SwiftUI
import OSLog
import SwiftData
import UniformTypeIdentifiers

private let globalBackendURL = "https://backend.roam.msd3.io"
// private let globalBackendURL = "http://localhost:8080"

private func getAPIKey() -> String? {
    let apiKey = Bundle.main.infoDictionary?["BACKEND_API_KEY"] as? String

    Log.backend.notice("Got api key \(apiKey ?? "--", privacy: .public)")
    return apiKey
}

public func getSystemInstallID() -> String {
    var ids: [String] = []
    for _ in 0 ... 2 {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let randomLetters = String((0 ..< 3).map { _ in letters.randomElement()! })
        ids.append(randomLetters)
    }
    let defaultVar = ids.joined(separator: "-")

    return UserDefaultInfo(key: "system-install-id", defaultValue: defaultVar).get()
}

private struct UserDefaultInfo<Value> {
    var key: String
    var defaultValue: Value
}

private extension UserDefaultInfo {
    func get() -> Value {
        guard let existingValue = UserDefaults.standard.object(forKey: key) as? Value else {
            set(defaultValue)
            return defaultValue
        }
        return existingValue
    }

    func set(_ value: Value) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

public struct WorkersAttachmentDownload: Decodable, Sendable {
    let filename: String
    let data: Data
    let contentType: String
    let id: String

    enum CodingKeys: String, CodingKey {
        case filename = "filename"
        case data = "data"
        case contentType = "content_type"
        case id = "id"
    }
}

public struct WorkersAttachmentUpload: Encodable, Sendable {
    let filename: String
    let data: Data
    let contentType: String
    let id: String

    let pairedMessages: [String]

    enum CodingKeys: String, CodingKey {
        case filename = "filename"
        case data = "data"
        case contentType = "content_type"
        case pairedMessages = "paired_messages"
        case id = "id"
    }
}

struct APNSRequest: Encodable, Sendable {
    let apnsToken: String
    let userId: String
    let installationInfo: InstallationInfo
}

struct MessageRequest: Encodable, Sendable {
    let content: String
    let userId: String
    let installationInfo: InstallationInfo
    let attachment: WorkersAttachmentUpload?
    let nonce: String?
}

public struct MessageModelResponse: Decodable, Sendable {
    let id: String
    let message: String
    let author: Message.AuthorType
    let nonce: String?
    let attachments: [WorkersAttachmentDownload]?

    enum CodingKeys: String, CodingKey {
        case id
        case message = "content"
        case author
        case attachments
        case nonce
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        message = try container.decode(String.self, forKey: .message)

        let authorInfo = try container.nestedContainer(keyedBy: AuthorKeys.self, forKey: .author)
        let id = try authorInfo.decode(String.self, forKey: .id)
        author = id == "1229219148228460595" ? .me : .support

        let attachmentsData: [WorkersAttachmentDownload]?
        if let attachmentsArray = try container.decodeIfPresent([WorkersAttachmentDownload].self, forKey: .attachments) {
            attachmentsData = attachmentsArray
        } else {
            attachmentsData = nil
        }
        self.attachments = attachmentsData

        nonce = try container.decodeIfPresent(String.self, forKey: .nonce)
    }

    private enum AuthorKeys: String, CodingKey {
        case id
    }
}

struct MessagingUpdateResponse: Decodable, Sendable {
    let messages: [MessageModelResponse]
    let presence: PresenceInfo
}

struct PresenceInfo: Decodable, Sendable {
    let lastSupportTyping: Date?
    let lastSelfTyping: Date?

    enum CodingKeys: String, CodingKey {
        case lastSupportTyping = "last_support_typing"
        case lastSelfTyping = "last_self_typing"
    }
}

func getMessagingUpdates(after: String?) async throws -> MessagingUpdateResponse {
    let userId = getSystemInstallID()

    var url = "\(globalBackendURL)/updates/\(userId)"
    if let after {
        url = "\(url)?after=\(after)"
    }
    guard let url = URL(string: url) else {
        throw URLError(.badURL)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue(getAPIKey() ?? "", forHTTPHeaderField: "x-api-key")

    let (data, response) = try await URLSession.shared.data(for: request)
    let statusCode = if let httpResponse = response as? HTTPURLResponse {
        httpResponse.statusCode
    } else {
        -1
    }
    guard statusCode == 200 else {
        if let responseData = String(data: data, encoding: .utf8) {
            Log.backend.error("Received failed status code \(statusCode, privacy: .public) get messages response with data: \(responseData, privacy: .public)")
        } else {
            Log.backend.error("Received failed (\(statusCode, privacy: .public)) get messages response and data could not be converted to a String")
        }
        throw URLError(.badServerResponse)
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.dataDecodingStrategy = .base64
    let messages = try decoder.decode(MessagingUpdateResponse.self, from: data)
    Log.backend.notice("Got \(messages.messages, privacy: .public) updates from backend")
    return messages
}

public func sendTyping() async throws {
    let userId = getSystemInstallID()
    guard let url = URL(string: "\(globalBackendURL)/typing/\(userId)") else {
        throw URLError(.badURL)
    }

    Log.backend.notice("Sending typing to backend")

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue(getAPIKey() ?? "", forHTTPHeaderField: "x-api-key")

    let (data, response) = try await URLSession.shared.data(for: request)
    let statusCode = if let httpResponse = response as? HTTPURLResponse {
        httpResponse.statusCode
    } else {
        -1
    }
    guard statusCode == 200 else {
        if let responseData = String(data: data, encoding: .utf8) {
            Log.backend.error("Received failed status code \(statusCode, privacy: .public) typing response with data: \(responseData, privacy: .public)")
        } else {
            Log.backend.error("Received failed (\(statusCode, privacy: .public)) typing response and data could not be converted to a String")
        }
        throw URLError(.badServerResponse)
    }
}

public enum UploadError: Error {
    case retryable(any Error)
    case failed(MessageFailedError)
}

public enum MessageFailedError: Error, LocalizedError {
    case invalidURL
    case invalidJSON
    case badResponse(Int?)

    var errorDescription: String {
        switch self {
        case .invalidURL:
            return String(localized: "Failed to connect")
        case .invalidJSON:
            return String(localized: "Failed to send data")
        case .badResponse(let code):
            return String(localized: "Failed to send data: \(code ?? 0)")
        }
    }
}

public func uploadApnsToken(_ token: String) async throws {
    guard let url = URL(string: "\(globalBackendURL)/new-apns") else {
        throw UploadError.failed(.invalidURL)
    }

    Log.backend.notice("Uploading APNS to backend")
    let userId = getSystemInstallID()

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue(getAPIKey() ?? "", forHTTPHeaderField: "x-api-key")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let messageRequest = APNSRequest(
        apnsToken: token,
        userId: userId,
        installationInfo: InstallationInfo()
    )
    do {
        let jsonData = try JSONEncoder().encode(messageRequest)
        request.httpBody = jsonData
    } catch {
        throw UploadError.failed(.invalidJSON)
    }

    do {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            Log.backend.error("Received non-http response \(String(describing: response), privacy: .public)")
            throw UploadError.failed(.badResponse(nil))
        }
        guard httpResponse.statusCode == 200 else {
            if let responseData = String(data: data, encoding: .utf8) {
                Log.backend.error("Received failed \(httpResponse.statusCode, privacy: .public) new-apns response with data: \(responseData, privacy: .public)")
            } else {
                Log.backend.error("Received failed \(httpResponse.statusCode, privacy: .public) new-apns response and data could not be converted to a String")
            }
            throw UploadError.failed(.badResponse(httpResponse.statusCode))
        }
    } catch {
        throw UploadError.retryable(error)
    }
}

struct DiagnosticsRequest: Encodable {
    let userId: String
    let installationInfo: InstallationInfo
    let diagnostics: DebugInfo
    let metricsPayloads: [RoamMetricDiagnosticPayload]
}

struct RoamMetricDiagnosticPayload: Encodable {
    let cpuExceptionDiagnostics: [CPUExceptionDiagnostic]
    let diskWriteExceptionDiagnostics: [DiskWriteExceptionDiagnostic]
    let hangDiagnostics: [HangDiagnostic]
    let appLaunchDiagnostics: [AppLaunchDiagnostic]
    let crashDiagnostics: [CrashDiagnostic]
    let timeStampBegin: Date
    let timeStampEnd: Date

    struct MetaData: Encodable {
        let applicationBuildVersion: String
        let deviceType: String
        let isTestFlightApp: Bool
        let lowPowerModeEnabled: Bool
        let osVersion: String
        let platformArchitecture: String
        let regionFormat: String
        let pid: pid_t
    }

    struct SignpostRecord: Encodable {
        let beginTimeStamp: Date
        let category: String
        let duration: Measurement<UnitDuration>?
        let endTimeStamp: Date?
        let isInterval: Bool
        let name: String
        let subsystem: String
    }

    struct HangDiagnostic: Encodable {
        let hangDuration: Double
        let stackTrace: StackTrace?
        let metaData: MetaData
        let applicationVersion: String
        let signpostData: [SignpostRecord]
    }

    struct CrashDiagnostic: Encodable {
        var exceptionType: Int?
        var exceptionCode: Int?
        var signal: Int?
        var exceptionReason: CrashDiagnosticObjectiveCExceptionReason?
        var terminationReason: String?
        var virtualMemoryRegionInfo: String?
        let stackTrace: StackTrace?
        let metaData: MetaData
        let applicationVersion: String
        let signpostData: [SignpostRecord]

        struct CrashDiagnosticObjectiveCExceptionReason: Encodable {
            var arguments: [String]
            var className: String
            var composedMessage: String
            var exceptionName: String
            var exceptionType: String
            var formatString: String
        }
    }

    struct DiskWriteExceptionDiagnostic: Encodable {
        let totalWrites: Double
        let stackTrace: StackTrace?
        let metaData: MetaData
        let applicationVersion: String
        let signpostData: [SignpostRecord]
    }

    struct AppLaunchDiagnostic: Encodable {
        let launchDuration: Double
        let stackTrace: StackTrace?
        let metaData: MetaData
        let applicationVersion: String
        let signpostData: [SignpostRecord]
    }

    struct CPUExceptionDiagnostic: Encodable {
        let totalCPUTime: Double
        let totalSampledTime: Double
        let stackTrace: StackTrace?
        let metaData: MetaData
        let applicationVersion: String
        let signpostData: [SignpostRecord]
    }

    struct StackTrace: Codable {
        let callStackPerThread: Bool
        let callStacks: [CallStack]

        struct CallStack: Codable {
            let threadAttributed: Bool
            let callStackRootFrames: [Frame]

            struct Frame: Codable {
                let binaryUUID: String
                let offsetIntoBinaryTextSegment: Int
                let sampleCount: Int
                let binaryName: String
                let address: Int
                let subframes: [Frame]?
            }
        }
    }
}

func uploadDiagnosticsMessageV2(logs: DebugInfo, diagnostics: [RoamMetricDiagnosticPayload]) async throws {
    guard let url = URL(string: "\(globalBackendURL)/v2/upload-diagnostics") else {
        throw MessageFailedError.invalidURL
    }

    let userId = getSystemInstallID()
    Log.backend.notice("Sending diagnostics to backend \(userId, privacy: .public)")

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue(getAPIKey() ?? "", forHTTPHeaderField: "x-api-key")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let requestBody = DiagnosticsRequest(
        userId: userId,
        installationInfo: InstallationInfo(),
        diagnostics: logs,
        metricsPayloads: diagnostics
    )
    let encoder = JSONEncoder()
    encoder.dataEncodingStrategy = .base64
    encoder.dateEncodingStrategy = .iso8601
    do {
        let jsonData = try encoder.encode(requestBody)
        request.httpBody = jsonData
    } catch {
        throw MessageFailedError.invalidJSON
    }

    do {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            Log.backend.error("Received non-http response \(String(describing: response), privacy: .public)")
            throw MessageFailedError.badResponse(nil)
        }
        guard httpResponse.statusCode == 200 else {
            if let responseData = String(data: data, encoding: .utf8) {
                Log.backend.error("Received failed \(httpResponse.statusCode, privacy: .public) send-messages response with data: \(responseData, privacy: .public)")
            } else {
                Log.backend.error("Received failed \(httpResponse.statusCode, privacy: .public) send-messages response and data could not be converted to a String")
            }
            throw MessageFailedError.badResponse(httpResponse.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        let message = try decoder.decode(MessageModelResponse.self, from: data)
        Log.backend.notice("Sent message \(message.id, privacy: .public) to backend")
    } catch {
        Log.backend.error("Error uploading diagnostics \(error, privacy: .public)")
        throw error
    }
}

public func sendMessageDirect(message: String?, attachment: AttachmentUpload?, attachmentData: Data? = nil) async -> Result<MessageModelResponse, UploadError> {
    guard let url = URL(string: "\(globalBackendURL)/v2/new-message") else {
        return .failure(.failed(.invalidURL))
    }

    let userId = getSystemInstallID()
    Log.backend.notice("Sending message to backend \(userId, privacy: .public)")

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue(getAPIKey() ?? "", forHTTPHeaderField: "x-api-key")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    var workersAttachment: WorkersAttachmentUpload?
    do {
        if let attachment {
            let data = try attachmentData ?? loadAttachmentFromDisk(hash: attachment.dataHash, filename: attachment.filename)
            workersAttachment = WorkersAttachmentUpload(
                filename: attachment.filename,
                data: data,
                contentType: attachment.contentType,
                id: attachment.id,
                pairedMessages: attachment.pairedMessages
            )
        }
    } catch {
        Log.backend.error("Error loading attachment from disk: \(error, privacy: .public)")
    }

    let messageRequest = MessageRequest(
        content: message ?? "",
        userId: userId,
        installationInfo: InstallationInfo(),
        attachment: workersAttachment,
        nonce: nil
    )
    let encoder = JSONEncoder()
    encoder.dataEncodingStrategy = .base64
    do {
        let jsonData = try encoder.encode(messageRequest)
        request.httpBody = jsonData
    } catch {
        return .failure(.failed(.invalidJSON))
    }

    do {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            Log.backend.error("Received non-http response \(String(describing: response), privacy: .public)")
            return .failure(.failed(.badResponse(nil)))
        }
        guard httpResponse.statusCode == 200 else {
            if let responseData = String(data: data, encoding: .utf8) {
                Log.backend.error("Received failed \(httpResponse.statusCode, privacy: .public) send-messages response with data: \(responseData, privacy: .public)")
            } else {
                Log.backend.error("Received failed \(httpResponse.statusCode, privacy: .public) send-messages response and data could not be converted to a String")
            }
            return .failure(.failed(.badResponse(httpResponse.statusCode)))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        let message = try decoder.decode(MessageModelResponse.self, from: data)
        Log.backend.notice("Sent message \(message.id, privacy: .public) to backend")
        return .success(message)
    } catch {
        return .failure(.retryable(error))
    }
}
