import Foundation

extension UInt64{
    func toData() -> Data {
        var copy = bigEndian
        return Data(bytes: &copy, count: 8)
    }

    init?(bigEndian data: Data) {
        guard data.count >= MemoryLayout<UInt64>.size else { return nil }
        guard let val = data.withUnsafeBytes({ bytes in
            bytes.bindMemory(to: UInt64.self).baseAddress?.pointee
        })?.bigEndian
        else { return nil }
        self = val
    }
}

extension UInt32 {
    func toData() -> Data {
        var copy = bigEndian
        return Data(bytes: &copy, count: 4)
    }

    init?(bigEndian data: Data) {
        guard data.count >= MemoryLayout<UInt32>.size else { return nil }
        guard let val = data.withUnsafeBytes({ bytes in
            bytes.bindMemory(to: UInt32.self).baseAddress?.pointee
        })?.bigEndian
        else { return nil }
        self = val
    }
}

extension UInt16 {
    func toData() -> Data {
        var copy = bigEndian
        return Data(bytes: &copy, count: 2)
    }

    init?(bigEndian data: Data) {
        guard data.count >= MemoryLayout<UInt16>.size else { return nil }
        guard let val = data.withUnsafeBytes({ bytes in
            bytes.bindMemory(to: UInt16.self).baseAddress?.pointee
        })?.bigEndian
        else { return nil }
        self = val
    }
}
