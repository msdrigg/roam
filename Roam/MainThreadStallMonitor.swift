import Darwin
import Foundation
import os

#if canImport(UIKit)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Logs from its own thread while the main thread stops answering.
///
/// A watchdog kill leaves MetricKit one sample of the main thread, and the file
/// log goes quiet when the stall begins because nearly everything that logs
/// waits on main. This thread does not, so the log keeps a running stall length
/// and records a `SIGTERM` arriving during it.
enum MainThreadStallMonitor {
    private static let pingInterval: TimeInterval = 0.5
    private static let reportInterval: TimeInterval = 2
    /// A tick this late means the whole process was suspended, not that main
    /// stalled. A stuck main thread does not delay this thread's own sleep.
    private static let suspensionGap: TimeInterval = 2

    private struct Context: Sendable {
        var applicationState = "not yet sampled"
        var scenes = "not yet sampled"
        var backgroundTimeRemaining: TimeInterval?
    }

    private struct State: Sendable {
        var lastAnswer = ProcessInfo.processInfo.systemUptime
        var lastAnswerCPU: TimeInterval?
        var pingOutstanding = false
        var reportedStall: TimeInterval = 0
        var launch = "unknown"
        var context = Context()
        var checkpoints: [(time: TimeInterval, label: String)] = []
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static let started = OSAllocatedUnfairLock(initialState: false)
    nonisolated(unsafe) private static var terminationSource: DispatchSourceSignal?

    /// Idempotent: `RoamApp.init` runs on every rebuild of the `App` value.
    @MainActor
    static func start() {
        let first = started.withLock { started in
            defer { started = true }
            return !started
        }
        guard first else { return }

        let mainThread = pthread_mach_thread_np(pthread_self())
        let cpu = sampleThread(mainThread)?.cpu
        state.withLock {
            $0.lastAnswer = ProcessInfo.processInfo.systemUptime
            $0.lastAnswerCPU = cpu
        }
        checkpoint("App initialization started")
        let thread = Thread { run(mainThread: mainThread) }
        thread.name = "com.msdrigg.roam.main-stall-monitor"
        thread.qualityOfService = .userInitiated
        thread.start()
        observeTermination()
    }

    @MainActor
    static func noteLaunch(_ launch: String) {
        let context = sampleContext()
        state.withLock {
            $0.launch = launch
            $0.context = context
        }
        checkpoint("Application did finish launching")
    }

    static func checkpoint(_ label: String) {
        let now = ProcessInfo.processInfo.systemUptime
        state.withLock {
            if $0.checkpoints.count == 8 { $0.checkpoints.removeFirst() }
            $0.checkpoints.append((now, label))
        }
    }

    /// Context as of the main thread's last answer, which during a stall is
    /// the moment it began.
    static func describeLastAnswer() -> String {
        let (stall, snapshot) = state.withLock { state in
            (ProcessInfo.processInfo.systemUptime - state.lastAnswer, state)
        }
        return "main last answered \(seconds(stall))s ago, \(describe(snapshot))"
    }

    private static func run(mainThread: thread_t) {
        var lastTick = ProcessInfo.processInfo.systemUptime
        while true {
            Thread.sleep(forTimeInterval: pingInterval)
            let now = ProcessInfo.processInfo.systemUptime
            let resumed = now - lastTick > suspensionGap
            lastTick = now
            let threadSample = sampleThread(mainThread)

            let (ping, report) = state.withLock { state -> (Bool, (TimeInterval, State)?) in
                if resumed {
                    state.lastAnswer = now
                    state.lastAnswerCPU = threadSample?.cpu
                    state.reportedStall = 0
                }
                let stall = now - state.lastAnswer
                var report: (TimeInterval, State)?
                if stall >= state.reportedStall + reportInterval {
                    state.reportedStall = stall
                    report = (stall, state)
                }
                let ping = !state.pingOutstanding
                state.pingOutstanding = true
                return (ping, report)
            }

            if let report {
                let (stall, snapshot) = report
                Log.lifecycle.error(
                    "Main thread unresponsive for \(seconds(stall), privacy: .public)s; at stall start \(describe(snapshot), privacy: .public)"
                )
                if let threadSample, let baseline = snapshot.lastAnswerCPU {
                    let cpu = max(0, threadSample.cpu - baseline)
                    Log.lifecycle.error(
                        "Stall main-thread CPU=\(seconds(cpu), privacy: .public)s over \(seconds(stall), privacy: .public)s wall; threadState=\(threadSample.runState, privacy: .public)"
                    )
                }
                let history = snapshot.checkpoints.map {
                    "\(seconds(now - $0.time))s ago: \($0.label)"
                }.joined(separator: " | ")
                Log.lifecycle.error("Stall checkpoints: \(history, privacy: .public)")
                FileLog.flushNow()
            }
            if ping {
                DispatchQueue.main.async { answer() }
            }
        }
    }

