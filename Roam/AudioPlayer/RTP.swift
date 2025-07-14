import Foundation
import Opus

struct RtpPacket: Comparable, Sendable {
    static func < (lhs: RtpPacket, rhs: RtpPacket) -> Bool {
        lhs.sequenceNumber > rhs.sequenceNumber
    }

    static func == (lhs: RtpPacket, rhs: RtpPacket) -> Bool {
        lhs.sequenceNumber == rhs.sequenceNumber
    }

    private let packet: Packet
    let receivedAt: UInt64
    var sequenceNumber: Int64

    var unwrappedSequenceNumber: UInt16 {
        packet.sequenceNumber
    }

    /// Updates self to account for any wrapping and returns the new rolling sequence number
    mutating func updateWithRollingSequenceNumber(_ rollingSequenceNumber: Int64?) -> Int64 {
        var rls = rollingSequenceNumber ?? Int64(packet.sequenceNumber)
        let wrappedSeq = Int64(packet.sequenceNumber)
        let wrappedMax = Int64(UInt16.max)
        let diff = wrappedSeq - (rls % (wrappedMax + 1))

        if diff < -wrappedMax / 2 {
            rls = rls + diff + wrappedMax + 1
        } else if diff >= -wrappedMax / 2, diff <= wrappedMax / 2 {
            rls += diff
        }

        sequenceNumber = Int64(packet.sequenceNumber) + rls - (rls % Int64(UInt16.max))

        return rls
    }

    var payloadType: PayloadType {
        packet.payloadType
    }

    var timestamp: Timestamp {
        packet.timestamp
    }

    var ssrc: UInt32 {
        packet.ssrc
    }

    var payload: Data {
        packet.payload
    }

    var validOpus: Bool {
        packet.payloadType.rawValue == globalRTPPayloadType
    }

    init(data: Data) throws {
        packet = try Packet(from: data)
        receivedAt = mach_absolute_time()
        sequenceNumber = Int64(packet.sequenceNumber)
    }
}

// Packet represents an individual RTP packet.
private struct Packet: Sendable {
    static let version: UInt8 = 2
    static let versionMask: UInt8 = 0b1100_0000
    static let paddingMask: UInt8 = 0b0010_0000
    static let extensionMask: UInt8 = 0b0001_0000
    static let csrcCountOffset = 0
    static let csrcCountMask: UInt8 = 0b0000_1111
    static let maxCSRCs = 15
    static let markerOffset = 1
    static let markerMask: UInt8 = 0b1000_0000
    static let payloadTypeOffset = 1
    static let payloadTypeMask: UInt8 = 0b0111_1111
    static let sequenceOffset = 2
    static let timestampOffset = 4
    static let ssrcOffset = 8
    static let csrcOffset = 12
    static let headerSize = csrcOffset

    public let payloadType: PayloadType
    public let marker: Bool
    public let sequenceNumber: SequenceNumber
    public let timestamp: Timestamp
    public let ssrc: SourceID
    public let csrcs: [SourceID]?
    public let `extension`: Extension?
    public let payload: Data
    public let padding: UInt8

    var payloadWithoutPadding: Data {
        payload[0..<payload.count - Int(padding)]
    }

    var encodedSize: Int {
        let csrcsSize = csrcs?.count ?? 0 * MemoryLayout<SourceID>.size
        let extensionSize = `extension`?.encodedSize ?? 0
        return Self.headerSize + csrcsSize + extensionSize + payload.count + Int(padding)
    }

