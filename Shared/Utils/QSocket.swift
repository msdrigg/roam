/// A namespace for helpers that work with BSD Sockets addresses.
///
/// These convert between IP address strings and the `sockaddr` pointers used by
/// the BSD Sockets API. For example, here’s how you can call `connect` with an
/// IP address and string.
///
/// ```swift
/// let success = try QSockAddr.withSockAddr(address: "1.2.3.4", port: 12345) { sa, saLen in
///     connect(fd, sa, saLen) >= 0
/// }
/// ```
///
/// This example calls ``withSockAddr(address:port:_:)``, which is what you use
/// when passing an address into BSD Sockets. There’s also
/// ``fromSockAddr(sa:saLen:)``, to use when getting an address back from BSD
/// Sockets.
///
/// > important: Representing addresses as strings is potentially very
/// inefficient.  For example, if you were to wrap the BSD Sockets `sendto` call
/// in this way, you would end up doing a string-to-address conversion every
/// time you sent a datagram!  However, it _is_ very convenient, making it perfect
/// for small test projects, wrapping weird low-level APIs, and so on.
///
/// Keep in mind that I rarely use BSD Sockets for _networking_ these days.
/// Apple platforms have better networking APIs; see TN3151 [Choosing the right
/// networking API][tn3151] for the details.
///
/// [tn3151]: <[TN3151: Choosing the right networking API | Apple Developer Documentation](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api)>

import Foundation
import Darwin
import System

public enum QSockAddr {
}

extension QSockAddr {
    /// Calls a closure with a socket address and length.
    ///
    /// Use this to pass an address in to a BSD Sockets call. For example:
    ///
    /// ```swift
    /// let success = try QSockAddr.withSockAddr(address: "1.2.3.4", port: 12345) { sa, saLen in
    ///     connect(fd, sa, saLen) >= 0
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - address: The address as a string. This can be either an IPv4 or IPv6
    ///   address, in any format accepted by `getaddrinfo` when the
    ///   `AI_NUMERICHOST` flag is set.
    ///   - port: The port number.
    ///   - body: A closure to call with the corresponding `sockaddr` pointer
    ///   and length.
    /// - Returns: The value returned by that closure.

    public static func withSockAddr<ReturnType>(
        address: String,
        port: UInt16,
        _ body: (_ sa: UnsafePointer<sockaddr>, _ saLen: socklen_t) throws -> ReturnType
    ) throws -> ReturnType {
        var addrList: UnsafeMutablePointer<addrinfo>?
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV
        let err = getaddrinfo(address, "\(port)", &hints, &addrList)
        guard err == 0 else { throw QSockAddr.NetDBError(code: err) }
        guard let addr = addrList else { throw QSockAddr.NetDBError(code: EAI_NODATA) }
        defer { freeaddrinfo(addrList) }
        return try body(addr.pointee.ai_addr, addr.pointee.ai_addrlen)
    }
}

extension QSockAddr {
    /// Creates an address by calling a closure to fill in a socket address and
    /// length.
    ///
    /// Use this to get an address back from a BSD Sockets call. For example:
    ///
    /// ```swift
    /// let peer = try QSockAddr.fromSockAddr() { sa, saLen in
    ///     getpeername(fd, sa, &saLen) >= 0
    /// }
    /// guard peer.result else { … something went wrong … }
    /// … use peer.address and peer.port …
    /// ```
    ///
    /// - Parameter body: The closure to call. It passes this a mutable pointer
    /// to a `sockaddr` and an `inout` length. The closure is expected to
    /// populate that memory with an IPv4 or IPv6 address, or throw an error.
    /// - Returns: A tuple containing the closure result, the address string,
    /// and the port.

    public static func fromSockAddr<ReturnType>(
        _ body: (_ sa: UnsafeMutablePointer<sockaddr>, _ saLen: inout socklen_t) throws -> ReturnType
    ) throws -> (result: ReturnType, address: String, port: UInt16) {
        var ss = sockaddr_storage()
        var saLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
        return try withUnsafeMutablePointer(to: &ss) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                let result = try body(sa, &saLen)
                let (address, port) = try fromSockAddr(sa: sa, saLen: saLen)
                return (result, address, port)
            }
        }
    }
}

extension QSockAddr {
    /// Creates an address from an address pointer and length.
    ///
    /// Use this when you have an existing `sockaddr` pointer, for example, when
    /// working with `getifaddrs`.
    ///
    /// - Parameters:
    ///   - sa: The address pointer
    ///   - saLen: The address length.
    /// - Returns: A tuple containing the address string, and the port.

