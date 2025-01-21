import Darwin
import Foundation
import Network
import os
import System

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: String(describing: "SSDPDiscovery")
)

enum SSDPError: Swift.Error, LocalizedError {
    case socketCreationFailed
    case connectionGroupFailed
    case interfaceNotFound(String?)
}

/// SSDP discovery for UPnP devices on the LAN.
/// Created using BSD sockets do to this bug: https://developer.apple.com/forums/thread/716339?page=1#769355022
/// Code using Network framework shown below
func scanDevicesContinually(interface: String?) throws -> AsyncThrowingStream<SSDPService, any Error> {
    AsyncThrowingStream { continuation in
        do {
            let socket = try FileDescriptor.socket(AF_INET, SOCK_DGRAM, 0)

            // Optionally bind to a specific interface address
            // Retrieve the interface address
            if let interface {
                let interfaceAddresses = QSockAddr.addressesByInterface()[interface] ?? []
                let interfaceAddress = interfaceAddresses.first
                logger.info("Getting information about interfaces \(interfaceAddresses, privacy: .public) and chose \(interfaceAddress ?? "--", privacy: .public)")

                // Bind the socket to the interface address
                if let address = interfaceAddress {
                    try QSockAddr.withSockAddr(address: address, port: 0) { sa, saLen in
                        _ = try socket.bind(sa, saLen)
                    }
                }

                // Set the multicast interface for sending
                logger.info("Setting multicast interface \(interfaceAddress ?? "", privacy: .public)")
                let multicastInterface = in_addr(s_addr: inet_addr(interfaceAddress))
                try socket.setSocketOption(IPPROTO_IP, IP_MULTICAST_IF, multicastInterface)
            }

            let groupAddress = "239.255.255.250"
            let groupPort: UInt16 = 1900

            let message =
                """
                M-SEARCH * HTTP/1.1\r\n\
                Host: 239.255.255.250:1900\r\n\
                Man: "ssdp:discover"\r\n\
                ST: roku:ecp\r\n\r\n
                """

            let sendingHandle = Task {
                var failures = 0
                for await _ in exponentialBackoff(min: 2, max: 30) {
                    if Task.isCancelled {
                        return
                    }
                    do {
                        try socket.send(data: Data(message.utf8), to: (address: groupAddress, port: groupPort))
                        logger.debug("Sent SSDP request successfully")
                        failures = 0
                    } catch {
                        failures += 1
                        logger.warning("Error sending SSDP request: \(error, privacy: .public)")
                        if failures >= 2 {
                            continuation.finish(throwing: error)
                        }
                    }
                }
            }

            let receivingHandle = Task {
                while !Task.isCancelled {
                    do {
                        logger.info("Trying to receive SSDP data from \(groupAddress, privacy: .public):\(groupPort, privacy: .public)")
                        let (data, from) = try socket.receiveFrom(maxCount: 16384)
                        logger.info("Receinving SSDP data with len \(data.count, privacy: .public) from \(from.0, privacy: .public):\(from.1, privacy: .public)")
                        if let response = String(data: data, encoding: .utf8) {
                            continuation.yield(SSDPService(host: from.address, response: response))
                        }
                    } catch {
                        logger.warning("Error receiving SSDP response: \(error, privacy: .public)")
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                receivingHandle.cancel()
                sendingHandle.cancel()
                try? socket.close()
            }
        } catch {
            logger.error("Failed to create or configure socket: \(error, privacy: .public)")
            continuation.finish(throwing: SSDPError.socketCreationFailed)
        }
    }
}
