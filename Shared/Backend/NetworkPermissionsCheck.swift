import Foundation
import Network
import OSLog

#if os(macOS)
func requestLocalNetworkAuthorization() async throws -> Bool {
    let queue = DispatchQueue(label: "com.nonstrict.localNetworkAuthCheck")

    let connection = NWConnection(host: NWEndpoint.Host("255.255.255.255"), port: 4567, using: .udp)

    return try await withTaskCancellationHandler {
        let stream = AsyncThrowingStream(Bool.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            @Sendable func resume(with result: Result<Bool, any Error>) {
                // Teardown listener and browser
                connection.stateUpdateHandler = { _ in }
                connection.cancel()

                continuation.yield(with: result)
            }

            // Do not setup listener/browser is we're already cancelled, it does work but logs a lot of very ugly errors
            if Task.isCancelled {
                Log.network.notice("Task cancelled before listener & browser started.")
                resume(with: .failure(CancellationError()))
                return
            }
            connection.pathUpdateHandler = { newPath in
                Log.network.notice("Browser path changed to \(String(describing: newPath))")
                if newPath.status == .unsatisfied && newPath.unsatisfiedReason == .localNetworkDenied {
                    resume(with: .success(false))
                }
            }

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .setup:
                    Log.network.notice("Browser performing setup.")
                    return
                case .ready:
                    Log.network.notice("Connection ready to send packets.")
                    resume(with: .success(true))
                    return
                case .cancelled:
                    Log.network.notice("Connection cancelled.")
                    resume(with: .failure(CancellationError()))
                case .failed(let error):
                    Log.network.error("Connection failed, stopping. \(error, privacy: .public)")
                    resume(with: .failure(error))
                case let .waiting(error):
                    Log.network.error("Connection waiting, will update in pathUpdateHandler. \(error, privacy: .public)")
                    queue.asyncAfter(deadline: .now() + 0.1) {
                        switch connection.state {
                        case .waiting: connection.restart()
                        default: break
                        }
                    }
                case .preparing:
                    Log.network.notice("Connection preparing.")
                @unknown default:
                    Log.network.warning("Ignoring unknown Connection state: \(String(describing: newState), privacy: .public)")
                    return
                }
            }

            connection.start(queue: queue)

            // Task cancelled while setting up listener & Connection, tear down immediatly
            if Task.isCancelled {
                Log.network.notice("Task cancelled during listener & Connection start. (Some warnings might be logged by the listener or Connection.)")
                resume(with: .failure(CancellationError()))
                return
            }
        }

        var iterator = stream.makeAsyncIterator()
        guard let first = try await iterator.next() else {
            throw CancellationError()
        }

        return first
    } onCancel: {
        connection.stateUpdateHandler = { _ in }
        connection.cancel()
    }
}
#else
private let type = "_preflight_check._tcp"

func requestLocalNetworkAuthorization() async throws -> Bool {
    let queue = DispatchQueue(label: "com.nonstrict.localNetworkAuthCheck")

    Log.network.notice("Setup listener.")
    let listener = try NWListener(using: NWParameters(tls: .none, tcp: NWProtocolTCP.Options()))
    listener.service = NWListener.Service(name: UUID().uuidString, type: type)
    listener.newConnectionHandler = { _ in } // Must be set or else the listener will error with POSIX error 22

    Log.network.notice("Setup browser.")
    let parameters = NWParameters()
    parameters.includePeerToPeer = true
    let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: parameters)

    return try await withTaskCancellationHandler {
        let stream = AsyncThrowingStream(Bool.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            final class LocalState {
                var didResume = false
            }
            @Sendable func resume(with result: Result<Bool, any Error>) {
                // Teardown listener and browser
                listener.stateUpdateHandler = { _ in }
                browser.stateUpdateHandler = { _ in }
                browser.browseResultsChangedHandler = { _, _ in }
                listener.cancel()
                browser.cancel()

                continuation.yield(with: result)
            }

            // Do not setup listener/browser is we're already cancelled, it does work but logs a lot of very ugly errors
            if Task.isCancelled {
                Log.network.notice("Task cancelled before listener & browser started.")
                resume(with: .failure(CancellationError()))
                return
            }

            listener.stateUpdateHandler = { newState in
                switch newState {
                case .setup:
                    Log.network.notice("Listener performing setup.")
                case .ready:
                    Log.network.notice("Listener ready to be discovered.")
                case .cancelled:
                    Log.network.notice("Listener cancelled.")
                    resume(with: .failure(CancellationError()))
                case .failed(let error):
                    Log.network.error("Listener failed, stopping. \(error, privacy: .public)")
                    resume(with: .failure(error))
                case .waiting(let error):
                    Log.network.warning("Listener waiting, stopping. \(error, privacy: .public)")
                    resume(with: .failure(error))
                @unknown default:
                    Log.network.warning("Ignoring unknown listener state: \(String(describing: newState), privacy: .public)")
                }
            }
            listener.start(queue: queue)

            browser.stateUpdateHandler = { newState in
                switch newState {
                case .setup:
                    Log.network.notice("Browser performing setup.")
                    return
                case .ready:
                    Log.network.notice("Browser ready to discover listeners.")
                    return
                case .cancelled:
                    Log.network.notice("Browser cancelled.")
                    resume(with: .failure(CancellationError()))
                case .failed(let error):
                    Log.network.error("Browser failed, stopping. \(error, privacy: .public)")
                    resume(with: .failure(error))
                case let .waiting(error):
                    switch error {
                    case .dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied)):
                        Log.network.notice("Browser permission denied, reporting failure.")
                        resume(with: .success(false))
                    default:
                        Log.network.error("Browser waiting, stopping. \(error, privacy: .public)")
                        resume(with: .failure(error))
                    }
                @unknown default:
                    Log.network.warning("Ignoring unknown browser state: \(String(describing: newState), privacy: .public)")
                    return
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                if results.isEmpty {
                    Log.network.warning("Got empty result set from browser, ignoring.")
                    return
                }

                Log.network.notice("Discovered \(results.count, privacy: .public) listeners, reporting success.")
                resume(with: .success(true))
            }
            browser.start(queue: queue)

            // Task cancelled while setting up listener & browser, tear down immediatly
            if Task.isCancelled {
                Log.network.notice("Task cancelled during listener & browser start. (Some warnings might be logged by the listener or browser.)")
                resume(with: .failure(CancellationError()))
                return
            }
        }

        var iterator = stream.makeAsyncIterator()
        guard let first = try await iterator.next() else {
            throw CancellationError()
        }

        return first
    } onCancel: {
        listener.cancel()
        browser.cancel()
    }
}
#endif
