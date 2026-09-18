import Foundation
import Testing
@testable import Roam

private actor FakeTV {
    var muted = false
    var presses = 0
    var reportsState = true
    var reachable = true
    var pressFails = false
    var ignoresPresses = false

    func configure(muted: Bool = false, reportsState: Bool = true, pressFails: Bool = false, ignoresPresses: Bool = false) {
        self.muted = muted
        self.reportsState = reportsState
        self.pressFails = pressFails
        self.ignoresPresses = ignoresPresses
    }

    func setMuted(_ value: Bool) {
        muted = value
    }

    func setReachable(_ value: Bool) {
        reachable = value
    }

    func read() -> MuteReading {
        guard reachable else { return .unreachable }
        guard reportsState else { return .unknown }
        return muted ? .muted : .unmuted
    }

    func press() throws {
        presses += 1
        if pressFails || !reachable {
            throw URLError(.cannotConnectToHost)
        }
        if !ignoresPresses {
            muted.toggle()
        }
    }
}

@MainActor
struct TimedMuteControllerTests {
    private let tv = FakeTV()
    private let defaults: UserDefaults

    init() {
        let suite = "TimedMuteControllerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeController() -> TimedMuteController {
        let tv = tv
        let driver = TimedMuteController.Driver(
            read: { _ in await tv.read() },
            press: { _ in try await tv.press() },
            confirmInterval: .milliseconds(5),
            confirmAttempts: 3,
            unmuteRetryDelays: [.zero, .milliseconds(10), .milliseconds(10)]
        )
        return TimedMuteController(driver: driver, defaults: defaults, usesSystemServices: false)
    }

    private func target(reportsMuteState: Bool = true) -> TimedMuteTarget {
        TimedMuteTarget(deviceId: "tv", location: "http://tv:8060/", name: "Living Room", reportsMuteState: reportsMuteState)
    }

    private func waitFor(
        _ controller: TimedMuteController,
        timeout: Duration = .seconds(2),
        until condition: (TimedMutePhase) -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition(controller.phase) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition(controller.phase)
    }

    @Test func mutesCountsDownAndUnmutes() async {
        let controller = makeController()
        controller.start(target(), duration: 0.2)

        #expect(await waitFor(controller) { if case .active = $0 { true } else { false } })
        #expect(await tv.muted)
        #expect(defaults.data(forKey: UserDefaultKeys.pendingTimedMute) != nil)

        #expect(await waitFor(controller) { if case .unmuted = $0 { true } else { false } })
        #expect(await tv.muted == false)
        #expect(await tv.presses == 2)
        #expect(defaults.data(forKey: UserDefaultKeys.pendingTimedMute) == nil)
    }

    @Test func failedKeypressShowsMuteFailure() async {
        await tv.configure(pressFails: true)
        let controller = makeController()
        controller.start(target(), duration: 5)

        #expect(await waitFor(controller) { if case .muteFailed = $0 { true } else { false } })
        #expect(defaults.data(forKey: UserDefaultKeys.pendingTimedMute) == nil)
    }

    @Test func keypressTheTVIgnoresShowsMuteFailure() async {
        await tv.configure(ignoresPresses: true)
        let controller = makeController()
        controller.start(target(), duration: 5)

        #expect(await waitFor(controller) { if case .muteFailed = $0 { true } else { false } })
    }

    @Test func alreadyMutedTVIsNotToggled() async {
        await tv.configure(muted: true)
        let controller = makeController()
        controller.start(target(), duration: 5)

        #expect(await waitFor(controller) { if case .active = $0 { true } else { false } })
        #expect(await tv.presses == 0)
        #expect(await tv.muted)
    }

    @Test func manualCancelLeavesTheTVAlone() async {
        let controller = makeController()
        controller.start(target(), duration: 0.15)
        #expect(await waitFor(controller) { if case .active = $0 { true } else { false } })

        controller.cancel()
        try? await Task.sleep(for: .milliseconds(300))

        #expect(controller.phase == .idle)
        #expect(await tv.presses == 1)
        #expect(defaults.data(forKey: UserDefaultKeys.pendingTimedMute) == nil)
    }

    @Test func unmuteNowEndsEarly() async {
        let controller = makeController()
        controller.start(target(), duration: 60)
        #expect(await waitFor(controller) { if case .active = $0 { true } else { false } })

        controller.unmuteNow()

        #expect(await waitFor(controller) { if case .unmuted = $0 { true } else { false } })
        #expect(await tv.muted == false)
    }

    @Test func alreadyUnmutedByHandIsNotToggledBack() async {
        let controller = makeController()
        controller.start(target(), duration: 0.2)
        #expect(await waitFor(controller) { if case .active = $0 { true } else { false } })

        await tv.setMuted(false)

        #expect(await waitFor(controller) { if case .unmuted = $0 { true } else { false } })
        #expect(await tv.muted == false)
        #expect(await tv.presses == 1)
    }

    @Test func stickWithoutMuteStateTogglesBlind() async {
        await tv.configure(reportsState: false)
        let controller = makeController()
        controller.start(target(reportsMuteState: false), duration: 0.1)

        #expect(await waitFor(controller) { if case .unmuted = $0 { true } else { false } })
        #expect(await tv.presses == 2)
        #expect(await tv.muted == false)
    }

    @Test func unreachableAtUnmuteTimeFailsAndKeepsTheSession() async {
        let controller = makeController()
        controller.start(target(), duration: 0.1)
        #expect(await waitFor(controller) { if case .active = $0 { true } else { false } })

        await tv.setReachable(false)

        #expect(await waitFor(controller) { if case .unmuteFailed = $0 { true } else { false } })
        #expect(await tv.muted)
        #expect(defaults.data(forKey: UserDefaultKeys.pendingTimedMute) != nil)

        await tv.setReachable(true)
        controller.unmuteNow()

        #expect(await waitFor(controller) { if case .unmuted = $0 { true } else { false } })
        #expect(await tv.muted == false)
    }

    @Test func overdueSessionFromAnEarlierLaunchIsFinished() async throws {
        await tv.setMuted(true)
        let now = Date.now
        let session = TimedMuteSession(target: target(), startedAt: now.addingTimeInterval(-90), endsAt: now.addingTimeInterval(-5))
        defaults.set(try JSONEncoder().encode(session), forKey: UserDefaultKeys.pendingTimedMute)

        let controller = makeController()
        controller.resumeIfNeeded()

        #expect(await waitFor(controller) { if case .unmuted = $0 { true } else { false } })
        #expect(await tv.muted == false)
    }

    @Test func staleSessionIsDropped() async throws {
        await tv.setMuted(true)
        let now = Date.now
        let session = TimedMuteSession(target: target(), startedAt: now.addingTimeInterval(-3600), endsAt: now.addingTimeInterval(-3500))
        defaults.set(try JSONEncoder().encode(session), forKey: UserDefaultKeys.pendingTimedMute)

        let controller = makeController()
        controller.resumeIfNeeded()

        #expect(controller.phase == .idle)
        #expect(await tv.presses == 0)
        #expect(defaults.data(forKey: UserDefaultKeys.pendingTimedMute) == nil)
    }
}
