import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

let globalBackendURL = "https://backend.roam.msd3.io"
// let globalBackendURL = "http://localhost:8080"

/// How long a backend request may make no progress before it is abandoned.
///
/// `URLRequest.timeoutInterval` is an idle timer rather than a wall clock, so
/// these are budgets for "the link has gone quiet", not for "this is slow".
/// A megabyte crawling uphill on airplane wifi keeps resetting the timer and
/// is allowed to finish; a request that has genuinely stalled gives up and
/// lets the caller retry instead of holding a slot indefinitely. They are
/// spelled out here rather than left to `URLSession.shared`'s 60 second
/// default so a future change to the shared session cannot silently move them.
enum BackendTimeout {
    /// Sends carry attachments, so they get the most patience.
    static let send: TimeInterval = 60
    /// Polling for new messages; the next poll is along shortly either way.
    static let poll: TimeInterval = 20
    /// A typing indicator that arrives late is worse than one that never does.
    static let ephemeral: TimeInterval = 10
}

/// The longest message body Discord will accept.
///
/// The backend forwards `content` and every element of `paired_messages`
/// straight through as Discord message bodies, so this ceiling is ours to
/// respect. Exceeding it is not a slow send or a flaky one: Discord answers
/// `50035 BASE_TYPE_MAX_LENGTH` and the backend turns that into a 500, on every
/// attempt, forever. A message that long can never be delivered, so it must
/// never be put on the wire in the first place.
public let discordMessageContentLimit = 4000

/// Trims `text` to something Discord will accept.
///
/// The tail is what gets cut because these bodies lead with the part a human
/// reads first. Anything dropped is already in the attachment that accompanies
/// the message, so the note points there rather than pretending nothing is
/// missing.
public func clampToDiscordLimit(_ text: String, label: String) -> String {
    guard text.count > discordMessageContentLimit else {
        return text
    }
    let notice = "\n\n… truncated, see the attached file for the rest."
    let keep = discordMessageContentLimit - notice.count
    Log.backend.notice(
        "Truncating \(label, privacy: .public) from \(text.count, privacy: .public) to \(discordMessageContentLimit, privacy: .public) characters for Discord"
    )
    return String(text.prefix(keep)) + notice
}

public func getSystemInstallID() -> String {
    var ids: [String] = []
    for _ in 0...2 {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let randomLetters = String((0..<3).map { _ in letters.randomElement()! })
        ids.append(randomLetters)
    }
    let defaultVar = ids.joined(separator: "-")

    return UserDefaultInfo(key: "system-install-id", defaultValue: defaultVar).get()
}

/// Adopts the install id the backend considers authoritative.
///
/// An attested key keeps the id it registered with, so when a reinstall clears
/// `UserDefaults` the backend hands back the original id and the support
/// conversation follows the device instead of starting over.
public func adoptUserID(_ userId: String) {
    guard !userId.isEmpty, userId != getSystemInstallID() else {
        return
    }
    Log.backend.notice("Adopting install id \(userId, privacy: .public) from the backend")
    UserDefaults.standard.set(userId, forKey: "system-install-id")
}

private struct UserDefaultInfo<Value> {
    var key: String
    var defaultValue: Value
}

extension UserDefaultInfo {
    fileprivate func get() -> Value {
        guard let existingValue = UserDefaults.standard.object(forKey: key) as? Value else {
            set(defaultValue)
            return defaultValue
        }
        return existingValue
    }

