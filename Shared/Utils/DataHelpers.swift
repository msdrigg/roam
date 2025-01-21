import Foundation

extension UInt64{
    func toData() -> Data {
        var copy = bigEndian
        return Data(bytes: &copy, count: 4)
    }

    init?(bigEndian data: Data) {
        guard data.count == 4 else { return nil }

        self = UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
    }
}

extension UInt32 {
    func toData() -> Data {
        var copy = bigEndian
        return Data(bytes: &copy, count: 4)
    }

    init?(bigEndian data: Data) {
        guard data.count == 4 else { return nil }

        self = UInt32(bigEndian: data.withUnsafeBytes { $0.load(as: UInt32.self) })
    }
}

extension UInt16 {
    func toData() -> Data {
        var copy = bigEndian
        return Data(bytes: &copy, count: 2)
    }

    init?(bigEndian data: Data) {
        guard data.count == 2 else { return nil }

        self = UInt16(bigEndian: data.withUnsafeBytes { $0.load(as: UInt16.self) })
    }
}
