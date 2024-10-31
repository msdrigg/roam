import Foundation
import OSLog
import SwiftData

private let globalBackendURL = "https://backend.roam.msd3.io"
// private let globalBackendURL = "http://192.168.8.133:8787"

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "WorkersBackend"
)

private func getAPIKey() -> String? {
    let apiKey = Bundle.main.infoDictionary?["BACKEND_API_KEY"] as? String

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

struct MessageRequest: Encodable {
    let content: String
    let title: String?
    let apnsToken: String?
    let userId: String
    let installationInfo: InstallationInfo
}

struct MessageModelResponse: Decodable {
    let id: String
    let message: String
    let author: Message.AuthorType

    enum CodingKeys: String, CodingKey {
        case id
        case message = "content"
        case author
    }

    init(id: String, message: String, author: Message.AuthorType) {
        self.id = id
        self.message = message
        self.author = author
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        message = try container.decode(String.self, forKey: .message)

        let authorInfo = try container.nestedContainer(keyedBy: AuthorKeys.self, forKey: .author)
        let id = try authorInfo.decode(String.self, forKey: .id)
        author = id == "1229219148228460595" ? .me : .support
    }

    private enum AuthorKeys: String, CodingKey {
        case id
    }
}

func getMessages(after: String?) async throws -> [MessageModelResponse] {
    let userId = getSystemInstallID()

    var url = "\(globalBackendURL)/messages/\(userId)"
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
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        if let responseData = String(data: data, encoding: .utf8) {
            logger.info("Received non-200 response with data: \(responseData)")
        } else {
            logger.info("Received non-200 response and data could not be converted to a String")
        }
        throw URLError(.badServerResponse)
    }

    let messages = try JSONDecoder().decode([MessageModelResponse].self, from: data)
    return messages
}

public func sendMessage(message: String?, apnsToken: String?) async throws {
    guard let url = URL(string: "\(globalBackendURL)/new-message") else {
        throw URLError(.badURL)
    }

    logger.info("Sending message to backend")
    let userId = getSystemInstallID()

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue(getAPIKey() ?? "", forHTTPHeaderField: "x-api-key")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let messageRequest = MessageRequest(
        content: message ?? "",
        title: "Message from \(userId)",
        apnsToken: apnsToken,
        userId: userId,
        installationInfo: InstallationInfo()
    )
    let encoder = JSONEncoder()
    let jsonData = try encoder.encode(messageRequest)
    request.httpBody = jsonData

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        if let responseData = String(data: data, encoding: .utf8) {
            logger.error("Received non-200 response with data: \(responseData)")
        } else {
            logger.error("Received non-200 response and data could not be converted to a String")
        }
        throw URLError(.badServerResponse)
    }
}

public func uploadDebugLogs(logs: DebugInfo) async throws {
    let diagnosticKey = logs.installationInfo.userId
    guard let url = URL(string: "\(globalBackendURL)/upload-diagnostics/\(diagnosticKey)") else {
        throw URLError(.badURL)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue(getAPIKey() ?? "", forHTTPHeaderField: "x-api-key")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let jsonData = try encoder.encode(logs)
    request.httpBody = jsonData

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        if let responseData = String(data: data, encoding: .utf8) {
            logger.error("Received non-200 response with data: \(responseData)")
        } else {
            logger.error("Received non-200 response and data could not be converted to a String")
        }
        throw URLError(.badServerResponse)
    }
}
