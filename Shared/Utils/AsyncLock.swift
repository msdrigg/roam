import Foundation
import os

public struct AsyncLock: Sendable {
    private final class Inner: Sendable {
        private let lock: OSAllocatedUnfairLock<LockState>

        init(isLocked: Bool = false) {
            self.lock = OSAllocatedUnfairLock(uncheckedState: LockState())
        }

        private func cancelWaiter(_ waiterNode: sending Node<Waiter>) {
            let waiter = lock.withLock { [waiterNode] ls in
                return ls.waiters.remove(node: waiterNode)
            }
            waiter.resume(throwing: CancellationError())
        }

        func lock() async throws {
            try Task.checkCancellation()

            let fastLocked = lock.withLock { ls in
                if !ls.isLocked {
                    ls.isLocked = true
                    return true
                } else {
                    return false
                }
            }
            if fastLocked {
                return
            }
            let node: OSAllocatedUnfairLock<Node<Waiter>?> = OSAllocatedUnfairLock(initialState: nil)
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    let waitedNode = lock.withLock { ls in
                        return ls.waiters.append(continuation)
                    }
                    node.withLock { node in
                        node = waitedNode
                    }
                }
            }, onCancel: {
                let cancelling = node.withLock { receivedNode in
                    return receivedNode.take()
                }

                if let cancelling {
                    self.cancelWaiter(cancelling)
                }
            })
        }

        func unlock() {
            let resumingNext = lock.withLock { ls in
                if let next = ls.waiters.removeFirst() {
                    return Optional.some(next)
                } else {
                    ls.isLocked = false
                    return nil
                }
            }
            resumingNext?.resume()
        }
    }

    struct LockState {
        var isLocked: Bool = false
        var waiters: LinkedList<Waiter> = LinkedList()
    }

    private let inner = Inner()

    public init() {}

    public func lock() async throws {
        try Task.checkCancellation()
        try await inner.lock()
    }

    public func unlock() {
        inner.unlock()
    }

    public func withLock<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        try await inner.lock()
        defer { inner.unlock() }
        return try await operation()
    }
}

func processConcurrently<T: Sendable, U: Sendable>(
    items: [T],
    maxConcurrent: Int,
    operation: @Sendable @escaping (T) async -> U
) -> AsyncStream<U> {
    AsyncStream(bufferingPolicy: .unbounded) { continuation in
        Task {
            await withTaskGroup(of: U.self) { group in
                var nextIndex = 0
                let initial = min(maxConcurrent, items.count)
                for _ in 0..<initial {
                    let idx = nextIndex
                    group.addTask {
                        await operation(items[idx])
                    }
                    nextIndex += 1
                }
                while let result = await group.next() {
                    continuation.yield(result)
                    if nextIndex < items.count {
                        let idx = nextIndex
                        group.addTask {
                            await operation(items[idx])
                        }
                        nextIndex += 1
                    }
                }
            }
            continuation.finish()
        }
    }
}

typealias Waiter = CheckedContinuation<Void, Error>

final class Node<T: Sendable>: @unchecked Sendable {
    fileprivate let value: T
    fileprivate var next: Node?
    fileprivate weak var previous: Node?

    fileprivate init(value: T, next: Node? = nil, previous: Node? = nil) {
        self.value = value
        self.next = next
        self.previous = previous
    }
}

final class LinkedList<T: Sendable> {
    var head: Node<T>?
    var tail: Node<T>?

    @discardableResult
    func append(_ value: T) -> Node<T> {
        let newNode = Node(value: value)
        if let tailNode = tail {
            newNode.previous = tailNode
            tailNode.next = newNode
        } else {
            head = newNode
        }
        tail = newNode
        return newNode
    }

    func removeFirst() -> T? {
        if let head {
            return self.remove(node: head)
        } else {
            return nil
        }
    }

    public func remove(node: sending Node<T>) -> T {
        let prev = node.previous
        let next = node.next

        if let prev = prev {
            prev.next = next
        } else {
            head = next
        }
        next?.previous = prev

        if next == nil {
            tail = prev
        }

        node.previous = nil
        node.next = nil

        return node.value
    }

    var isEmpty: Bool {
        return head == nil
    }

    private func lastNode() -> Node<T>? {
        return tail
    }
}