    private static func answer() {
        let context = MainActor.assumeIsolated { sampleContext() }
        let now = ProcessInfo.processInfo.systemUptime
        let cpu = sampleThread(pthread_mach_thread_np(pthread_self()))?.cpu
        let recovered = state.withLock { state -> TimeInterval? in
            let stall = state.reportedStall > 0 ? now - state.lastAnswer : nil
            state.lastAnswer = now
            state.lastAnswerCPU = cpu
            state.pingOutstanding = false
            state.reportedStall = 0
            state.context = context
            return stall
        }
        if let recovered {
            Log.lifecycle.notice(
                "Main thread answered again after a \(seconds(recovered), privacy: .public)s stall")
        }
    }

    // Reading thread accounting does not suspend main or unwind a stack that
    // may hold allocator locks. CPU time is cumulative and needs a ping baseline.
    private static func sampleThread(_ thread: thread_t) -> (cpu: TimeInterval, runState: Int32)? {
        var info = thread_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let cpu = Double(info.user_time.seconds) + Double(info.system_time.seconds)
            + (Double(info.user_time.microseconds) + Double(info.system_time.microseconds)) / 1_000_000
        return (cpu, info.run_state)
    }

    /// A dispatch source leaves `SIGTERM`'s disposition alone, so whatever
    /// UIKit or the default action does with the signal still happens.
    private static func observeTermination() {
        let source = DispatchSource.makeSignalSource(
            signal: SIGTERM, queue: .global(qos: .userInitiated))
        source.setEventHandler {
            Log.lifecycle.notice(
                "SIGTERM received, the system asked Roam to quit; \(describeLastAnswer(), privacy: .public)"
            )
            FileLog.flushNow()
        }
        source.resume()
        terminationSource = source
    }

    @MainActor
    private static func sampleContext() -> Context {
        var context = Context()
        #if canImport(UIKit)
            let application = UIApplication.shared
            switch application.applicationState {
            case .active: context.applicationState = "active"
            case .inactive: context.applicationState = "inactive"
            case .background:
                context.applicationState = "background"
                context.backgroundTimeRemaining = application.backgroundTimeRemaining
            @unknown default: context.applicationState = "unknown"
            }
            context.scenes = application.connectedScenes.map { scene in
                switch scene.activationState {
                case .foregroundActive: "foregroundActive"
                case .foregroundInactive: "foregroundInactive"
                case .background: "background"
                case .unattached: "unattached"
                @unknown default: "unknown"
                }
            }.joined(separator: ",")
        #elseif os(macOS)
            context.applicationState = NSApp.isActive ? "active" : "inactive"
            context.scenes = NSApp.windows.filter(\.isVisible).count.description + " visible windows"
        #endif
        return context
    }

    private static func describe(_ snapshot: State) -> String {
        var text =
            "app=\(snapshot.context.applicationState) scenes=[\(snapshot.context.scenes)] launch=\(snapshot.launch)"
        if let remaining = snapshot.context.backgroundTimeRemaining {
            // UIKit reports DBL_MAX while nothing limits background time.
            text += " backgroundTimeRemaining="
            text += remaining > 1e9 ? "unlimited" : "\(seconds(remaining))s"
        }
        return text
    }

    private static func seconds(_ interval: TimeInterval) -> String {
        String(format: "%.1f", interval)
    }
}