    public init(from data: Data) throws {
        if data.count < Self.headerSize {
            throw EncodingError.dataTooSmall(Self.headerSize)
        }

        // Parse first octect (version, padding, extension)
        let version = (data[0] & Self.versionMask) >> 6
        if version != Self.version {
            throw EncodingError.unknownVersion(version)
        }
        let hasPadding = (data[0] & Self.paddingMask) != 0
        let hasExtension = (data[0] & Self.extensionMask) != 0
        let sizeWithPaddingAndExtension = Self.headerSize + (hasPadding ? 1 : 0) + (hasExtension ? Extension.headerSize : 0)

        // Parse second octet
        marker = (data[Self.markerOffset] & Self.markerMask) != 0
        let csrcCount = Int(data[Self.csrcCountOffset] & Self.csrcCountMask)
        let csrcSize = csrcCount * MemoryLayout<SourceID>.size
        let sizeWithCSRCs = sizeWithPaddingAndExtension + csrcSize
        if data.count < sizeWithCSRCs {
            throw EncodingError.dataTooSmall(sizeWithCSRCs)
        }
        payloadType = PayloadType(data[Self.payloadTypeOffset] & Self.payloadTypeMask)

        // Parse sequence number from octets 3-4
        sequenceNumber = data.big(at: Self.sequenceOffset)

        // Parse timestamp from octets 5-8
        timestamp = data.big(at: Self.timestampOffset)

        // Parse SSRC from octets 9-12
        ssrc = data.big(at: Self.ssrcOffset)

        // Parse optional CSRCs in octets 13+
        if csrcCount > 0 {
            csrcs = (0..<csrcCount).map {
                data.big(at: Self.csrcOffset + $0)
            }
        } else {
            csrcs = nil
        }

        // Read extension
        let extensionOffset = Self.csrcOffset + csrcSize
        `extension` = hasExtension ? try Extension(from: data[extensionOffset...]) : nil

        // Read payload
        let payloadOffset = extensionOffset + (`extension`?.encodedSize ?? 0)
        padding = hasPadding ? UInt8(data[data.count - 1]) : 0
        if data.count - payloadOffset - Int(padding) < 0 {
            throw EncodingError.paddingTooLarge(padding)
        }
        payload = data[payloadOffset...]
    }
}

private struct Extension: Sendable {
    public typealias ProfileID = UInt16

    static let headerSize = 4
    static let profileIDOffset = 0
    static let sizeOffset = 2

    public let profileID: ProfileID
    public let payload: Data

    public var encodedSize: Int {
        Self.headerSize + payload.count
    }

    public init(from data: Data) throws {
        if data.count < Self.headerSize {
            throw EncodingError.extensionDataTooSmall(Self.headerSize)
        }

        profileID = data.big(at: Self.profileIDOffset)
        let payloadSize = data.big(at: Self.sizeOffset) * MemoryLayout<UInt32>.size
        let size = Self.headerSize + payloadSize
        if data.count < size {
            throw EncodingError.extensionDataTooSmall(size)
        }

        payload = data[Self.headerSize..<size]
    }
}

private enum EncodingError: Error {
    case unknownVersion(_ version: UInt8)
    case dataTooSmall(_ expected: Int)
    case extensionDataTooSmall(_ expected: Int)
    case paddingTooLarge(_ padding: UInt8)
}

public struct PayloadType: ExpressibleByIntegerLiteral, RawRepresentable, Equatable, Sendable {
    public typealias IntegerLiteralType = UInt8

    public static let marker: Self = 0b1000_0000
    public static let opus: Self = 111

    public var rawValue: IntegerLiteralType

    public init(integerLiteral value: IntegerLiteralType) {
        rawValue = value
    }

    public init?(rawValue: IntegerLiteralType) {
        self.rawValue = rawValue
    }

    public init(_ value: IntegerLiteralType) {
        self.init(integerLiteral: value)
    }
}

private typealias SourceID = UInt32
private typealias SequenceNumber = UInt16
typealias Timestamp = UInt32

private extension Data {
    func big<T: FixedWidthInteger>(at offset: Int) -> T {
        var value: T = 0
        withUnsafeMutablePointer(to: &value) {
            self.copyBytes(to: UnsafeMutableBufferPointer(start: $0, count: 1), from: offset..<offset + MemoryLayout<T>.size)
        }
        return T(bigEndian: value)
    }
}
