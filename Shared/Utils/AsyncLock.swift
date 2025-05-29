import Foundation
import os

public struct AsyncLock: Sendable {
    private class Inner: @unchecked Sendable {
        private var isLocked = false
        private let lock = FastLock()
        private let waiters: LinkedList<Waiter>

        init(isLocked: Bool = false) {
            self.isLocked = isLocked
            self.waiters = LinkedList<Waiter>()
        }

        private func cancelWaiter(_ waiterNode: Node<Waiter>) {
            lock.lock()
            let waiter = waiters.remove(node: waiterNode)
            lock.unlock()
            waiter.resume(throwing: CancellationError())
        }

        func lock() async throws {
            try Task.checkCancellation()
            
            lock.lock()
            if !isLocked {
                isLocked = true
                lock.unlock()
                return
            }
            lock.unlock()
            let node: OSAllocatedUnfairLock<Node<Waiter>?> = OSAllocatedUnfairLock(initialState: nil)
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    lock.lock()
                    let waitedNode = waiters.append(continuation)
                    lock.unlock()
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
            lock.lock()
            guard let next = waiters.removeFirst() else {
                isLocked = false
                lock.unlock()
                return
            }
            lock.unlock()
            next.resume()
        }
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

    public func remove(node: Node<T>) -> T {
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

/// MARK: FastLock
/// See https://github.com/gh123man/Async-Channels for source
#if canImport(Darwin)
class FastLock {
    let unfairLock = {
        let l = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        l.initialize(to: os_unfair_lock())
        return l
    }()
    
    deinit {
        unfairLock.deinitialize(count: 1)
        unfairLock.deallocate()
    }

    @inlinable
    @inline(__always)
    func lock() {
        os_unfair_lock_lock(unfairLock)
    }
   
    @inlinable
    @inline(__always)
    func unlock() {
        os_unfair_lock_unlock(unfairLock)
    }
}

#else

class FastLock {
    var m: pthread_mutex_t = {
      var m = pthread_mutex_t()
      var attr = pthread_mutexattr_t()
      pthread_mutexattr_init(&attr)
      pthread_mutexattr_settype(&attr, 3) // Faster under contention
      precondition(pthread_mutex_init(&m, &attr) == 0, "pthread_mutex_init failed")
      pthread_mutexattr_destroy(&attr)
      return m
  }()

  deinit {
      pthread_mutex_destroy(&m)
  }

  @inline(__always)
  func lock() {
      pthread_mutex_lock(&m)
  }

  @inline(__always)
  func unlock() {
      pthread_mutex_unlock(&m)
  }
}

#endif
