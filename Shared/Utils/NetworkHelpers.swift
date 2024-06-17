import Foundation
import Network
import os

let checkConnectLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "TCPConnectionChecker"
)

#if !os(watchOS)
    public func tryConnectTCP(
        location: String,
        timeout: TimeInterval,
        interface: NWInterface? = nil
    ) async -> NWInterface? {
        guard let url = URL(string: location),
              let host = url.host,
              let port = url.port
        else {
            checkConnectLogger.error("Cannot connect to url \(location) bc url not valid")
            return nil
        }
        checkConnectLogger.debug("Checking can connect to url \(location) (\(host):\(port)) with interface \(interface?.name ?? "--")")
        let tcpParams = NWProtocolTCP.Options()
        let params = NWParameters(tls: nil, tcp: tcpParams)
        if let interface {
            params.requiredInterface = interface
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: params
        )

        do {
            return try await withTimeout(delay: timeout) {
                await withTaskCancellationHandler {
                    let stream = AsyncStream { continuation in
                        connection.stateUpdateHandler = { state in
                            switch state {
                            case .ready:
                                checkConnectLogger
                                    .debug(
                                        "Connected to \(location) with ifaces \(String(describing: connection.currentPath?.availableInterfaces))"
                                    )
                                if let localIface = connection.currentPath?.availableInterfaces.first {
                                    continuation.yield(Optional(localIface))
                                    return
                                }
                            case .cancelled:
                                continuation.yield(nil)
                                return
                            case .failed, .waiting, .setup, .preparing:
                                return
                            @unknown default:
                                return
                            }
                        }
                    }

                    var iterator = stream.makeAsyncIterator()
                    connection.start(queue: DispatchQueue.global())
                    return await iterator.next() ?? nil
                } onCancel: {
                    connection.cancel()
                }
            }
        } catch {
            checkConnectLogger.warning("Cannot connect to \(location) because of error \(error)")
            return nil
        }
    }

    public func canConnectTCP(location: String, timeout: TimeInterval, interface: NWInterface? = nil) async -> Bool {
        await tryConnectTCP(location: location, timeout: timeout, interface: interface) != nil
    }
#else
    public func canConnectHTTP(location: String, timeout: TimeInterval) async -> Bool {
        let result = try? await withTimeout(delay: timeout) {
            let url = URL(string: location)!
            let request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: timeout
            )

            let stream = AsyncStream<Bool> { continuation in
                let task = URLSession.shared.dataTask(with: request) { _, response, _ in
                    if let httpResponse = response as? HTTPURLResponse,
                       (200 ... 299).contains(httpResponse.statusCode)
                    {
                        continuation.yield(true)
                    } else {
                        continuation.yield(false)
                    }
                }

                task.resume()
            }

            var iterator = stream.makeAsyncIterator()
            return await iterator.next() ?? false
        } ?? false
        return result ?? false
    }
#endif
