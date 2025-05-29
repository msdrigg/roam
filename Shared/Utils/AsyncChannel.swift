import os

/// See https://github.com/gh123man/Async-Channels for initial source
public final class Channel<T: Sendable>: @unchecked Sendable {
    @usableFromInline
    let channelInternal: ChannelInternal

    public init(capacity: Int = 0) {
        self.channelInternal = ChannelInternal(capacity: capacity)
    }

    public var isClosed: Bool {
        channelInternal.isClosed
    }

    /// Receive data from the channel. This function will suspend until a sender is ready or there is data in the buffer.
    /// This functionw will return `nil` when the channel is closed after all buffered data is read.
    /// - Returns: data or nil.
    @inline(__always)
    @inlinable
    public func receive() async -> T? {
        return toValue(await channelInternal.receive())
    }

    /// Sends data synchonosly. Returns true if the data was sent.
    /// A fatal error will be triggered if you attpend to send on a closed channel.
    /// - Parameter value: The input data.
    @inline(__always)
    @inlinable
    public func send(_ value: T) -> Bool {
        do {
            return try channelInternal.syncSend(toPointer(value))
        } catch {
            Log.data.error("Error sending data on a closed channel")
            return false
        }
    }

    /// Closes the channel. A channel cannot be reopened.
    /// Once a channel is closed, no more data can be writeen. The remaining data can be read until the buffer is empty.
    @inline(__always)
    public func close() {
        channelInternal.close()
    }
}

extension Channel: AsyncSequence, AsyncIteratorProtocol {
    public typealias Element = T
    
    public func makeAsyncIterator() -> Channel {
        return self
    }
    
    public func next() async -> T? {
        return await self.receive()
    }
}

extension UnsafeRawPointer: @unchecked @retroactive Sendable {}

public enum ChannelError: Error {
    case closed
}

@inline(__always)
@inlinable
func toPointer<T: Sendable>(_ value: T) -> UnsafeRawPointer {
    // Handle arc managed pointer types
    if T.self is AnyObject.Type {
        return UnsafeRawPointer(Unmanaged.passRetained(value as AnyObject).toOpaque())
    }
    // Handle struct/value types
    let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
    ptr.initialize(to: value)
    return UnsafeRawPointer(ptr)
}

@inline(__always)
@inlinable
func toValue<T: Sendable>(_ ptr: UnsafeRawPointer?) -> T? {
    guard let ptr = ptr else {
        return nil
    }
    
    // Handle arc managed pointer types
    if T.self is AnyObject.Type {
        return Unmanaged<AnyObject>.fromOpaque(ptr).takeRetainedValue() as? T
    }
    
    // Handle struct/value types
    let pt = UnsafeMutablePointer<T>(mutating: ptr.assumingMemoryBound(to: T.self))
    defer {
        pt.deinitialize(count: 1)
        pt.deallocate()
    }
    return pt.pointee
}

@usableFromInline
final class ChannelInternal: @unchecked Sendable {
    private var mutex = FastLock()
    private let capacity: Int
    private var bufferCount: Int = 0
    private var closed = false
    private var buffer: LinkedList<UnsafeRawPointer>
    private var sendQueue = LinkedList<(UnsafeRawPointer, UnsafeContinuation<Void, Never>)>()
    private var recvQueue = LinkedList<UnsafeContinuation<UnsafeRawPointer?, Never>>()

    init(capacity: Int = 0) {
        self.capacity = capacity
        self.buffer = LinkedList()
    }
    
    var isClosed: Bool {
        mutex.lock()
        defer { mutex.unlock() }
        return closed
    }

    @inline(__always)
    private func nonBlockingSend(_ p: UnsafeRawPointer) throws -> Bool {
        if closed {
            mutex.unlock()
            throw ChannelError.closed
        }
        
        if !recvQueue.isEmpty {
            let r = recvQueue.removeFirst()!
            mutex.unlock()
            r.resume(returning: p)
            return true
        }

        if bufferCount < capacity {
            buffer.append(p)
            bufferCount += 1
            mutex.unlock()
            return true
        }
        
        return false
    }
    
    @inline(__always)
    @usableFromInline
    func send(_ p: UnsafeRawPointer) async throws {
        mutex.lock()
        
        if try nonBlockingSend(p) {
            return
        }
        
        await withUnsafeContinuation { continuation in
            sendQueue.append((p, continuation))
            mutex.unlock()
        }
    }
    
    @inline(__always)
    @usableFromInline
    func syncSend(_ p: UnsafeRawPointer) throws -> Bool {
        mutex.lock()
        if try nonBlockingSend(p) {
            return true
        }
        mutex.unlock()
        return false
    }
    
    @inline(__always)
    @usableFromInline
    func nonBlockingReceive() -> UnsafeRawPointer? {
        if buffer.isEmpty {
            if !sendQueue.isEmpty {
                let (p, continuation) = sendQueue.removeFirst()!
                mutex.unlock()
                continuation.resume()
                return p
            } else {
                return nil
            }
        }
        
        let p = buffer.removeFirst()
        bufferCount -= 1
        
        if !sendQueue.isEmpty {
            let (value, continuation) = sendQueue.removeFirst()!
            buffer.append(value)
            bufferCount += 1
            mutex.unlock()
            continuation.resume()
        } else {
            mutex.unlock()
        }
        return p
    }

    @inline(__always)
    @usableFromInline
    func receive() async -> UnsafeRawPointer? {
        mutex.lock()

        if let p = nonBlockingReceive() {
            return p
        }
        
        if closed {
            mutex.unlock()
            return nil
        }
        
        let p = await withUnsafeContinuation { continuation in
            recvQueue.append(continuation)
            mutex.unlock()
        }
        return p
    }
    
    @inline(__always)
    @usableFromInline
    func syncReceive() -> UnsafeRawPointer? {
        mutex.lock()
        if let p = nonBlockingReceive() {
            return p
        }
        mutex.unlock()
        return nil
    }
    
    @inline(__always)
    func close() {
        mutex.lock()
        defer { mutex.unlock() }
        closed = true
        
        while let recvW = recvQueue.removeFirst() {
            recvW.resume(returning: nil)
        }
    }
}
