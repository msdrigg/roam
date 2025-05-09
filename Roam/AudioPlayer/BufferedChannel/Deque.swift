import Foundation

/// A double-ended queue implementation with O(1) operations at both ends
public struct Deque<Element> {
    // MARK: - Private Storage

    // Using a ring buffer implementation for optimal performance
    private var buffer: ContiguousArray<Element?>
    private var head: Int = 0
    public var count: Int = 0

    // Capacity management constants
    private let initialCapacity = 8
    private let growthFactor = 2
    private let shrinkFactor = 4

    // MARK: - Initialization

    public init() {
        buffer = ContiguousArray<Element?>(repeating: nil, count: initialCapacity)
    }

    public init<S: Sequence>(_ elements: S) where S.Element == Element {
        self.init()
        elements.forEach { append($0) }
    }

    // MARK: - Private Helpers

    @inline(__always)
    private var capacity: Int {
        return buffer.count
    }

    @inline(__always)
    public var isEmpty: Bool {
        return count == 0
    }

    @inline(__always)
    private func normalizeIndex(_ index: Int) -> Int {
        return (head + index) % capacity
    }

    private mutating func growIfNeeded() {
        if count == capacity {
            resize(capacity * growthFactor)
        }
    }

    private mutating func shrinkIfNeeded() {
        if count <= capacity / shrinkFactor && capacity > initialCapacity {
            resize(Swift.max(capacity / shrinkFactor, initialCapacity))
        }
    }

    private mutating func resize(_ newCapacity: Int) {
        var newBuffer = ContiguousArray<Element?>(repeating: nil, count: newCapacity)

        // Copy elements to the new buffer
        for i in 0..<count {
            newBuffer[i] = self[i]
        }

        // Update state
        buffer = newBuffer
        head = 0
    }

    // MARK: - Core Operations

    /// Add an element to the front of the deque
    public mutating func prepend(_ element: Element) {
        growIfNeeded()

        // Move head back by one (with wraparound)
        head = (head - 1 + capacity) % capacity
        buffer[head] = element
        count += 1
    }

    /// Add an element to the back of the deque
    public mutating func append(_ element: Element) {
        growIfNeeded()

        let index = normalizeIndex(count)
        buffer[index] = element
        count += 1
    }

    /// Remove and return the first element if available, or nil if deque is empty
    @discardableResult
    public mutating func popFirst() -> Element? {
        guard !isEmpty else { return nil }

        let element = buffer[head]!
        buffer[head] = nil
        head = (head + 1) % capacity
        count -= 1

        shrinkIfNeeded()
        return element
    }

    /// Access element at specified position
    public subscript(index: Int) -> Element {
        precondition(index >= 0 && index < count, "Index out of bounds")
        let bufferIndex = normalizeIndex(index)
        return buffer[bufferIndex]!
    }

    // MARK: - Additional Helper Methods

    /// Returns the first element without removing it
    public var first: Element? {
        guard !isEmpty else { return nil }
        return buffer[head]
    }

    /// Returns the last element without removing it
    public var last: Element? {
        guard !isEmpty else { return nil }
        let index = normalizeIndex(count - 1)
        return buffer[index]
    }

    /// Number of elements in the deque
    public var size: Int {
        return count
    }

    /// Remove all elements
    public mutating func removeAll() {
        buffer = ContiguousArray<Element?>(repeating: nil, count: initialCapacity)
        head = 0
        count = 0
    }
}

// MARK: - Collection Conformance

extension Deque: Collection {
    public typealias Index = Int

    public var startIndex: Int { return 0 }
    public var endIndex: Int { return count }

    public func index(after i: Int) -> Int {
        return i + 1
    }

    public func makeIterator() -> DequeIterator<Element> {
        return DequeIterator(self)
    }
}

// MARK: - Iterator Implementation

public struct DequeIterator<Element>: IteratorProtocol {
    private let deque: Deque<Element>
    private var currentIndex = 0

    init(_ deque: Deque<Element>) {
        self.deque = deque
    }

    public mutating func next() -> Element? {
        guard currentIndex < deque.size else { return nil }
        let element = deque[currentIndex]
        currentIndex += 1
        return element
    }
}

// MARK: - CustomStringConvertible Conformance

extension Deque: CustomStringConvertible {
    public var description: String {
        guard !isEmpty else { return "[]" }

        var result = "["
        for i in 0..<count {
            result += "\(self[i])"
            if i < count - 1 {
                result += ", "
            }
        }
        result += "]"
        return result
    }
}

// MARK: - ExpressibleByArrayLiteral Conformance

extension Deque: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }
}
