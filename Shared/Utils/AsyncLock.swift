import Foundation

private struct Waiter: Identifiable, Hashable {
    let id: UUID
    let continuation: CheckedContinuation<Void, Error>?

    func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

public actor AsyncLock {
    private actor Inner {
        var isLocked = false
        var waiters: OrderedSet<Waiter> = OrderedSet()

        func cancelWaiter(_ cancellableId: UUID) {
            let waiter = waiters.remove(Waiter(id: cancellableId, continuation: nil))
            waiter?.continuation?.resume(throwing: CancellationError())
        }

        func lock() async throws {
            try Task.checkCancellation()
            if !isLocked {
                isLocked = true
                return
            }
            let cancellableId = UUID()
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    waiters.append(Waiter(id: cancellableId, continuation: continuation))
                }
            }, onCancel: {
                Task {
                    await self.cancelWaiter(cancellableId)
                }
            })
        }

        func unlock() {
            if let next = waiters.popFirst() {
                next.continuation?.resume()
            } else {
                isLocked = false
            }
        }
    }

    private let inner = Inner()

    public init() {}

    public nonisolated func lock() async throws {
        try Task.checkCancellation()
        try await inner.lock()
    }

    public nonisolated func unlock() {
        Task { await inner.unlock() }
    }

    public nonisolated func withLock<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        try await inner.lock()
        defer { Task { await inner.unlock() } }
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