    public static func fromSockAddr(sa: UnsafeMutablePointer<sockaddr>, saLen: socklen_t) throws -> (address: String, port: UInt16) {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var serv = [CChar](repeating: 0, count: Int(NI_MAXSERV))
        let err = getnameinfo(sa, saLen, &host, socklen_t(host.count), &serv, socklen_t(serv.count), NI_NUMERICHOST | NI_NUMERICSERV)
        guard err == 0 else { throw QSockAddr.NetDBError(code: err) }
        guard let port = UInt16(String(cString: serv)) else { throw QSockAddr.NetDBError(code: EAI_SERVICE) }
        return (String(cString: host), port)
    }
}

extension QSockAddr {
    /// Wraps an error coming from the DNS subsytem.
    ///
    /// The code values correspond to `EAI_***` in `<netdb.h>`.

    struct NetDBError: Error {
        var code: CInt
    }
}

extension QSockAddr {
    /// Returns a list of interfaces that have an associated IPv4 or IPv6
    /// address.
    ///
    /// Equivalent to the `getifaddrs` BSD Sockets call.
    ///
    /// The list is in the same order as that returned by `getifaddrs`.
    /// ```

    public static func interfaceNamesAndAddresses() -> [(name: String, address: String)] {
        var addrList: UnsafeMutablePointer<ifaddrs>?
        let err = getifaddrs(&addrList)
        // In theory we could check `errno` here but, honestly, what are gonna
        // do with that info?
        guard
            err >= 0,
            let first = addrList
        else { return [] }
        defer { freeifaddrs(addrList) }
        return sequence(first: first, next: { $0.pointee.ifa_next })
            .compactMap { addr in
                guard
                    let name = addr.pointee.ifa_name,
                    let sa = addr.pointee.ifa_addr,
                    [AF_INET, AF_INET6].contains(CInt(sa.pointee.sa_family)),
                    let (address, _) = try? QSockAddr.fromSockAddr(sa: sa, saLen: socklen_t(sa.pointee.sa_len))
                else { return nil }
                return (String(cString: name), address)
            }
    }
}

extension QSockAddr {

    public static func interfaceNames() -> [String] {
        interfaceNamesAndAddresses()
            .map { $0.name }
    }

    public static func interfaceAddresses() -> [String] {
        interfaceNamesAndAddresses()
            .map { $0.address }
    }

    public static func addressesByInterface() -> [String: [String]] {
        interfaceNamesAndAddresses()
            .reduce(into: [:]) { soFar, i in
                soFar[i.name, default: []].append(i.address)
            }
    }
}

// Calls a closure that might fail with `EINTR`.
///
/// This calls the supplied closure and, if it returns a negative value,
/// extracts the error from `errno`.  If `retryOnInterrupt` on interrupt is set
/// and the error is `EINTR`, it repeats the call.  Otherwise it throws that
/// error.
///
/// This is marked with `@discardableResult` because in many cases, like
/// `setsockopt`, the result isn’t relevant.
///
/// - Parameters:
///   - retryOnInterrupt: If true, check for `EINTR` and call the closure again.
///   - body: The closure to call.
/// - Returns: The closure result. This will not be negative.

@discardableResult
public func errnoQ<Result: SignedInteger>(retryOnInterrupt: Bool, _ body: () -> Result) throws -> Result {
    repeat {
        let result = body()
        let e = Foundation.errno
        if result >= 0 {
            return result
        }
        if retryOnInterrupt && e == Foundation.EINTR {
            continue
        }
        throw Errno(rawValue: e)
    } while true
}

extension FileDescriptor {

    /// Connects a socket to an address.
    ///
    /// Equivalent to the `connect` BSD Sockets call.
    ///
    /// The `ignoreInProgressError` parameter defaults to false.  If you set it,
    /// the call treats an `EINPROGRESS` error as success.  Do this for a
    /// non-blocking connect, where you monitor the connection status using
    /// `select` or one of its friends.

    public func connect(_ address: String, _ port: UInt16, ignoreInProgressError: Bool = false, retryOnInterrupt: Bool = true) throws {
        _ = try QSockAddr.withSockAddr(address: address, port: port) { sa, saLen in
            try errnoQ(retryOnInterrupt: retryOnInterrupt) {
                var err = Foundation.connect(self.rawValue, sa, saLen)
                if err < 0 && errno == EINPROGRESS {
                    err = 0
                }
                return err
            }
        }
    }
}

extension FileDescriptor {

    /// Configures a socket for listening.
    ///
    /// Equivalent to the `listen` BSD Sockets call.

