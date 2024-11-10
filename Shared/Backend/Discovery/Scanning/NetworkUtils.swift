import Darwin
import Foundation
import Network

struct IP4Address: Comparable, Equatable, Strideable, Encodable {
    func distance(to other: IP4Address) -> Int {
        Int(other.address) - Int(address)
    }

    func advanced(by n: Int) -> IP4Address {
        let address = UInt32(Int(address) + n)
        return IP4Address(address: address)
    }

    typealias Stride = Int

    private let address: UInt32

    private init(address: UInt32) {
        self.address = address
    }

    init?(string: String) {
        guard let address = ipToUInt32(string) else {
            return nil
        }

        self.address = address
    }

    var addressString: String {
        uInt32ToIP(address)
    }

    func localNetworkRange(subnetMask: IP4Address) -> Range<IP4Address> {
        let networkAddressInt = address & subnetMask.address
        let broadcastAddressInt = networkAddressInt | ~subnetMask.address

        return IP4Address(address: networkAddressInt) ..< IP4Address(address: broadcastAddressInt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(addressString)
    }
}

struct Addressed4NetworkInterface: Encodable {
    let name: String
    let family: Int32
    let address: IP4Address
    let netmask: IP4Address
    let flags: UInt32
    let nwInterface: NWInterface?

    var isEthernetLike: Bool {
        nwInterface?.type == .wifi || nwInterface?.type == .wifi
    }

    var isIPV4: Bool {
        family == AF_INET
    }

    var isRunning: Bool {
        (flags & UInt32(IFF_RUNNING)) != 0
    }

    var isLoopback: Bool {
        (flags & UInt32(IFF_LOOPBACK)) != 0
    }

    var scannableIPV4NetworkRange: Range<IP4Address> {
        address.localNetworkRange(subnetMask: netmask)
    }

    func withNWInterface(_ iface: NWInterface?) -> Addressed4NetworkInterface {
        Addressed4NetworkInterface(
            name: name,
            family: family,
            address: address,
            netmask: netmask,
            flags: flags,
            nwInterface: iface
        )
    }

    // Custom encoding
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(family, forKey: .family)
        try container.encode(address, forKey: .address)
        try container.encode(netmask, forKey: .netmask)
        try container.encode(flags, forKey: .flags)
        try container.encode(isRunning, forKey: .isRunning)
        try container.encode(isLoopback, forKey: .isLoopback)
        try container.encode(isIPV4, forKey: .isIPv4)
        try container.encode(getFlagList(), forKey: .flagList)
    }

    func getFlagList() -> [String] {
        let flagBooleans: [(String, Int32)] = [
            ("UP", IFF_UP),
            ("BROADCAST", IFF_BROADCAST),
            ("DEBUG", IFF_DEBUG),
            ("LOOPBACK", IFF_LOOPBACK),
            ("POINTOPOINT", IFF_POINTOPOINT),
            ("NOTRAILERS", IFF_NOTRAILERS),
            ("RUNNING", IFF_RUNNING),
            ("NOARP", IFF_NOARP),
            ("PROMISC", IFF_PROMISC),
            ("ALLMULTI", IFF_ALLMULTI),
            ("OACTIVE", IFF_OACTIVE),
            ("SIMPLEX", IFF_SIMPLEX),
            ("MULTICAST", IFF_MULTICAST),
            ("NOARP", IFF_NOARP),
            ("ALTPHYS", IFF_ALTPHYS),
            ("LINK0", IFF_LINK0),
            ("LINK1", IFF_LINK1),
            ("LINK2", IFF_LINK2),
        ]

        var flagStrings: [String] = []
        for (flag, value) in flagBooleans where flags & UInt32(value) != 0  {
            flagStrings.append(flag)
        }

        return flagStrings
    }

    // Custom coding keys
    private enum CodingKeys: String, CodingKey {
        case name
        case family
        case address
        case netmask
        case flags
        case isRunning
        case isLoopback
        case isIPv4
        case flagList
    }
}

func allAddressedInterfaces() async -> [Addressed4NetworkInterface] {
    let darwinInterfaces = listInterfacesDarwin()
    let nwInterfaces = await listInterfacesNW()
    var combinedInterfaces: [Addressed4NetworkInterface] = []

    for netInterface in darwinInterfaces {
        if let matched = nwInterfaces.first(where: { $0.name == netInterface.name }) {
            combinedInterfaces.append(netInterface.withNWInterface(matched))
        }
    }

    return combinedInterfaces
}

private func ipToUInt32(_ ip: String) -> UInt32? {
    let segments = ip.split(separator: ".")
    guard segments.count == 4 else { return nil }

    var result: UInt32 = 0
    for segment in segments {
        guard let octet = UInt32(segment), octet < 256 else { return nil }
        result = (result << 8) + octet
    }

    return result
}

private func uInt32ToIP(_ intVal: UInt32) -> String {
    var remaining = intVal
    var segments: [UInt32] = []

    for _ in 0 ..< 4 {
        let segment = remaining & 0xFF
        segments.insert(segment, at: 0)
        remaining >>= 8
    }

    return segments.map(String.init).joined(separator: ".")
}

private func listInterfacesDarwin() -> [Addressed4NetworkInterface] {
    var addrList: UnsafeMutablePointer<ifaddrs>?
    var networkInterfaces: [Addressed4NetworkInterface] = []

    if getifaddrs(&addrList) == 0 {
        var ptr = addrList
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let addr = ptr?.pointee else { continue }

            let name = String(cString: addr.ifa_name)
            let flags = addr.ifa_flags
            let family = addr.ifa_addr?.pointee.sa_family ?? 0

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if let ifaAddr = addr.ifa_addr {
                getnameinfo(ifaAddr, socklen_t(ifaAddr.pointee.sa_len),
                            &host, socklen_t(host.count),
                            nil, socklen_t(0), NI_NUMERICHOST)
            }

            var netmask = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if let ifaNetmask = addr.ifa_netmask {
                getnameinfo(ifaNetmask, socklen_t(ifaNetmask.pointee.sa_len),
                            &netmask, socklen_t(netmask.count),
                            nil, socklen_t(0), NI_NUMERICHOST)
            }
            if family == AF_INET || family == AF_INET6 {
                let addressString = String(cString: host)
                let netmaskString = String(cString: netmask)
                if let address = IP4Address(string: addressString), let netmask = IP4Address(string: netmaskString) {
                    networkInterfaces.append(Addressed4NetworkInterface(
                        name: name,
                        family: Int32(family),
                        address: address,
                        netmask: netmask,
                        flags: flags,
                        nwInterface: nil
                    ))
                }
            }
        }
        freeifaddrs(addrList)
    }
    return networkInterfaces
}

private func listInterfacesNW() async -> [NWInterface] {
    let monitor = NWPathMonitor()
    monitor.start(queue: DispatchQueue.global())

    var matchedNWInterfacesStream = AsyncStream { continuation in
        monitor.pathUpdateHandler = { path in
            continuation.yield(path.availableInterfaces)
        }
    }.makeAsyncIterator()
    let matchedNWInterfaces = await matchedNWInterfacesStream.next()

    monitor.cancel()
    return matchedNWInterfaces ?? []
}
