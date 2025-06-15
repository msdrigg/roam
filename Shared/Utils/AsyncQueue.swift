actor AsyncQueue {
    public typealias WorkItem = @Sendable () async -> Void

    private let _streamContinuation: AsyncStream<WorkItem>.Continuation

    public init(_ bufferingPolicy: AsyncStream<WorkItem>.Continuation.BufferingPolicy = .unbounded) {
        let stream: AsyncStream<WorkItem>
        (stream, _streamContinuation) = AsyncStream.makeStream()

        Task {
            for await workItem in stream {
                await workItem()
            }
        }
    }

    deinit {
        _streamContinuation.finish()
    }

    public nonisolated func async(_ workItem: @escaping WorkItem) {
        _streamContinuation.yield(workItem)
    }
}
