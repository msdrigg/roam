import Foundation
import Network
import os.log

public func openApp(location: String, app: String) async throws {
    guard let url = URL(string: "\(location)launch/\(app)") else { return }

    var request = URLRequest(url: url, timeoutInterval: 3)
    request.httpMethod = "POST"

    let (_, response) = try await URLSession.shared.data(for: request)
    if let httpResponse = response as? HTTPURLResponse {
        if httpResponse.statusCode == 200 {
            Log.connection.notice("Opened app \(app) to with location \(location, privacy: .public)")
        } else {
            Log.connection.error("Error opening app \(app, privacy: .public) at \(location, privacy: .public)launch/\(app, privacy: .public): \(httpResponse.statusCode, privacy: .public)")
        }
    }
}

@discardableResult
private func powerToggleDeviceStateless(location: String, macs: [String]) async -> Bool {
    Log.connection.notice("Toggling power for device \(location, privacy: .public)")

    // Attempt checking the device power mode
    Log.connection.notice("Attempting to power toggle device with api first")

    let toggleResult = await internalSendKeyToDevice(
        location: location,
        rawKey: RemoteButton.power.apiValue!,
        timeout: 1.1
    )
    if !toggleResult {
        let interfaces = await allAddressedInterfaces().filter{ iface in
            return (iface.flags & UInt32(IFF_UP) != 0) && (iface.flags & UInt32(IFF_RUNNING) != 0) && iface.nwInterface != nil
        }
        let interfaceNames = interfaces.map(\.name)

        Log.connection.notice("API toggle failed, trying to WOL to macs \(String(describing: macs), privacy: .public) on interfaces \(interfaceNames, privacy: .public)")

        for mac in macs {
            for iface in interfaces {
                Log.connection.notice("Sending wol packet to \(mac, privacy: .public) with interface \(iface.name, privacy: .public)")
                await wakeOnLAN(macAddress: mac, interface: iface.nwInterface)
            }
            if interfaces.count == 0 {
                Log.connection.notice("Sending wol packet to \(mac, privacy: .public) with no interface")
                await wakeOnLAN(macAddress: mac, interface: nil)
            }
        }
        return true
    } else {
        Log.connection.notice("API toggle suceeded!")
        return true
    }
}

public func sendKeyToDeviceRawNotRecommended(location: String, key: String, macs: [String]) async -> Bool {
    if key == RemoteButton.power.apiValue {
        Log.connection.notice("Toggling power on device \(location, privacy: .public) with mac \(String(describing: macs), privacy: .public)")
        return await powerToggleDeviceStateless(location: location, macs: macs)
    } else {
        Log.connection.notice("Sending key to device \(key, privacy: .public)")
        return await internalSendKeyToDevice(location: location, rawKey: key)
    }
}

private func internalSendKeyToDevice(location: String, rawKey: String, timeout: TimeInterval? = nil) async -> Bool {
    let keypressURL = "\(location)/keypress/\(rawKey)"
    guard let url = URL(string: keypressURL) else {
        Log.connection.error("Unable to send key due to bad url url `\(keypressURL, privacy: .public)`")
        return false
    }
    var request = URLRequest(url: url, timeoutInterval: timeout ?? 3)
    request.httpMethod = "POST"

    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
                Log.connection.notice("Sent \(rawKey, privacy: .public) to \(location, privacy: .public)")
                return true
            } else {
                Log.connection.error("Error sending \(rawKey, privacy: .public) to \(location, privacy: .public): \(httpResponse.statusCode, privacy: .public)")
                return false
            }
        }

        return false
    } catch {
        Log.connection.error("Error sending \(rawKey, privacy: .public) to \(location, privacy: .public): \(error, privacy: .public)")
        return false
    }
}

public func sendWolToDevice(macs: [String]) async {
    let interfaces = await allAddressedInterfaces().filter{ iface in
        return (iface.flags & UInt32(IFF_UP) != 0) && (iface.flags & UInt32(IFF_RUNNING) != 0) && iface.nwInterface != nil
    }
    let interfaceNames = interfaces.map(\.name)

    Log.connection.notice("Trying to WOL to macs \(String(describing: macs), privacy: .public) on interfaces \(interfaceNames, privacy: .public)")

    for mac in macs {
        for iface in interfaces {
            Log.connection.notice("Sending wol packet to \(mac, privacy: .public) with interface \(iface.name, privacy: .public)")
            await wakeOnLAN(macAddress: mac, interface: iface.nwInterface)
        }
        if interfaces.count == 0 {
            Log.connection.notice("Sending wol packet to \(mac, privacy: .public) with no interface")
            await wakeOnLAN(macAddress: mac, interface: nil)
        }
    }
}

@discardableResult
private func wakeOnLAN(macAddress: String, interface: NWInterface?) async -> Bool {
    let host = NWEndpoint.Host("255.255.255.255")
    let port = NWEndpoint.Port(rawValue: 9)!
    let parameters = NWParameters.udp
    if let interface {
        parameters.requiredInterface = interface
    }
    let connection = NWConnection(host: host, port: port, using: parameters)

    let packet: Data? = {
        var packet = Data()
        // Create the header with 6 bytes of FF
        for _ in 0 ..< 6 {
            packet.append(0xFF)
        }

        // Parse MAC address and append it 16 times to the packet
        let macBytes = macAddress.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard macBytes.count == 6 else {
            Log.connection.error("Invalid MAC address")
            return nil
        }

        for _ in 0 ..< 16 {
            packet.append(contentsOf: macBytes)
        }
        return packet
    }()

    guard let packet else {
        return false
    }

    let timeout = DispatchTime.now() + .seconds(5) // Set a 5-second timeout
    let statusStream = AsyncStream { continuation in
        // Start a timer to handle timeout
        DispatchQueue.network.asyncAfter(deadline: timeout) {
            continuation.yield(false)
            connection.cancel()
        }

        connection.stateUpdateHandler = { state in
            if state == .ready {
                connection.send(content: packet, completion: NWConnection.SendCompletion.contentProcessed { error in
                    if let error {
                        Log.connection.error("Error sending WOL packet for MAC \(macAddress, privacy: .public): \(error, privacy: .public)")
                    } else {
                        Log.connection.notice("Sent WOL packet for address \(macAddress, privacy: .public)")
                    }
                    connection.cancel()
                    continuation.yield(true)
                })
            } else {
                switch state {
                case .failed:
                    continuation.yield(false)
                case .cancelled:
                    continuation.yield(false)
                default:
                    return
                }
            }
        }
        connection.start(queue: .network)
    }

    var iterator = statusStream.makeAsyncIterator()
    let canSendPacket = await iterator.next() ?? false

    if !canSendPacket {
        Log.connection.error("Unable to send WOL packet within 5 sec")
    }
    return canSendPacket
}
