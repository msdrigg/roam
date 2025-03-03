import Darwin
import Foundation
import Network
import os
import System

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
            Log.scanning.notice("Starting scan with interface \(interface ?? "nil", privacy: .public)")
            let socket = try FileDescriptor.socket(AF_INET, SOCK_DGRAM, 0)
            // Setting nosigpipe due to https://developer.apple.com/forums/thread/773307
            try socket.setSocketOption(SOL_SOCKET, SO_NOSIGPIPE, 1 as CInt)
            try socket.setSocketOption(SOL_SOCKET, SO_REUSEPORT, 1 as CInt)

            _ = try QSockAddr.withSockAddr(address: "0.0.0.0", port: 1900) { sa, saLen in
                Log.scanning.notice("Binding socket to 0.0.0.0:1900")
                _ = try socket.bind(sa, saLen)
            }

            if let interface {
                let iface = try QSockAddr.interfaceIndex(interface)
                Log.scanning.notice("Setting bound interface \(interface, privacy: .public) (\(iface, privacy: .public))")
                try socket.setSocketOption(IPPROTO_IP, IP_BOUND_IF, UInt32(iface))
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
                        Log.scanning.notice("Sent SSDP request successfully")
                        failures = 0
                    } catch {
                        failures += 1
                        Log.scanning.warning("Error sending SSDP request: \(error, privacy: .public)")
                        if failures >= 2 {
                            continuation.finish(throwing: error)
                        }
                    }
                }
            }

            let receivingHandle = Task {
                while !Task.isCancelled {
                    do {
                        Log.scanning.notice("Trying to receive SSDP data from \(groupAddress, privacy: .public):\(groupPort, privacy: .public)")
                        let (data, from) = try socket.receiveFrom(maxCount: 16384)
                        Log.scanning.notice("Receiving SSDP data with len \(data.count, privacy: .public) from \(from.0, privacy: .public):\(from.1, privacy: .public)")
                        if let response = String(data: data, encoding: .utf8) {
                            continuation.yield(SSDPService(host: from.address, response: response))
                        }
                    } catch {
                        if Task.isCancelled {
                            Log.scanning.notice("Error receiving from cancelled SSDP: \(error, privacy: .public)")
                        } else {
                            Log.scanning.warning("Error receiving SSDP: \(error, privacy: .public)")
                        }
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                Log.scanning.notice("Terminating ssdp")
                receivingHandle.cancel()
                sendingHandle.cancel()
                try? socket.close()
            }
        } catch {
            Log.scanning.error("Failed to create or configure socket: \(error, privacy: .public)")
            continuation.finish(throwing: SSDPError.socketCreationFailed)
        }
    }
}
