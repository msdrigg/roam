import CryptoKit
import DeviceCheck
import Foundation
import OSLog

/// Bundle ids the backend will accept an attestation from. The widget
/// extensions have their own bundle ids and are not on the list, so if one ever
/// does reach the backend it fails here with a clear error rather than burning
/// an App Attest registration the server would refuse anyway.
private let attestableBundleIDs: Set<String> = [
    "com.msdrigg.roam",
    "com.msdrigg.roam.watchkitapp",
]

/// Routes that create something durable on the backend, and the only ones that
/// carry an assertion.
///
/// Signing by HTTP method instead would sign `/typing`, which goes out every
/// five seconds while someone is composing, and that is the assertion volume
/// Apple warns has real CPU cost. This list has to match `requires_proof` in
/// the backend's `auth.rs`, or a signed request meets a server that ignores the
/// signature and an unsigned one meets a server that demands it.
private let proofRequiredPaths: Set<String> = [
    "/v2/new-message",
    "/new-message",
    "/v2/upload-diagnostics",
    "/new-apns",
]

private func requiresProof(_ path: String) -> Bool {
    proofRequiredPaths.contains(path) || path.hasPrefix("/upload-diagnostics/")
}

/// Platform and OS version, reported when a device cannot attest so the backend
/// can separate an old Mac from a client that should have been able to.
private func platformDescription() -> String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    #if os(macOS)
        let platform = "macOS"
    #elseif os(iOS)
        let platform = "iOS"
    #elseif os(watchOS)
        let platform = "watchOS"
    #elseif os(visionOS)
        let platform = "visionOS"
    #else
        let platform = "unknown"
    #endif
    return "\(platform) \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
}

/// Why the backend refused an attestation call.
///
/// The 401s on these routes cover unrelated faults -- a signature that did not
/// verify, a challenge already spent, a counter already seen, a key the server
/// has never heard of -- and only the last kind says anything about the
/// credential this device holds. The backend now names the reason in a `reason`
/// field beside the sentence it has always sent, because matching on the
/// sentence would break the day someone rewords it.
///
/// Reading these wrong is expensive in one direction only. Deleting the key and
/// registering a new one costs a Secure Enclave attestation, which Apple rate
/// limits and the backend caps at twenty an hour per address; treating a dead
/// key as live costs one failed request that the next launch retries. So
/// anything not positively identified as "the key is gone" is treated as live.
public enum AttestationRejectionReason: Sendable, Equatable {
    /// The backend has no record of this key. The credential is gone.
    case keyUnknown
    /// The key is on file but revoked. The credential is gone.
    case keyRevoked
    /// Everything else, including a 401 from a backend old enough to send no
    /// code at all. Unrecognised has to land here: re-registering is the
    /// destructive choice, so it is the one that needs positive evidence.
    case other(String?)

    init(code: String?) {
        switch code {
        case "key_unknown":
            self = .keyUnknown
        case "key_revoked":
            self = .keyRevoked
        default:
            self = .other(code)
        }
    }

    /// Whether the key behind this credential is worth nothing now, and a
    /// fresh registration is the only way forward.
    var credentialIsGone: Bool {
        switch self {
        case .keyUnknown, .keyRevoked:
            return true
        case .other:
            return false
        }
    }

    /// The wire code, for logs.
    var code: String {
        switch self {
        case .keyUnknown:
            return "key_unknown"
        case .keyRevoked:
            return "key_revoked"
        case let .other(code):
            return code ?? "unspecified"
        }
    }
}

public enum BackendAuthError: Error, LocalizedError {
    case attestationRejected(status: Int, reason: AttestationRejectionReason, body: String)
    case registrationThrottled(retryAfter: TimeInterval)
    case missingKey
    case missingReceipt
    case attestationUnavailable(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case let .attestationRejected(status, reason, body):
            return "The backend rejected attestation (\(status)/\(reason.code)): \(body)"
        case let .registrationThrottled(retryAfter):
            return
                "Too many attestation registrations recently; the next one may run in \(Int(retryAfter))s"
        case .missingKey:
            return "No attestation key is available"
        case .missingReceipt:
            return "No App Store receipt is available to authenticate with"
        case let .attestationUnavailable(reason):
            return "App Attest is unavailable and this platform has no fallback: \(reason)"
        case .badResponse:
            return "The backend returned an unexpected response"
        }
    }
}

