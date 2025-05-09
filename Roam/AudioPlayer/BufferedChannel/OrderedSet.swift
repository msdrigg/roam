import Foundation

/// An ordered set implementation that maintains insertion order while ensuring uniqueness of elements
public struct OrderedSet<Element: Hashable> {
    // MARK: - Private Storage

    // Using two storage components for optimal performance
    private var orderedElements: [Element]
    private var uniqueElements: Set<Element>

    // MARK: - Initialization

    public init() {
        orderedElements = []
        uniqueElements = Set<Element>()
    }

    public init<S: Sequence>(_ sequence: S) where S.Element == Element {
        self.init()
        sequence.forEach { append($0) }
    }

    // MARK: - Core Operations

    /// Add an element to the end if it's not already in the set
    @discardableResult
    public mutating func append(_ element: Element) -> Bool {
        if uniqueElements.contains(element) {
            return false
        }

        uniqueElements.insert(element)
        orderedElements.append(element)
        return true
    }

    /// Remove and return the first element if available, or nil if set is empty
    @discardableResult
    public mutating func popFirst() -> Element? {
        guard !orderedElements.isEmpty else { return nil }

        let element = orderedElements.first!
        uniqueElements.remove(element)
        return orderedElements.removeFirst()
    }

    /// Remove an element if it exists
    @discardableResult
    public mutating func remove(_ element: Element) -> Element? {
        guard let index = firstIndex(of: element) else {
            return nil
        }

        uniqueElements.remove(element)
        return orderedElements.remove(at: index)
    }

    /// Check if the set contains an element
    public func contains(_ element: Element) -> Bool {
        return uniqueElements.contains(element)
    }

    /// Find the first index of an element
    public func firstIndex(of element: Element) -> Int? {
        guard uniqueElements.contains(element) else {
            return nil
        }
        return orderedElements.firstIndex(of: element)
    }

    // MARK: - Subscript Access

    public subscript(index: Int) -> Element {
        precondition(index >= 0 && index < orderedElements.count, "Index out of bounds")
        return orderedElements[index]
    }

    // MARK: - Additional Helper Methods

    /// Number of elements in the ordered set
    public var count: Int {
        return orderedElements.count
    }

    /// Check if the ordered set is empty
    public var isEmpty: Bool {
        return orderedElements.isEmpty
    }

    /// Return the first element
    public var first: Element? {
        return orderedElements.first
    }

    /// Return the last element
    public var last: Element? {
        return orderedElements.last
    }

    /// Remove all elements
    public mutating func removeAll() {
        orderedElements.removeAll()
        uniqueElements.removeAll()
    }

    // MARK: - Set Operations

    /// Create a new set with elements from both this set and another
    public func union(_ other: OrderedSet<Element>) -> OrderedSet<Element> {
        var result = self
        other.forEach { result.append($0) }
        return result
    }

    /// Create a new set with elements common to both this set and another
    public func intersection(_ other: OrderedSet<Element>) -> OrderedSet<Element> {
        var result = OrderedSet<Element>()
        forEach { element in
            if other.contains(element) {
                result.append(element)
            }
        }
        return result
    }

    /// Create a new set with elements in this set that aren't in another
    public func subtracting(_ other: OrderedSet<Element>) -> OrderedSet<Element> {
        var result = OrderedSet<Element>()
        forEach { element in
            if !other.contains(element) {
                result.append(element)
            }
        }
        return result
    }

    /// Create a new set with elements that are in exactly one of the sets
    public func symmetricDifference(_ other: OrderedSet<Element>) -> OrderedSet<Element> {
        var result = OrderedSet<Element>()

        forEach { element in
            if !other.contains(element) {
                result.append(element)
            }
        }

        other.forEach { element in
            if !self.contains(element) {
                result.append(element)
            }
        }

        return result
    }
}

// MARK: - Collection Conformance

extension OrderedSet: Collection {
    public typealias Index = Int

    public var startIndex: Int { return orderedElements.startIndex }
    public var endIndex: Int { return orderedElements.endIndex }

    public func index(after i: Int) -> Int {
        return orderedElements.index(after: i)
    }
}

// MARK: - Sequence Conformance

extension OrderedSet: Sequence {
    public func makeIterator() -> IndexingIterator<[Element]> {
        return orderedElements.makeIterator()
    }
}

// MARK: - CustomStringConvertible Conformance

extension OrderedSet: CustomStringConvertible {
    public var description: String {
        return orderedElements.description
    }
}

// MARK: - ExpressibleByArrayLiteral Conformance

extension OrderedSet: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }
}

extension OrderedSet {
    /// Updates an existing Awaiting object with matching id, or appends a new one if not found
    public mutating func updateOrAppend(_ element: Element) {
        if !self.contains(element) {
            append(element)
        } else {
            uniqueElements.remove(element)
            uniqueElements.insert(element)
            if let idx = firstIndex(of: element) {
                orderedElements[idx] = element
            }
        }
    }
}
