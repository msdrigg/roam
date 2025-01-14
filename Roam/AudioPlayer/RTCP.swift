import Foundation
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "RTCP"
)

enum RtcpPacket {
    case receiverReport(RtcpReceiverReport)
    case senderReport(RtcpSenderReport)
    case appSpecific(RtcpAppSpecific)
    case unknown(RtcpUnknown)
    case bye(RtcpBye)

    static func vdly(delayMs: UInt32) -> RtcpPacket {
        .appSpecific(.vdly(RtcpVdly(delayMs: delayMs)))
    }

    static func cver(clientVersion: UInt32) -> RtcpPacket {
        .appSpecific(.cver(RtcpCver(clientVersion: clientVersion)))
    }

    static func report() -> RtcpPacket {
        .receiverReport(RtcpReceiverReport(ssrc: 0, reportBlocks: []))
    }

    init?(data: Data) {
        //         0                   1                   2                   3
        //         0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
        //        +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        // header |V=2|P| Subtype |      PT       |             length            |
        //        +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        //        |                          ...                                  |
        //   body +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        guard data.count >= 4 else {
            return nil
        }

        let firstByte = data[0]
        let version = firstByte >> 6
        // Padding (Currently unused
        _ = (firstByte & 0x20) == 0x20
        let subtypeData = firstByte & 0x1F
        let packetType = data[1]

        let data = data.dropFirst(2)

        if version != 2 {
            logger.warning("Bad rtcp packet recevied with version = \(version, privacy: .public). Expected version = 2")
            return nil
        }

        let lengthData = data.prefix(2)
        if UInt16(bigEndian: lengthData) == nil {
            return nil
        }

        let packetData = data.dropFirst(2)

        switch packetType {
        case 200:
            self = Self.senderReport(RtcpSenderReport(data: packetData))
        case 201:
            guard let packet = RtcpReceiverReport(data: packetData) else {
                logger.warning("Bad receiver report recevied with data \(packetData, privacy: .public)")
                return nil
            }
            self = Self.receiverReport(packet)
        case 203:
            guard let packet = RtcpBye(data: packetData) else {
                logger.warning("Bad bye packet recevied with data \(packetData, privacy: .public)")
                return nil
            }
            self = Self.bye(packet)
        case 204:
            guard let packet = RtcpAppSpecific(subtypeData: subtypeData, packet: packetData) else {
                logger.warning("Bad app packet recevied with data \(packetData, privacy: .public)")
                return nil
            }
            self = Self.appSpecific(packet)
        default:
            self = Self.unknown(RtcpUnknown(packetType: packetType, data: packetData, subtypeData: subtypeData))
        }
    }

    func packet() -> Data {
        var packet = Data()

        // Extract packet data and related values
        let (packetData, subtypeData, packetType): (Data, UInt8, UInt8)
        switch self {
        case let .receiverReport(inner):
            packetData = inner.packetData()
            subtypeData = inner.subtypeData()
            packetType = RtcpReceiverReport.packetType
        case let .bye(inner):
            packetData = inner.packetData()
            subtypeData = inner.subtypeData()
            packetType = RtcpBye.packetType
        case let .senderReport(inner):
            packetData = inner.packetData()
            subtypeData = inner.subtypeData()
            packetType = RtcpSenderReport.packetType
        case let .appSpecific(inner):
            packetData = inner.packetData()
            subtypeData = inner.subtypeData()
            packetType = RtcpAppSpecific.packetType
        case let .unknown(inner):
            packetData = inner.data
            subtypeData = inner.subtypeData
            packetType = inner.packetType
        }

        // First byte: Version, Padding and Subtype
        let vPSt: UInt8 = (2 << 6) | (0 << 5) | subtypeData
        packet.append(vPSt)

        // Second byte: Packet Type
        packet.append(packetType)

        // Length: 16 bits, in 32-bit words minus one
        let length = UInt16(packetData.count / 4)
        packet.append(length.toData())

        // Packet data
        packet.append(packetData)

        return packet
    }
}

struct RtcpUnknown {
    let packetType: UInt8
    let data: Data
    let subtypeData: UInt8
}

struct RtcpReceiverReport {
    let reportBlocks: [ReceiverReportBlock]
    let ssrc: UInt32

    static let packetType: UInt8 = 201

    func subtypeData() -> UInt8 {
        UInt8(reportBlocks.count)
    }

    func packetData() -> Data {
        ssrc.toData()
    }

    init?(data _: Data) {
        nil
    }

    init(ssrc: UInt32, reportBlocks: [ReceiverReportBlock]) {
        self.reportBlocks = reportBlocks
        self.ssrc = ssrc
    }
}

struct RtcpBye {
    let ssrc: [UInt32]

    static let packetType: UInt8 = 203

    func subtypeData() -> UInt8 {
        UInt8(ssrc.count)
    }

    func packetData() -> Data {
        var data = Data()
        ssrc.map { $0.toData() }.forEach {
            data.append($0)
        }
        return data
    }

    init?(data _: Data) {
        nil
    }

    init(ssrc: [UInt32]) {
        self.ssrc = ssrc
    }

    init(ssrc: UInt32) {
        self.ssrc = [ssrc]
    }
}