/// How many key registrations may *start* inside `registrationWindow`, across
/// every Roam process on this device.
///
/// A healthy install registers once and never again, so this only ever bites a
/// loop. It is deliberately far below the backend's twenty an hour per address
/// and Apple's own undocumented ceiling: the point is to stop long before
/// either of those starts refusing, because what they refuse is the app's only
/// route to a credential. Three leaves room for the genuine retries -- a key
/// that failed to persist, a registration that lost its network -- while
/// turning a runaway into a handful of attempts an hour instead of one every
/// fifty seconds.
private let registrationBudget = 3
private let registrationWindow: TimeInterval = 3600
private let registrationLedgerKey = "app-attest-registration-attempts"

/// The bytes an assertion signs.
///
/// The client sends these exact bytes alongside the assertion, so the server
/// hashes what was signed rather than a re-serialisation of the same fields.
/// On the session-refresh route `s` carries the challenge, because there is no
/// session to name yet.
private struct AssertionClientData: Encodable {
    let s: String
    let m: String
    let p: String
    let t: Int64
}

private struct ChallengeResponse: Decodable {
    let challenge: String
    let expiresAtMs: Int64
}

/// The part of a backend error body this file acts on.
///
/// Everything else in it is prose, and the field is optional because a client
/// on this route can meet a backend that predates it.
private struct ErrorEnvelope: Decodable {
    let reason: String?
}

private struct SessionResponse: Decodable {
    let token: String
    let sessionId: String
    let userId: String
    let expiresAtMs: Int64
    let attested: Bool
}

/// Holds the app's backend credential.
///
/// The session token lives here and nowhere else: it is never written to
/// disk, the Keychain, or a log. What does persist is the key identifier,
/// which names a P-256 key generated inside the Secure Enclave and is useless
/// without the hardware that holds it. Recovering the token from memory buys
/// an attacker reads at most, because every write has to carry a fresh
/// assertion that only that hardware can produce.
#if os(macOS)
    /// The Mac App Store receipt, base64 encoded.
    ///
    /// Present in every App Store copy. A local build has none, which is why
    /// development against production needs the backend's development flag
    /// rather than a client-side bypass.
    private func appStoreReceipt() -> String? {
        guard let url = Bundle.main.appStoreReceiptURL,
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return data.base64EncodedString()
    }
#endif

