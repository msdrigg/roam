import Foundation
import Opus
import RTP

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
