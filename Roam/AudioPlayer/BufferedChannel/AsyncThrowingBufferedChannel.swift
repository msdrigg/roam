//
//  AsyncThrowingBufferedChannel.swift
//
//
//  Created by Thibault Wittemberg on 07/01/2022.
//
// Please see the source at https://github.com/apple/swift-async-algorithms

/// A channel for sending elements from one task to another.
///
/// The `AsyncThrowingBufferedChannel` class is intended to be used as a communication type between tasks,
/// particularly when one task produces values and another task consumes those values. The values are
/// buffered awaiting a consumer to consume them from iteration.
/// `finish()` and `fail()` induce a terminal state and no further elements can be sent.
public final class AsyncThrowingBufferedChannel<Element, Failure: Error>: AsyncSequence,
    Sendable where Element: Sendable
{
    public typealias Element = Element
    public typealias AsyncIterator = Iterator

    enum Termination: Sendable {
        case finished
        case failure(Failure)
    }

    struct Awaiting: Hashable {
        let id: Int
        let continuation: UnsafeContinuation<Element?, any Error>?

        static func placeHolder(id: Int) -> Awaiting {
            Awaiting(id: id, continuation: nil)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: Awaiting, rhs: Awaiting) -> Bool {
            lhs.id == rhs.id
        }
    }

    enum SendDecision {
        case resume(Awaiting, Element)
        case finish([Awaiting])
        case fail([Awaiting], any Error)
        case nothing
    }

    enum AwaitingDecision {
        case resume(Element?)
        case fail(any Error)
        case suspend
    }

    enum Value {
        case element(Element)
        case termination(Termination)
    }

    enum State: @unchecked Sendable {
        case idle
        case queued(Deque<Value>)
        case awaiting(OrderedSet<Awaiting>)
        case terminated(Termination)

        static var initial: State {
            .idle
        }
    }

    let ids: ManagedCriticalState<Int>
    let state: ManagedCriticalState<State>

    public init() {
        ids = ManagedCriticalState(0)
        state = ManagedCriticalState(.initial)
    }

    func generateId() -> Int {
        ids.withCriticalRegion { ids in
            ids += 1
            return ids
        }
    }

    var hasBufferedElements: Bool {
        state.withCriticalRegion { state in
            switch state {
            case .idle:
                false
            case let .queued(values) where !values.isEmpty:
                true
            case .awaiting, .queued:
                false
            case .terminated:
                true
            }
        }
    }

    func send(_ value: Value) {
        let decision = state.withCriticalRegion { state -> SendDecision in
            switch (state, value) {
            case (.idle, .element):
                state = .queued([value])
                return .nothing
            case let (.idle, .termination(termination)):
                state = .terminated(termination)
                return .nothing
            case var (.queued(values), _):
                values.append(value)
                state = .queued(values)
                return .nothing
            case (.awaiting(var awaitings), let .element(element)):
                let awaiting = awaitings.popFirst()!
                if awaitings.isEmpty {
                    state = .idle
                } else {
                    state = .awaiting(awaitings)
                }
                return .resume(awaiting, element)
            case let (.awaiting(awaitings), .termination(.failure(error))):
                state = .terminated(.failure(error))
                return .fail(Array(awaitings), error)
            case let (.awaiting(awaitings), .termination(.finished)):
                state = .terminated(.finished)
                return .finish(Array(awaitings))
            case (.terminated, _):
                return .nothing
            }
        }

        switch decision {
        case .nothing:
            break
        case let .finish(awaitings):
            awaitings.forEach { $0.continuation?.resume(returning: nil) }
        case let .fail(awaitings, error):
            awaitings.forEach { $0.continuation?.resume(throwing: error) }
        case let .resume(awaiting, element):
            awaiting.continuation?.resume(returning: element)
        }
    }

    public func send(_ element: Element) {
        send(.element(element))
    }

    public func fail(_ error: Failure) where Failure == any Error {
        send(.termination(.failure(error)))
    }

    public func finish() {
        send(.termination(.finished))
    }

    func next(onSuspend: (() -> Void)? = nil) async throws -> Element? {
        let awaitingId = generateId()
        let cancellation = ManagedCriticalState<Bool>(false)

        return try await withTaskCancellationHandler { [state] in
            try await withUnsafeThrowingContinuation { [state] (continuation: UnsafeContinuation<Element?, Error>) in
                let decision = state.withCriticalRegion { state -> AwaitingDecision in
                    let isCancelled = cancellation.withCriticalRegion { $0 }
                    guard !isCancelled else { return .resume(nil) }

                    switch state {
                    case .idle:
                        state = .awaiting([Awaiting(id: awaitingId, continuation: continuation)])
                        return .suspend
                    case var .queued(values):
                        let value = values.popFirst()
                        switch value {
                        case .termination(.finished):
                            state = .terminated(.finished)
                            return .resume(nil)
                        case let .termination(.failure(error)):
                            state = .terminated(.failure(error))
                            return .fail(error)
                        case let .element(element) where !values.isEmpty:
                            state = .queued(values)
                            return .resume(element)
                        case let .element(element):
                            state = .idle
                            return .resume(element)
                        default:
                            state = .idle
                            return .suspend
                        }
                    case var .awaiting(awaitings):
                        awaitings.updateOrAppend(Awaiting(id: awaitingId, continuation: continuation))
                        state = .awaiting(awaitings)
                        return .suspend
                    case .terminated(.finished):
                        return .resume(nil)
                    case let .terminated(.failure(error)):
                        return .fail(error)
                    }
                }

                switch decision {
                case let .resume(element): continuation.resume(returning: element)
                case let .fail(error): continuation.resume(throwing: error)
                case .suspend:
                    onSuspend?()
                }
            }
        } onCancel: {
            let awaiting = state.withCriticalRegion { state -> Awaiting? in
                cancellation.withCriticalRegion { cancellation in
                    cancellation = true
                }
                switch state {
                case var .awaiting(awaitings):
                    let awaiting = awaitings.remove(.placeHolder(id: awaitingId))
                    if awaitings.isEmpty {
                        state = .idle
                    } else {
                        state = .awaiting(awaitings)
                    }
                    return awaiting
                default:
                    return nil
                }
            }

            awaiting?.continuation?.resume(returning: nil)
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(
            channel: self
        )
    }

    public struct Iterator: AsyncIteratorProtocol, Sendable {
        let channel: AsyncThrowingBufferedChannel<Element, Failure>

        var hasBufferedElements: Bool {
            channel.hasBufferedElements
        }

        public func next() async throws -> Element? {
            try await channel.next()
        }
    }
}
