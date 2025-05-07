#if canImport(UIKit) && !os(watchOS) && !WIDGET
import UIKit

/// Prevents the process from suspending by holding a `UIApplication` background
/// task assertion.
///
/// The assertion is released if:
///
/// * You explicitly release the assertion by calling ``release()``.
/// * There are no more strong references to the object and so it gets deinitialised.
/// * The system ‘calls in’ the assertion, in which case it calls the
///   ``systemDidReleaseAssertion`` closure, if set.
///
/// You should aim to explicitly release the assertion yourself, as soon as
/// you’ve completed the work that the assertion covers.
@MainActor final class QRunInBackgroundAssertion {

    /// The name used when creating the assertion.
    let name: String

    /// Called when the system releases the assertion itself.
    ///
    /// This is called on the main thread.
    ///
    /// To help avoid retain cycles, the object sets this to `nil` whenever the
    /// assertion is released.
    var systemDidReleaseAssertion: (() -> Void)? {
        willSet { dispatchPrecondition(condition: .onQueue(.main)) }
    }

    private var taskID: UIBackgroundTaskIdentifier

    /// Creates an assertion with the given name.
    ///
    /// The name isn’t used by the system but it does show up in various logs so
    /// it’s important to choose one that’s meaningful to you.
    ///
    /// Must be called on the main thread.
    @MainActor
    init(name: String) {
        self.name = name
        self.systemDidReleaseAssertion = nil
        // Have to initialise `taskID` first so that I can capture a fully
        // initialised `self` in the expiration handler.  If the expiration
        // handler ran /before/ I got a chance to set `self.taskID` to `t`,
        // things would end badly.  However, that can’t happen because I’m
        // running on the main thread — courtesy of the Dispatch precondition
        // above — and the expiration handler also runs on the main thread.
        self.taskID = .invalid
        let t = UIApplication.shared.beginBackgroundTask(withName: name) {
            self.taskDidExpire()
        }
        self.taskID = t
    }

    /// Release the assertion.
    ///
    /// It’s safe to call this redundantly, that is, call it twice in a row or
    /// call it on an assertion that’s expired.
    ///
    /// Must be called on the main thread.
    func release() {
        self.consumeValidTaskID { }
    }

    func isReleased() -> Bool {
        return self.taskID == .invalid
    }

