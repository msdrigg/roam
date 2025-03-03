import Foundation

public extension Task where Success == Never, Failure == Never {
    /// Blueprint for a task that should be run, but not yet.
    struct Blueprint<Output: Sendable>: Sendable {
        public var priority: TaskPriority
        public var operation: @Sendable () async throws -> Output

        public init(
            priority: TaskPriority = .medium,
            operation: @escaping @Sendable () async throws -> Output
        ) {
            self.priority = priority
            self.operation = operation
        }
    }
}

public extension Task where Success == Never, Failure == Never {
    /// Race for the first result by any of the provided tasks.
    ///
    /// This will return the first valid result or throw the first thrown error by any task.
    static func race<Output: Sendable>(firstResolved tasks: [Blueprint<Output>]) async throws -> Output {
        assert(!tasks.isEmpty, "You must race at least 1 task.")
        return try await withThrowingTaskGroup(of: Output.self) { group -> Output in
            for task in tasks {
                group.addTask(priority: task.priority) {
                    try await task.operation()
                }
            }

            defer { group.cancelAll() }
            if let firstToResolve = try await group.next() {
                return firstToResolve
            } else {
                // There will be at least 1 task.
                fatalError("At least 1 task should be scheduled.")
            }
        }
    }

    /// Race for the first valid value.
    ///
    /// Ignores errors that may be thrown and waits for the first result.
    /// If all tasks fail, returns `nil`.
    static func race<Output: Sendable>(firstValue tasks: [Blueprint<Output>]) async -> Output? {
        await withThrowingTaskGroup(of: Output.self) { group -> Output? in
            for task in tasks {
                group.addTask(priority: task.priority) {
                    try await task.operation()
                }
            }

            defer { group.cancelAll() }
            while let nextResult = await group.nextResult() {
                switch nextResult {
                case .failure:
                    continue
                case let .success(result):
                    return result
                }
            }

            // If all the racing tasks error, we will reach this point.
            return nil
        }
    }
}

public extension Task where Success == Never, Failure == Never {
    /// Sleep for the specified `TimeInterval`.
    @inlinable static func sleep(duration: TimeInterval) async throws {
        try await sleep(nanoseconds: UInt64(duration * 1e9))
    }

    /// Sleep until cancelled
    @inlinable static func sleepUntilCancelled() async {
        try? await sleep(nanoseconds: UInt64.max / 2)
    }
}

public struct TimeoutError: Swift.Error, LocalizedError {
    /// When the timeout occurred.
    public let occurred: Date = .init()
    public var errorDescription: String? {
        "The operation timed out."
    }
}

/// Run a new task that will fail after `delay`.
/// You should ensure that the task run here responds to a cancellation event as soon as possible.
/// - returns: The value if the operation did not timeout.
/// - throws: `TimeoutError` if the operation timed out.
public func withTimeout<T: Sendable>(
    delay: TimeInterval,
    priority: TaskPriority = .medium,
    run task: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await Task.race(firstResolved: [
        .init {
            try await Task.sleep(duration: delay)
            throw TimeoutError()
        },
        .init(priority: priority) {
            try await task()
        },
    ])
}

public func exponentialBackoff(
    min minTime: TimeInterval,
    max maxTime: TimeInterval,
    multiplier: Double = 2
) -> AsyncStream<Date> {
    return AsyncStream<Date>.init(Date.self, bufferingPolicy: .bufferingOldest(1), { (continuation: AsyncStream<Date>.Continuation) in
        let task = Task {
            var currentTimeout: TimeInterval?
            while !Task.isCancelled {
                if let timeout = currentTimeout {
                    // Jitter for 1% of timeout
                    let jitter = Double.random(in: 0 ..< timeout * 0.01)
                    try? await Task.sleep(duration: timeout + jitter)
                    currentTimeout = min(timeout * multiplier, maxTime)
                } else {
                    currentTimeout = minTime
                }
                if Task.isCancelled {
                    continuation.finish()
                } else {
                    continuation.yield(Date.now)
                }
            }
        }
        continuation.onTermination =  { @Sendable _ in
            task.cancel()
        }
    })
}

public func interval(
    time: TimeInterval
) -> AsyncStream<Date> {
    AsyncStream {
        // Jitter for 1% of timeout
        let jitter = Double.random(in: 0 ..< time * 0.01)
        try? await Task.sleep(duration: time + jitter)
        if Task.isCancelled {
            return nil
        }

        return Date.now
    }
}

public func nanoseconds(_ timeInterval: TimeInterval) -> UInt64 {
    UInt64(timeInterval) * 1_000_000_000
}

final class Signaler {
    private var hasFiredFlag: Bool = false
    private let flagQueue = DispatchQueue(label: "Signaler.FlagQueue")

    func fire() {
        flagQueue.sync {
            hasFiredFlag = true
        }
    }

    func hasFired() -> Bool {
        flagQueue.sync {
            hasFiredFlag
        }
    }
}