    public func listen(_ backlog: CInt, retryOnInterrupt: Bool = true) throws {
        try errnoQ(retryOnInterrupt: retryOnInterrupt) {
            Foundation.listen(self.rawValue, backlog)
        }
    }

    /// Accepts an incoming connection
    ///
    /// Equivalent to the `accept` BSD Sockets call when you pass `NULL` to the
    /// `address` and `address_len` parameters.  If you need the connection’s
    /// remote address, call ``getPeerName(retryOnInterrupt:)``.
    public func accept(retryOnInterrupt: Bool = true) throws -> FileDescriptor {
        let newSocket = try errnoQ(retryOnInterrupt: retryOnInterrupt) {
            Foundation.accept(self.rawValue, nil, nil)
        }
        return FileDescriptor(rawValue: newSocket)
    }

    public func bind(_ sa: UnsafePointer<sockaddr>, _ saLen: socklen_t, retryOnInterrupt: Bool = true) throws -> FileDescriptor {
        let newSocket = try errnoQ(retryOnInterrupt: retryOnInterrupt) {
            Foundation.bind(self.rawValue, sa, saLen)
        }
        return FileDescriptor(rawValue: newSocket)
    }

}

extension FileDescriptor {
    /// Gets the socket’s local address.
    ///
    /// Equivalent to the `getsockname` BSD Sockets call.
    public func getSockName(retryOnInterrupt: Bool = true) throws -> (address: String, port: UInt16) {
        let result = try QSockAddr.fromSockAddr { sa, saLen in
            try errnoQ(retryOnInterrupt: retryOnInterrupt) {
                Foundation.getsockname(self.rawValue, sa, &saLen)
            }
        }
        return (result.address, result.port)
    }
}

extension FileDescriptor {
    /// Creates a socket.
    ///
    /// Equivalent to the `socket` BSD Sockets call.

    public static func socket(_ domain: CInt, _ type: CInt, _ proto: CInt, retryOnInterrupt: Bool = true) throws -> FileDescriptor {
        let socket = try errnoQ(retryOnInterrupt: retryOnInterrupt) {
            Foundation.socket(domain, type, proto)
        }
        return FileDescriptor(rawValue: socket)
    }
}

extension FileDescriptor {
    /// Gets a socket option.
    ///
    /// Equivalent to the `getsockopt` BSD Sockets call.
    ///
    /// For simple socket options, consider using
    /// ``getSocketOption(_:_:as:retryOnInterrupt:)``.

    public func getSocketOption(_ level: CInt, _ name: CInt, _ optionValue: UnsafeMutableRawPointer, optionLen: inout Int, retryOnInterrupt: Bool = true) throws {
        guard var optionSockLen = socklen_t(exactly: optionLen), optionLen >= 0 else { fatalError() }
        try errnoQ(retryOnInterrupt: retryOnInterrupt) {
            Foundation.getsockopt(self.rawValue, level, name, optionValue, &optionSockLen)
        }
        optionLen = Int(optionSockLen)
    }

    /// Sets a socket option.
    ///
    /// Equivalent to the `setsockopt` BSD Sockets call.
    ///
    /// For simple socket options, consider using
    /// ``setSocketOption(_:_:_:retryOnInterrupt:)``.

    public func setSocketOption(_ level: CInt, _ name: CInt, _ optionValue: UnsafeRawPointer, _ optionLen: Int, retryOnInterrupt: Bool = true) throws {
        guard let optionSockLen = socklen_t(exactly: optionLen), optionLen >= 0 else { fatalError() }
        try errnoQ(retryOnInterrupt: retryOnInterrupt) {
            Foundation.setsockopt(self.rawValue, level, name, optionValue, optionSockLen)
        }
    }
}

extension FileDescriptor {

    /// Gets a simple socket option.
    ///
    /// This allows you to get a simple socket option without messing around
    /// with the unsafe pointer malarkely involved in
    /// ``getSocketOption(_:_:_:optionLen:retryOnInterrupt:)``.  See
    /// `QSocketOptionConvertible` for more about how this works.

    public func getSocketOption<T>(_ level: CInt, _ name: CInt, as: T.Type, retryOnInterrupt: Bool = true) throws -> T
        where T: QSocketOptionConvertible
    {
        var result = T()
        try withUnsafeMutableBytes(of: &result) { buf in
            var bufCount = buf.count
            try self.getSocketOption(level, name, buf.baseAddress!, optionLen: &bufCount, retryOnInterrupt: retryOnInterrupt)
            guard bufCount == buf.count else {
                throw Errno.noBufferSpace
            }
        }
        return result
    }
    /// Sets a simple socket option.
    ///
    /// This allows you to set a simple socket option without messing around
    /// with the unsafe pointer malarkely involved in
    /// ``setSocketOption(_:_:_:_:retryOnInterrupt:)``.  See
    /// ``QSocketOptionConvertible`` for more about how this works.