public actor BackendAuth {
    public static let shared = BackendAuth()

    private struct Session {
        let token: String
        let sessionId: String
        let userId: String
        let expiresAt: Date
        let attested: Bool
    }

    private var session: Session?
    /// Collapses concurrent callers onto one handshake so a cold launch does
    /// not fire several registrations at Apple's rate-limited endpoint.
    private var handshake: Task<Session, Error>?

    private let keychainService = "io.msd3.roam.appattest"
    private let keychainAccount = "app-attest-key-id"

    /// Sends `request` with a credential attached, refreshing once if the
    /// backend says the session is no longer good.
    public func authorizedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        for attempt in 0...1 {
            let session = try await currentSession()
            let signed = try await sign(request, with: session)
            let (data, response) = try await URLSession.shared.data(for: signed)

            if let http = response as? HTTPURLResponse, http.statusCode == 401, attempt == 0 {
                Log.backend.notice("Backend rejected the session; re-authenticating once")
                self.session = nil
                continue
            }
            return (data, response)
        }
        throw BackendAuthError.badResponse
    }

    /// Drops the in-memory session, so the next request re-authenticates.
    public func invalidate() {
        session = nil
    }

    private func currentSession() async throws -> Session {
        // A minute of headroom so a request that authenticates just under the
        // wire does not arrive just over it.
        if let session, session.expiresAt.timeIntervalSinceNow > 60 {
            return session
        }
        if let handshake {
            return try await handshake.value
        }

        let task = Task { try await self.establishSession() }
        handshake = task
        defer { handshake = nil }

        let established = try await task.value
        session = established
        adoptUserID(established.userId)
        return established
    }

    private func establishSession() async throws -> Session {
        let service = DCAppAttestService.shared
        let bundleID = Bundle.main.bundleIdentifier ?? "--"

        guard attestableBundleIDs.contains(bundleID), service.isSupported else {
            return try await fallbackSession(
                reason: "isSupported=\(service.isSupported) bundle=\(bundleID)")
        }

        do {
            return try await attestedSession(service: service)
        } catch {
            Log.backend.error(
                "Attestation failed: \(error, privacy: .public)")
            return try await fallbackSession(reason: "attestation failed: \(error)")
        }
    }

    /// The macOS-only fallback, for Macs below macOS 27 where App Attest does
    /// not exist.
    ///
    /// This is compiled out of every other platform on purpose. iOS 18,
    /// watchOS 11 and visionOS 2 all support App Attest, so a client there
    /// claiming it cannot attest is tampering rather than an old OS, and a
    /// binary that does not contain this code cannot be talked into using it.
    /// The backend refuses the route without a valid Apple-signed receipt, so
    /// the two halves have to be removed together when macOS 27 is the floor.
    private func fallbackSession(reason: String) async throws -> Session {
        #if os(macOS)
            let platform = platformDescription()
            guard let receipt = appStoreReceipt() else {
                Log.backend.error(
                    "No App Store receipt available on \(platform, privacy: .public); cannot authenticate"
                )
                throw BackendAuthError.missingReceipt
            }
            Log.backend.warning(
                "Falling back to a receipt-backed session on \(platform, privacy: .public): \(reason, privacy: .public)"
            )
            return try await unattestedSession(
                receipt: receipt, reason: "\(reason); \(platform)")
        #else
            // No fallback exists here, and none should: every supported OS on
            // this platform can attest.
            throw BackendAuthError.attestationUnavailable(reason)
        #endif
    }

    private func attestedSession(service: DCAppAttestService) async throws -> Session {
        if let keyID = loadKeyID() {
            do {
                return try await refreshSession(keyID: keyID, service: service)
            } catch let BackendAuthError.attestationRejected(status, reason, _)
                where status == 401 && reason.credentialIsGone
            {
                // The backend has no usable record of this key, so the
                // credential behind it is gone. Start over rather than
                // retrying forever.
                //
                // Every other 401 this route can return -- a signature that
                // did not verify, a spent challenge, a counter already seen --
                // describes the request, not the key, and re-registering fixes
                // none of them. A server-side signature bug once made all of
                // them look identical to this one, and a client that could not
                // tell the difference registered five Secure Enclave keys in
                // four minutes before anyone noticed. Those fall through
                // uncaught: the handshake fails, the caller retries, and the
                // key on disk survives to be used when the server is well.
                Log.backend.notice(
                    "The backend no longer holds this attestation key (\(reason.code, privacy: .public)); re-registering"
                )
                deleteKeyID()
            } catch let error as DCError {
                // A key ID outlives the key it names. Reinstalling the app or
                // restoring the device invalidates the Secure Enclave key while
                // the Keychain entry survives, so the identifier on disk can
                // point at nothing. Without this the app would retry a dead key
                // on every launch and never recover.
                Log.backend.notice(
                    "App Attest rejected the stored key (\(error.code.rawValue, privacy: .public)); re-registering"
                )
                deleteKeyID()
            }
        }

        return try await registerKey(service: service)
    }

    private func registerKey(service: DCAppAttestService) async throws -> Session {
        // Claimed before anything else so a throttled client does not even
        // spend a challenge, and -- more to the point -- so no future misread
        // of a server error can turn into an unbounded registration loop. The
        // reason codes above are the specific fix; this is the backstop that
        // holds whatever the next bug turns out to be.
        try claimRegistrationSlot()

        let challenge = try await fetchChallenge()
        let keyID = try await service.generateKey()
        // Persist before attesting: a key that is generated but not recorded
        // can never be used again, and Apple attests any given key only once.
        storeKeyID(keyID)

        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
        let attestation = try await service.attestKey(keyID, clientDataHash: clientDataHash)

        let body: [String: String] = [
            "keyId": keyID,
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge,
            "userId": getSystemInstallID(),
        ]
        let response: SessionResponse = try await post("/v3/attest/register", body: body)
        Log.backend.notice("Registered an attested key with the backend")
        return session(from: response)
    }

    private func refreshSession(keyID: String, service: DCAppAttestService) async throws -> Session {
        let challenge = try await fetchChallenge()
        let clientData = try encodeClientData(
            s: challenge, m: "POST", p: "/v3/attest/session")
        let clientDataHash = Data(SHA256.hash(data: clientData))
        let assertion = try await service.generateAssertion(keyID, clientDataHash: clientDataHash)

        let body: [String: String] = [
            "keyId": keyID,
            "assertion": assertion.base64EncodedString(),
            "clientData": clientData.base64EncodedString(),
        ]
        let response: SessionResponse = try await post("/v3/attest/session", body: body)
        return session(from: response)
    }

    private func unattestedSession(receipt: String, reason: String) async throws -> Session {
        let challenge = try await fetchChallenge()
        let body: [String: String] = [
            "userId": getSystemInstallID(),
            "challenge": challenge,
            "receipt": receipt,
            "reason": reason,
        ]
        let response: SessionResponse = try await post("/v3/attest/unattested", body: body)
        return session(from: response)
    }

    private func session(from response: SessionResponse) -> Session {
        Session(
            token: response.token,
            sessionId: response.sessionId,
            userId: response.userId,
            expiresAt: Date(timeIntervalSince1970: Double(response.expiresAtMs) / 1000),
            attested: response.attested
        )
    }

    private func sign(_ request: URLRequest, with session: Session) async throws -> URLRequest {
        var request = request
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        guard let path = request.url?.path(percentEncoded: true) else {
            throw BackendAuthError.badResponse
        }
        let method = request.httpMethod ?? "GET"
        guard session.attested, requiresProof(path) else {
            return request
        }
        guard let keyID = loadKeyID() else {
            throw BackendAuthError.missingKey
        }

        // Assertions are generated inside the actor, so their counters leave
        // the device in the order the Secure Enclave issued them.
        let clientData = try encodeClientData(s: session.sessionId, m: method, p: path)
        let clientDataHash = Data(SHA256.hash(data: clientData))
        let assertion = try await DCAppAttestService.shared.generateAssertion(
            keyID, clientDataHash: clientDataHash)

        request.setValue(clientData.base64EncodedString(), forHTTPHeaderField: "X-Roam-Client-Data")
        request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-Roam-Assertion")
        return request
    }

    private func encodeClientData(s: String, m: String, p: String) throws -> Data {
        let payload = AssertionClientData(
            s: s, m: m, p: p, t: Int64(Date().timeIntervalSince1970 * 1000))
        return try JSONEncoder().encode(payload)
    }

    private func fetchChallenge() async throws -> String {
        let response: ChallengeResponse = try await post("/v3/attest/challenge", body: [:])
        return response.challenge
    }

    private func post<Response: Decodable>(_ path: String, body: [String: String]) async throws
        -> Response
    {
        guard let url = URL(string: "\(globalBackendURL)\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendAuthError.badResponse
        }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "--"
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            let reason = AttestationRejectionReason(code: envelope?.reason)
            Log.backend.error(
                "Attestation call \(path, privacy: .public) failed \(http.statusCode, privacy: .public)/\(reason.code, privacy: .public): \(detail, privacy: .public)"
            )
            throw BackendAuthError.attestationRejected(
                status: http.statusCode, reason: reason, body: detail)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    // MARK: - Registration budget

    /// Registrations are recorded here rather than in memory because the loop
    /// this guards against outlives a process: the widget extensions and the
    /// watch app each run their own short-lived copy of this actor, and a
    /// per-process counter would reset before it ever refused anything. The
    /// app group is what makes the budget one budget.
    private let registrationLedger = UserDefaults(suiteName: roamAppGroup) ?? .standard

    /// Records that a registration is about to start, or refuses when too many
    /// have run recently.
    private func claimRegistrationSlot() throws {
        let now = Date().timeIntervalSince1970
        // Stamps far from now in *either* direction are dropped. A clock that
        // jumps forward and back would otherwise leave entries that never age
        // out, and a device locked out of attestation forever is a worse
        // failure than one that registers a few extra times.
        var recent = (registrationLedger.array(forKey: registrationLedgerKey) as? [Double] ?? [])
            .filter { abs(now - $0) < registrationWindow }

        guard recent.count < registrationBudget else {
            let oldest = recent.min() ?? now
            let retryAfter = max(0, registrationWindow - (now - oldest))
            Log.backend.error(
                "Refusing to register another attestation key: \(recent.count, privacy: .public) in the last hour"
            )
            throw BackendAuthError.registrationThrottled(retryAfter: retryAfter)
        }

        // Written before the registration runs rather than after it succeeds.
        // A registration that is killed or crashes partway has still spent
        // Apple's budget, and a loop is precisely the case that never reaches
        // the line after.
        recent.append(now)
        registrationLedger.set(recent, forKey: registrationLedgerKey)
    }

    // MARK: - Key identifier storage

    /// The key identifier is a handle, not a secret: it names a key the Secure
    /// Enclave will only ever use on this device. It lives in the Keychain so
    /// the app attests once per install rather than once per launch, which
    /// matters because Apple rate limits attestation.
    private func loadKeyID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let keyID = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return keyID
    }

    private func storeKeyID(_ keyID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(keyID.utf8)
        // Readable after the first unlock so a background refresh works, and
        // never synchronised: the private key it names cannot leave this
        // device, so a copy of the identifier elsewhere is dead weight.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            Log.backend.error("Could not store attestation key id: \(status, privacy: .public)")
        }
    }

    private func deleteKeyID() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
