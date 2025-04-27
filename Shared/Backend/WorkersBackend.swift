import Foundation
import SwiftUI
import CoreTransferable
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

public struct AttachmentDownload: Decodable, Sendable {
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

#if !os(watchOS)
extension AttachmentUpload: FileDocument {
    public init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.filename = "Unknown" // No way to get filename from FileDocument
        self.data = fileData
        self.contentType = configuration.contentType.preferredMIMEType ?? "application/octet-stream"
        self.id = UUID().uuidString
        self.pairedMessages = []
    }
    public static let readableContentTypes: [UTType] = [.data, .pdf, .png, .image, .jpeg, .json, .text, .movie, .archive]

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif

extension AttachmentUpload: Transferable {
    // MARK: - Transferable Conformance
    public typealias Representation = FileRepresentation<AttachmentUpload>
    static public var transferRepresentation: FileRepresentation<AttachmentUpload> {
        FileRepresentation(exportedContentType: UTType.data, shouldAllowToOpenInPlace: true) { (attachment: AttachmentUpload) in
            SentTransferredFile(try attachment.writeToTemporaryFile())
        }
    }
}

extension AttachmentUpload {
    func writeToTemporaryFile() throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: tempURL)
        return tempURL
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
    let attachment: AttachmentUpload?
    let nonce: String?
}

public struct MessageModelResponse: Decodable, Sendable {
    let id: String
    let message: String
    let author: Message.AuthorType
    let nonce: String?
    let attachments: [AttachmentDownload]?

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

        let attachmentsData: [AttachmentDownload]?
        if let attachmentsArray = try container.decodeIfPresent([AttachmentDownload].self, forKey: .attachments) {
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

public func sendMessageDirect(message: String?, attachment: AttachmentUpload?) async -> Result<MessageModelResponse, UploadError> {
    guard let url = URL(string: "\(globalBackendURL)/v2/new-message") else {
        return .failure(.failed(.invalidURL))
    }

    let userId = getSystemInstallID()
    Log.backend.notice("Sending message to backend \(userId, privacy: .public)")

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue(getAPIKey() ?? "", forHTTPHeaderField: "x-api-key")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let messageRequest = MessageRequest(
        content: message ?? "",
        userId: userId,
        installationInfo: InstallationInfo(),
        attachment: attachment,
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