    public func setSocketOption<T>(_ level: CInt, _ name: CInt, _ optionValue: T, retryOnInterrupt: Bool = true) throws
        where T: QSocketOptionConvertible
    {
        // Can’t use `&value` because of a new compiler warning.  We work around
        // that per the [docs][ref]. One day there may be a ‘bitwise copyable’
        // protocol that we can add to `QSocketOptionConvertible` to actually
        // expression what’s going on here at the type layer.
        //
        // [ref]: <https://github.com/atrick/swift-evolution/blob/diagnose-implicit-raw-bitwise/proposals/nnnn-implicit-raw-bitwise-conversion.md#workarounds-for-common-cases>
        var value = optionValue
        try withUnsafeBytes(of: &value) { buf in
            try self.setSocketOption(level, name, buf.baseAddress!, buf.count, retryOnInterrupt: retryOnInterrupt)
        }
    }
}

extension FileDescriptor {

    /// Sends a datagram to an address.
    ///
    /// Equivalent to the `sendto` BSD Sockets call.
    ///
    /// If you’re working with a TCP socket, use
    /// ``write(data:retryOnInterrupt:)`` method.
    ///
    /// - important: This builds the destination address from the supplied
    /// string every time you send a datagram.  That’s horribly inefficient.
    /// That’s not a problem given the design constraints of this package but,
    /// oh gosh, don’t use this in a real project.
    ///
    /// If the socket is non-blocking, be prepare for this to throw `EAGAIN`.
    ///
    /// The result is discardable because this method is most commonly used with
    /// a UDP socket and that’s all or nothing.

    @discardableResult
    func send(data: Data, flags: CInt = 0, to destination: (address: String, port: UInt16), retryOnInterrupt: Bool = true) throws -> Int {
        try data.withUnsafeBytes { buf in
            try QSockAddr.withSockAddr(address: destination.address, port: destination.port) { sa, saLen in
                try errnoQ(retryOnInterrupt: retryOnInterrupt) {
                    // If `count` is 0 then `baseAddress` might be zero.  We’re
                    // assuming that the `sendto` call will be OK with that.
                    Foundation.sendto(self.rawValue, buf.baseAddress, buf.count, flags, sa, saLen)
                }
            }
        }
    }

    /// Receive a datagram and its source address.
    ///
    /// Equivalent to the `recvfrom` BSD Sockets call.
    ///
    /// If you’re working with a TCP socket, use the
    /// ``read(maxCount:retryOnInterrupt:)`` method.
    ///
    /// - important: This builds the destination address string from the
    /// returned address every time you receive a datagram.  That’s horribly
    /// inefficient. That’s not a problem given the design constraints of this
    /// package but, oh gosh, don’t use this in a real project.
    ///
    /// If the socket is non-blocking, be prepare for this to throw `EAGAIN`.
    ///
    /// The result is non-optional because UDP allows us to send and receive
    /// zero length datagrams.

    func receiveFrom(maxCount: Int = 65536, flags: CInt = 0, retryOnInterrupt: Bool = true) throws -> (data: Data, from: (address: String, port: UInt16)) {
        var result = Data(count: maxCount)
        let (bytesRead, address, port) = try result.withUnsafeMutableBytes { buf in
            try QSockAddr.fromSockAddr { sa, saLen in
                try errnoQ(retryOnInterrupt: retryOnInterrupt) {
                    recvfrom(self.rawValue, buf.baseAddress, buf.count, flags, sa, &saLen)
                }
            }
        }
        result = result.prefix(bytesRead)
        return (result, (address, port))
    }
}

/// Indicates that a type can be used as a socket option.
///
/// This has one true constraint, namely that the type has a default value.
/// There are, however, two implicit constraints:
///
/// * The type must be just data. If, for example, the type contains an object
///   reference, bad things would happen.
///
/// * The type’s size is compatible with `socklen_t`.
///
/// We specifically conform various types, like `CInt` and `timeval`, to this
/// protocol but you can add to that list if necessary.

public protocol QSocketOptionConvertible {
    init()
}

extension UInt8: QSocketOptionConvertible { }
extension CInt: QSocketOptionConvertible { }
extension CUnsignedInt: QSocketOptionConvertible { }
extension timeval: QSocketOptionConvertible { }
extension in_addr: QSocketOptionConvertible { }