    fileprivate func set(_ value: Value) {
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
    let aiMessage: Bool
    let humanSupportMessage: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case message = "content"
        case author
        case attachments
        case nonce
        case aiMessage = "ai_message"
        case humanSupportMessage = "human_support_message"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        message = try container.decode(String.self, forKey: .message)

        let authorInfo = try container.nestedContainer(keyedBy: AuthorKeys.self, forKey: .author)
        let id = try authorInfo.decode(String.self, forKey: .id)
        author = id == "1229219148228460595" ? .me : .support

        let attachmentsData: [WorkersAttachmentDownload]?
        if let attachmentsArray = try container.decodeIfPresent(
            [WorkersAttachmentDownload].self, forKey: .attachments)
        {
            attachmentsData = attachmentsArray
        } else {
            attachmentsData = nil
        }
        self.attachments = attachmentsData

        nonce = try container.decodeIfPresent(String.self, forKey: .nonce)
        aiMessage = try container.decodeIfPresent(Bool.self, forKey: .aiMessage) ?? false
        humanSupportMessage =
            try container.decodeIfPresent(Bool.self, forKey: .humanSupportMessage) ?? false
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
    request.timeoutInterval = BackendTimeout.poll

    let (data, response) = try await BackendAuth.shared.authorizedData(for: request)
    let statusCode =
        if let httpResponse = response as? HTTPURLResponse {
            httpResponse.statusCode
        } else {
            -1
        }
    guard statusCode == 200 else {
        if let responseData = String(data: data, encoding: .utf8) {
            Log.backend.error(
                "Received failed status code \(statusCode, privacy: .public) get messages response with data: \(responseData, privacy: .public)"
            )
        } else {
            Log.backend.error(
                "Received failed (\(statusCode, privacy: .public)) get messages response and data could not be converted to a String"
            )
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
    request.timeoutInterval = BackendTimeout.ephemeral

    let (data, response) = try await BackendAuth.shared.authorizedData(for: request)
    let statusCode =
        if let httpResponse = response as? HTTPURLResponse {
            httpResponse.statusCode
        } else {
            -1
        }
    guard statusCode == 200 else {
        if let responseData = String(data: data, encoding: .utf8) {
            Log.backend.error(
                "Received failed status code \(statusCode, privacy: .public) typing response with data: \(responseData, privacy: .public)"
            )
        } else {
            Log.backend.error(
                "Received failed (\(statusCode, privacy: .public)) typing response and data could not be converted to a String"
            )
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
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = BackendTimeout.poll

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
        let (data, response) = try await BackendAuth.shared.authorizedData(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            Log.backend.error(
                "Received non-http response \(String(describing: response), privacy: .public)")
            throw UploadError.failed(.badResponse(nil))
        }
        guard httpResponse.statusCode == 200 else {
            if let responseData = String(data: data, encoding: .utf8) {
                Log.backend.error(
                    "Received failed \(httpResponse.statusCode, privacy: .public) new-apns response with data: \(responseData, privacy: .public)"
                )
            } else {
                Log.backend.error(
                    "Received failed \(httpResponse.statusCode, privacy: .public) new-apns response and data could not be converted to a String"
                )
            }
            throw UploadError.failed(.badResponse(httpResponse.statusCode))
        }
    } catch {
        throw UploadError.retryable(error)
    }
}

public func sendMessageDirect(
    message: String?,
    attachment: AttachmentUpload?,
    attachmentData: Data? = nil,
    nonce: String? = nil
) async -> Result<MessageModelResponse, UploadError> {
    guard let url = URL(string: "\(globalBackendURL)/v2/new-message") else {
        Log.backend.error(
            "Unable to build send-message URL from backend URL \(globalBackendURL, privacy: .public)"
        )
        return .failure(.failed(.invalidURL))
    }

    let userId = getSystemInstallID()
    let messageContent = message ?? ""
    let attachmentSummary =
        attachment.map { attachment in
            "\(attachment.filename) id=\(attachment.id) hash=\(attachment.dataHash) bytes=\(attachment.dataSize) type=\(attachment.contentType) pairedMessages=\(attachment.pairedMessages.count)"
        } ?? "none"
    Log.backend.notice(
        "Preparing send-message request user=\(userId, privacy: .public) nonce=\(nonce ?? "--", privacy: .public) contentBytes=\(messageContent.utf8.count, privacy: .public) attachment=\(attachmentSummary, privacy: .public)"
    )

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = BackendTimeout.send

    var workersAttachment: WorkersAttachmentUpload?
    do {
        if let attachment {
            Log.backend.notice(
                "Loading send-message attachment from disk filename=\(attachment.filename, privacy: .public) hash=\(attachment.dataHash, privacy: .public)"
            )
            let data =
                try attachmentData
                ?? loadAttachmentFromDisk(hash: attachment.dataHash, filename: attachment.filename)
            Log.backend.notice(
                "Loaded send-message attachment filename=\(attachment.filename, privacy: .public) encodedBytes=\(data.count, privacy: .public)"
            )
            workersAttachment = WorkersAttachmentUpload(
                filename: attachment.filename,
                data: data,
                contentType: attachment.contentType,
                id: attachment.id,
                // The backend posts each paired message as its own Discord
                // message *before* it uploads the file, so one over-length
                // entry here fails the whole send and the attachment never
                // leaves the device. Clamping at the edge means no caller can
                // reintroduce that by growing a summary string.
                pairedMessages: attachment.pairedMessages.map {
                    clampToDiscordLimit($0, label: "paired message")
                }
            )
        }
    } catch {
        Log.backend.error(
            "Error loading send-message attachment from disk filename=\(attachment?.filename ?? "--", privacy: .public) hash=\(attachment?.dataHash ?? "--", privacy: .public): \(error, privacy: .public)"
        )
    }

    let messageRequest = MessageRequest(
        content: clampToDiscordLimit(messageContent, label: "message content"),
        userId: userId,
        installationInfo: InstallationInfo(),
        attachment: workersAttachment,
        nonce: nonce
    )
    let encoder = JSONEncoder()
    encoder.dataEncodingStrategy = .base64
    do {
        let jsonData = try encoder.encode(messageRequest)
        request.httpBody = jsonData
        Log.backend.notice(
            "Encoded send-message request user=\(userId, privacy: .public) nonce=\(nonce ?? "--", privacy: .public) requestBytes=\(jsonData.count, privacy: .public) includesAttachment=\((workersAttachment != nil), privacy: .public)"
        )
    } catch {
        Log.backend.error(
            "Failed to encode send-message request user=\(userId, privacy: .public) nonce=\(nonce ?? "--", privacy: .public): \(error, privacy: .public)"
        )
        return .failure(.failed(.invalidJSON))
    }

    do {
        Log.backend.notice(
            "Starting send-message HTTP POST url=\(url.absoluteString, privacy: .public) user=\(userId, privacy: .public) nonce=\(nonce ?? "--", privacy: .public)"
        )
        let (data, response) = try await BackendAuth.shared.authorizedData(for: request)
        Log.backend.notice(
            "Finished send-message HTTP POST user=\(userId, privacy: .public) nonce=\(nonce ?? "--", privacy: .public) responseBytes=\(data.count, privacy: .public)"
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            Log.backend.error(
                "Received non-http response \(String(describing: response), privacy: .public)")
            return .failure(.failed(.badResponse(nil)))
        }
        Log.backend.notice(
            "Received send-message HTTP status=\(httpResponse.statusCode, privacy: .public) user=\(userId, privacy: .public) nonce=\(nonce ?? "--", privacy: .public)"
        )
        guard httpResponse.statusCode == 200 else {
            if let responseData = String(data: data, encoding: .utf8) {
                Log.backend.error(
                    "Received failed \(httpResponse.statusCode, privacy: .public) send-messages response with data: \(responseData, privacy: .public)"
                )
            } else {
                Log.backend.error(
                    "Received failed \(httpResponse.statusCode, privacy: .public) send-messages response and data could not be converted to a String"
                )
            }
            return .failure(.failed(.badResponse(httpResponse.statusCode)))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        let message = try decoder.decode(MessageModelResponse.self, from: data)
        Log.backend.notice(
            "Decoded send-message response backendMessageId=\(message.id, privacy: .public) nonce=\(message.nonce ?? "--", privacy: .public) attachmentCount=\(message.attachments?.count ?? 0, privacy: .public)"
        )
        Log.backend.notice("Sent message \(message.id, privacy: .public) to backend")
        return .success(message)
    } catch is CancellationError {
        Log.backend.error(
            "Send-message request cancelled user=\(userId, privacy: .public) nonce=\(nonce ?? "--", privacy: .public)"
        )
        return .failure(.retryable(CancellationError()))
    } catch {
        Log.backend.error(
            "Send-message request failed user=\(userId, privacy: .public) nonce=\(nonce ?? "--", privacy: .public): \(error, privacy: .public)"
        )
        return .failure(.retryable(error))
    }
}