    deinit {
        guard self.taskID != .invalid else { return }
        let task = self.taskID
        self.taskID = .invalid
        self.systemDidReleaseAssertion = nil
        DispatchQueue.main.async {
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    private func consumeValidTaskID(_ body: () -> Void) {
        // dispatchPrecondition(condition: .onQueue(.main))
        guard self.taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(self.taskID)
        self.taskID = .invalid
        body()
        self.systemDidReleaseAssertion = nil
    }

    private func taskDidExpire() {
        self.consumeValidTaskID {
            self.systemDidReleaseAssertion?()
        }
    }
}
#elseif !os(macOS)
import Foundation
import os

/// Prevents the process from suspending by holding a `ProcessInfo` expiry
/// activity assertion.
///
/// The assertion is released if:
///
/// * You explicitly release the assertion by calling ``release()``.
/// * There are no more strong references to the object and so it gets
///   deinitialised.
/// * The system ‘calls in’ the assertion, in which case it calls the
///   ``systemDidReleaseAssertion`` closure, if set.
///
/// You should aim to explicitly release the assertion yourself, as soon as
/// you’ve completed the work that the assertion covers.
///
/// This uses `performExpiringActivity(withReason:using:)`, which… well… how to
/// say this kindly… has some very odd design characteristics.  The API kinda
/// makes sense if you’re doing CPU bound work but its design does not work well
/// if you’re doing something I/O bound, like networking (r. 109839489). And
/// that’s the primary use case for this class.  The end result is that you have
/// to waste a thread that’s just sitting inside the expiry closure doing
/// nothing. Moreover, this is a Dispatch worker thread, so there’s a limit to
/// how many times you can do this.  So, you have to be _really_ careful not to
/// allocate too many instances of this class.
///
/// I could fix this by having all the instances share a single assertion but…
/// well… let’s just say this code is already complicated.
@MainActor
final class QRunInBackgroundAssertion {

    /// The name used when creating the assertion.

    let name: String

    /// Called when the system releases the assertion itself.
    ///
    /// This is called on the main thread.
    ///
    /// To help avoid retain cycles, the object sets this to `nil` whenever the
    /// assertion is released.
    var systemDidReleaseAssertion: (@Sendable () -> Void)? {
        willSet { dispatchPrecondition(condition: .onQueue(.main)) }
    }

    private let state: OSAllocatedUnfairLock<State>
    private enum State: Equatable {
        case starting
        case started(DispatchSemaphore)
        case released
    }

    /// Creates an assertion with the given name.
    ///
    /// The name isn’t used by the system but it does show up in various logs so
    /// it’s important to choose one that’s meaningful to you.
    ///
    /// Must be called on the main thread.
    @MainActor
    init(name: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.name = name
        self.systemDidReleaseAssertion = nil
        self.state = OSAllocatedUnfairLock(initialState: .starting)

        // See “Concurrency Notes” below.
        ProcessInfo.processInfo.performExpiringActivity(withReason: name) { didExpire in
            let semaphore: DispatchSemaphore? = self.state.withLock { state -> DispatchSemaphore? in
                switch (state, didExpire) {
                case (.starting, true):
                    // Failed to start; we can’t represent this in our API so we
                    // just flipped to the `.released` state and we’re done.
                    state = .released
                    return nil
                case (.starting, false):
                    // Started successfully.  Let’s block (outside the lock, of
                    // course) waiting on the semaphore.
                    let semaphore = DispatchSemaphore(value: 0)
                    state = .started(semaphore)
                    return semaphore
                case (.started(let semaphore), true):
                    // We have started and now we’re expiring.  Signal our
                    // semaphore to unblock the thread that’s waiting on it.
                    semaphore.signal()
                    state = .released
                    // Run the ‘did release’ callback.  This is async, so we can
                    // kick it off with the lock held.
                    DispatchQueue.main.async { self.runSystemDidReleaseAssertion() }
                    return nil
                case (.started(_), false):
                    // This shouldn’t be possible.
                    fatalError()
                case (.released, _):
                    // Our client called `release()` before we managed to start.
                    // That’s weird, but easy to handle.
                    return nil
                }
            }
            if let semaphore {
                semaphore.wait()
            }
        }
    }

    /// Release the assertion.
    ///
    /// It’s safe to call this redundantly, that is, call it twice in a row or
    /// call it on an assertion that’s expired.
    ///
    /// Must be called on the main thread.
    func release() {
        dispatchPrecondition(condition: .onQueue(.main))
        self.releaseOnAnyThread()
        // Set to `nil` to reduce the chances of a retain loop.
        self.systemDidReleaseAssertion = nil
    }

    func isReleased() -> Bool {
        return self.state.withLock { state in
            return state == .released
        }
    }

    private nonisolated func releaseOnAnyThread() {
        self.state.withLock { state in
            switch state {
            case .starting:
                // The transition from `.starting` to `.started` happens
                // asynchonously, so it’s possible that you could release the
                // assertion before that’s completed. This sets the state to
                // `.released` so that the concurrent code doing the transition
                // just gives up.
                state = .released
            case .started(let semaphore):
                // Unblock the thread waiting in our closure.
                semaphore.signal()
                state = .released
            case .released:
                // Releasing redundantly is a no-op.
                break
            }
        }
    }

    private func runSystemDidReleaseAssertion() {
        dispatchPrecondition(condition: .onQueue(.main))
        self.systemDidReleaseAssertion?()
        // Set to `nil` to reduce the chances of a retain loop.
        self.systemDidReleaseAssertion = nil
    }

    deinit {
        // We don’t apply this assert because it’s hard to force the last object
        // reference to be released on the main thread.  Fortunately,
        // `releaseOnAnyThread()` is thread safe.
        //
        // dispatchPrecondition(condition: .onQueue(.main))

        self.releaseOnAnyThread()

        // We don’t nil out `systemDidReleaseAssertion` here because that
        // property is confined to the main thread and we can’t be sure we’re
        // running on the main thread.  However, that’s not a problem because
        // the rationale for nil’ing this out is to minimise retain loop and, if
        // we got to this deinitialiser, that’s not a problem.

        // self.systemDidReleaseAssertion = nil
    }
}
#endif