struct ReceiverReportBlock {}

struct RtcpSenderReport {
    static let packetType: UInt8 = 200
    let data: Data

    func subtypeData() -> UInt8 {
        UInt8.zero
    }

    func packetData() -> Data {
        Data()
    }
}

enum RtcpAppSpecific {
    case ncli(RtcpNcli)
    case cver(RtcpCver)
    case xdly(RtcpXdly)
    case vdly(RtcpVdly)
    case other(RtcpUnknownApp)

    static let packetType: UInt8 = 204

    init?(subtypeData: UInt8, packet: Data) {
        logger
            .trace(
                "Initing app packet with stData \(subtypeData), packet \(packet.map { String(format: "%02x", $0) }.joined()))"
            )
        // SSRC Data. Always 0 for our use case
        _ = packet.prefix(4)
        let nameData = packet.dropFirst(4).prefix(4)
        guard let name = String(data: nameData, encoding: .utf8) else {
            logger.warning("Bad data for name in app data \(nameData, privacy: .public)")
            return nil
        }

        switch name {
        case "VDLY":
            guard let subPacket = RtcpVdly(data: packet.dropFirst(8)) else {
                return nil
            }
            self = Self.vdly(subPacket)
        case "XDLY":
            guard let subPacket = RtcpXdly(data: packet.dropFirst(8)) else {
                return nil
            }
            self = Self.xdly(subPacket)
        case "NCLI":
            self = Self.ncli(RtcpNcli())
        case "CVER":
            guard let subPacket = RtcpCver(data: packet.dropFirst(8)) else {
                return nil
            }
            self = Self.cver(subPacket)
        default:
            self = Self.other(RtcpUnknownApp(name: name, subtypeData: subtypeData, packetContent: packet.dropFirst(8)))
        }
    }

    func subtypeData() -> UInt8 {
        UInt8.zero
    }

    func packetData() -> Data {
        //        0                   1                   2                   3
        //        0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
        //       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        //       |V=2|P| subtype |   PT=APP=204  |             length            |
        //       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        //       |                           SSRC/CSRC                           |
        //       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        //       |                          name (ASCII)                         |
        //       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        //       |                   application-dependent data                ...
        //       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        var packet = Data()

        // Determine the 'name' and 'packetData' based on the enum case
        // SAFETY: We know name is a utf8 encoded string
        let (nameData, packetData): (Data, Data)
        switch self {
        case let .ncli(inner):
            nameData = RtcpNcli.NAME.data(using: .utf8)!
            packetData = inner.packetContent()
        case let .cver(inner):
            nameData = RtcpCver.NAME.data(using: .utf8)!
            packetData = inner.packetContent()
        case let .xdly(inner):
            nameData = RtcpXdly.NAME.data(using: .utf8)!
            packetData = inner.packetContent()
        case let .vdly(inner):
            nameData = RtcpVdly.NAME.data(using: .utf8)!
            packetData = inner.packetContent()
        case let .other(inner):
            nameData = inner.name.data(using: .utf8)!
            packetData = inner.packetContent
        }
        // SSRC/CSRC (assuming you have a value for it)
        packet.append(globalSSRC.toData())

        packet.append(nameData)

        // Packet data
        packet.append(packetData)

        return packet
    }
}

let globalSSRC: UInt32 = 0
let rtcpVersion: UInt8 = 2
let rtcpPadding: UInt8 = 0
let rtcpTypeApp: UInt8 = 204
let rtcpTypeReceiverReport: UInt8 = 201
let rtcpTypeSenderReport: UInt8 = 200

struct RtcpVdly {
    let delayMicroseconds: UInt32

    static let NAME: String = "VDLY"

    func packetContent() -> Data {
        delayMicroseconds.toData()
    }

    init(delayMs: UInt32) {
        delayMicroseconds = delayMs * 1000
    }

    init?(data: Data) {
        guard let delay = UInt32(bigEndian: data) else {
            logger.warning("Bad data for vdly delay in app data \(data, privacy: .public)")
            return nil
        }
        delayMicroseconds = delay
    }
}

struct RtcpXdly {
    let delayMicroseconds: UInt32

    static let NAME: String = "XDLY"

    func packetContent() -> Data {
        delayMicroseconds.toData()
    }

    init?(data: Data) {
        guard let delay = UInt32(bigEndian: data) else {
            logger.warning("Bad data for vdly delay in app data \(data, privacy: .public)")
            return nil
        }
        delayMicroseconds = delay
    }
}

struct RtcpNcli {
    static let NAME: String = "NCLI"

    func packetContent() -> Data {
        Data()
    }
}

struct RtcpCver {
    let clientVersion: UInt32

    static let NAME: String = "CVER"

    func packetContent() -> Data {
        clientVersion.toData()
    }

    init(clientVersion: UInt32) {
        self.clientVersion = clientVersion
    }

    init?(data: Data) {
        guard let clientVersion = UInt32(bigEndian: data) else {
            logger.warning("Bad data for client version in app data \(data, privacy: .public)")
            return nil
        }
        self.clientVersion = clientVersion
    }
}

struct RtcpUnknownApp {
    let name: String
    let subtypeData: UInt8
    let packetContent: Data
}
