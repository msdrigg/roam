#if !os(watchOS)
import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

enum MuteReading: Sendable, Equatable {
    case muted
    case unmuted
    /// The device answered but has no usable audio state.
    case unknown
    case unreachable
}

struct TimedMuteTarget: Codable, Equatable, Sendable {
    let deviceId: String
    let location: String
    let name: String
    /// Only a TV's own `query/audio-device` tracks its speakers. A stick
    /// forwards mute over HDMI-CEC and keeps reporting unmuted, so its mute
    /// can only be toggled blind.
    var reportsMuteState: Bool

    init(deviceId: String, location: String, name: String, reportsMuteState: Bool) {
        self.deviceId = deviceId
        self.location = location
        self.name = name
        self.reportsMuteState = reportsMuteState
    }

    init(device: Device) {
        self.init(
            deviceId: device.id,
            location: device.location,
            name: device.name,
            reportsMuteState: device.isTV == true
        )
    }
}

struct TimedMuteSession: Codable, Equatable, Sendable {
    let target: TimedMuteTarget
    let startedAt: Date
    let endsAt: Date

    var duration: TimeInterval {
        endsAt.timeIntervalSince(startedAt)
    }
}

enum TimedMutePhase: Equatable {
    case idle
    case muting(TimedMuteTarget)
    case active(TimedMuteSession)
    case unmuting(TimedMuteSession)
    case unmuted(TimedMuteTarget)
    case muteFailed(TimedMuteTarget)
    case unmuteFailed(TimedMuteSession)

    var target: TimedMuteTarget? {
        switch self {
        case .idle: nil
        case .muting(let target), .unmuted(let target), .muteFailed(let target): target
        case .active(let session), .unmuting(let session), .unmuteFailed(let session): session.target
        }
    }

    var session: TimedMuteSession? {
        switch self {
        case .active(let session), .unmuting(let session), .unmuteFailed(let session): session
        default: nil
        }
    }

    var isInFlight: Bool {
        switch self {
        case .muting, .active, .unmuting: true
        default: false
        }
    }
}

/// Mutes a device for a fixed time, then unmutes it.
///
/// iOS gives no way for an app to wake itself at a set time, so the unmute is
/// covered three ways: a background task assertion keeps the countdown running
/// for the (roughly 30 second) grace iOS allows after backgrounding, a local
/// notification with a background "Unmute" action fires if the app was
/// suspended anyway, and the session is persisted so a relaunch or return to
/// the foreground finishes an overdue unmute.
@MainActor @Observable
final class TimedMuteController {
    static let durations = [30, 60, 90]
    nonisolated static let notificationCategory = "com.msdrigg.roam.timedMute"
    static let unmuteActionIdentifier = "com.msdrigg.roam.timedMute.unmute"
    private static let notificationIdentifier = "com.msdrigg.roam.timedMute.pending"
    // An unmute this overdue is dropped on launch rather than replayed: by
    // then the TV has likely been unmuted by hand or switched off.
    private static let staleAfter: TimeInterval = 15 * 60
    // Gives the in-app countdown a head start so the notification only lands
    // when the app really was suspended.
    private static let notificationGrace: TimeInterval = 3

    struct Driver: Sendable {
        var read: @Sendable (String) async -> MuteReading
        var press: @Sendable (String) async throws -> Void
        var confirmInterval: Duration = .milliseconds(250)
        var confirmAttempts = 6
        var unmuteRetryDelays: [Duration] = [.zero, .seconds(1), .seconds(2), .seconds(3), .seconds(5), .seconds(8)]
    }

    private(set) var phase: TimedMutePhase = .idle

    @ObservationIgnored private let driver: Driver
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let usesSystemServices: Bool
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var messageDismissal: Task<Void, Never>?
    @ObservationIgnored private var foregroundObserver: (any NSObjectProtocol)?
    #if canImport(UIKit)
    @ObservationIgnored private var backgroundAssertion: QRunInBackgroundAssertion?
    #endif

    init(driver: Driver, defaults: UserDefaults = .standard, usesSystemServices: Bool = true) {
        self.driver = driver
        self.defaults = defaults
        self.usesSystemServices = usesSystemServices
        guard usesSystemServices else { return }

        let unmute = UNNotificationAction(
            identifier: Self.unmuteActionIdentifier,
            title: String(localized: "Unmute", comment: "Action on the notification sent when a timed mute ends"),
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Self.notificationCategory, actions: [unmute], intentIdentifiers: [])
        ])
        #if canImport(UIKit)
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeIfNeeded() }
        }
        #endif
    }

    func phase(forDevice deviceId: String?) -> TimedMutePhase {
        phase.target?.deviceId == deviceId ? phase : .idle
    }

    func start(_ target: TimedMuteTarget, duration: TimeInterval) {
        Log.userInteraction.notice("Starting \(duration, privacy: .public)s timed mute on \(target.location, privacy: .public)")
        cancelWork()
        removeNotification()
        show(.muting(target))
        work = Task { [weak self] in
            await self?.muteThenWait(target, duration: duration)
        }
    }

    /// Ends the countdown early, or retries a failed unmute.
    func unmuteNow() {
        guard let session = phase.session else { return }
        cancelWork()
        work = Task { [weak self] in
            await self?.unmute(session)
        }
    }

    /// Drops the timer without touching the TV, for when the user has toggled
    /// mute themselves.
    func cancel() {
        guard phase != .idle || loadSession() != nil else { return }
        Log.userInteraction.notice("Cancelling timed mute")
        cancelWork()
        clearSession()
        removeNotification()
        releaseBackgroundTime()
        show(.idle)
    }

    func dismissMessage() {
        switch phase {
        case .unmuted, .muteFailed:
            show(.idle)
        case .unmuteFailed:
            cancel()
        default:
            break
        }
    }

    /// Picks up a session persisted by an earlier launch, or one whose
    /// deadline passed while the app was suspended.
    func resumeIfNeeded() {
        guard !phase.isInFlight, let session = loadSession() else { return }
        if Date.now.timeIntervalSince(session.endsAt) > Self.staleAfter {
            Log.userInteraction.notice("Dropping stale timed mute that ended at \(session.endsAt, privacy: .public)")
            clearSession()
            return
        }
        Log.userInteraction.notice("Resuming timed mute ending at \(session.endsAt, privacy: .public)")
        cancelWork()
        show(.active(session))
        holdBackgroundTime()
        work = Task { [weak self] in
            await self?.waitThenUnmute(session)
        }
    }

    /// Runs the unmute for a tap on the timed-mute notification and returns
    /// once it has finished, so the caller can hold the background launch
    /// open until then.
    func handleNotificationResponse() async {
        if case .unmuting = phase, let work {
            await work.value
            return
        }
        guard let session = phase.session ?? loadSession() else { return }
        cancelWork()
        let task = Task<Void, Never> { [weak self] in
            await self?.unmute(session)
        }
        work = task
        await task.value
    }

    // MARK: - Sequence

    private func muteThenWait(_ target: TimedMuteTarget, duration: TimeInterval) async {
        guard let confirmed = await mute(target) else {
            guard !Task.isCancelled else { return }
            Log.userInteraction.warning("Timed mute could not mute \(target.location, privacy: .public)")
            show(.muteFailed(target))
            dismissLater(after: .seconds(3.5))
            return
        }
        guard !Task.isCancelled else { return }
        let now = Date.now
        let session = TimedMuteSession(target: confirmed, startedAt: now, endsAt: now.addingTimeInterval(duration))
        saveSession(session)
        show(.active(session))
        holdBackgroundTime()
        scheduleNotification(for: session)
        await waitThenUnmute(session)
    }

    private func waitThenUnmute(_ session: TimedMuteSession) async {
        let remaining = session.endsAt.timeIntervalSinceNow
        if remaining > 0 {
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return
            }
        }
        await unmute(session)
    }

    private func unmute(_ session: TimedMuteSession) async {
        show(.unmuting(session))
        let succeeded = await performUnmute(session.target)
        guard !Task.isCancelled else { return }
        if succeeded {
            Log.userInteraction.notice("Timed mute finished on \(session.target.location, privacy: .public)")
            clearSession()
            removeNotification()
            show(.unmuted(session.target))
            dismissLater(after: .seconds(2))
        } else {
            Log.userInteraction.warning("Timed mute could not unmute \(session.target.location, privacy: .public)")
            show(.unmuteFailed(session))
            // The pending notification is the only retry left once the app
            // suspends, so keep it unless the failure is already on screen.
            #if canImport(UIKit)
            if usesSystemServices, UIApplication.shared.applicationState == .active {
                removeNotification()
            }
            #endif
        }
        releaseBackgroundTime()
    }

    /// Returns the target with `reportsMuteState` corrected by what the device
    /// said, or nil if the TV could not be muted.
    private func mute(_ target: TimedMuteTarget) async -> TimedMuteTarget? {
        var target = target
        let before: MuteReading = target.reportsMuteState ? await driver.read(target.location) : .unknown
        if before == .muted {
            return target
        }
        if before == .unknown {
            target.reportsMuteState = false
        }
        do {
            try await driver.press(target.location)
        } catch {
            Log.userInteraction.warning("Timed mute keypress failed: \(error, privacy: .public)")
            return nil
        }
        guard target.reportsMuteState else {
            return target
        }
        switch await confirm(.muted, at: target.location) {
        case .muted:
            return target
        case .unmuted:
            return nil
        case .unknown, .unreachable:
            // The keypress was accepted, so trust it over an audio query that
            // has stopped answering.
            target.reportsMuteState = false
            return target
        }
    }

    private func performUnmute(_ target: TimedMuteTarget) async -> Bool {
        for delay in driver.unmuteRetryDelays {
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return false
                }
            }
            guard target.reportsMuteState else {
                if (try? await driver.press(target.location)) != nil {
                    return true
                }
                continue
            }
            switch await driver.read(target.location) {
            case .unmuted:
                return true
            case .unknown:
                return (try? await driver.press(target.location)) != nil
            case .unreachable:
                continue
            case .muted:
                guard (try? await driver.press(target.location)) != nil else { continue }
                if await confirm(.unmuted, at: target.location) == .unmuted {
                    return true
                }
            }
        }
        return false
    }

    /// Polls until the device reports `expected`, returning the last reading.
    private func confirm(_ expected: MuteReading, at location: String) async -> MuteReading {
        var reading = MuteReading.unreachable
        for _ in 0..<driver.confirmAttempts {
            try? await Task.sleep(for: driver.confirmInterval)
            reading = await driver.read(location)
            if reading == expected {
                break
            }
        }
        return reading
    }

    // MARK: - State

    private func show(_ newPhase: TimedMutePhase) {
        messageDismissal?.cancel()
        messageDismissal = nil
        phase = newPhase
    }

    private func dismissLater(after delay: Duration) {
        let shown = phase
        messageDismissal = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.phase == shown else { return }
            self.phase = .idle
        }
    }

    private func cancelWork() {
        work?.cancel()
        work = nil
    }

    private func saveSession(_ session: TimedMuteSession) {
        defaults.set(try? JSONEncoder().encode(session), forKey: UserDefaultKeys.pendingTimedMute)
    }

    private func loadSession() -> TimedMuteSession? {
        guard let data = defaults.data(forKey: UserDefaultKeys.pendingTimedMute) else { return nil }
        return try? JSONDecoder().decode(TimedMuteSession.self, from: data)
    }

    private func clearSession() {
        defaults.removeObject(forKey: UserDefaultKeys.pendingTimedMute)
    }

    // MARK: - Background

    private func holdBackgroundTime() {
        #if canImport(UIKit)
        guard usesSystemServices, backgroundAssertion?.isReleased() ?? true else { return }
        let assertion = QRunInBackgroundAssertion(name: "timed-mute")
        assertion.systemDidReleaseAssertion = {
            Log.userInteraction.notice("Background time ran out during a timed mute; the notification takes over")
        }
        backgroundAssertion = assertion
        #endif
    }

    private func releaseBackgroundTime() {
        #if canImport(UIKit)
        backgroundAssertion?.release()
        backgroundAssertion = nil
        #endif
    }

    private func scheduleNotification(for session: TimedMuteSession) {
        guard usesSystemServices else { return }
        Task { [weak self] in
            let center = UNUserNotificationCenter.current()
            var status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                status = await center.notificationSettings().authorizationStatus
            }
            guard status == .authorized || status == .provisional else {
                Log.notifications.notice("Timed mute notification skipped, authorization \(status.rawValue, privacy: .public)")
                return
            }
            guard let self, self.phase.session == session else { return }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "Mute timer ended", comment: "Title of the notification sent when a timed mute ends")
            content.body = String(
                localized: "Tap Unmute to turn the sound back on for \(session.target.name).",
                comment: "Body of the notification sent when a timed mute ends. The argument is the device name"
            )
            content.sound = .default
            content.categoryIdentifier = Self.notificationCategory
            let delay = max(1, session.endsAt.timeIntervalSinceNow + Self.notificationGrace)
            let request = UNNotificationRequest(
                identifier: Self.notificationIdentifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                Log.notifications.error("Failed to schedule timed mute notification: \(error, privacy: .public)")
            }
        }
    }

    private func removeNotification() {
        guard usesSystemServices else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
    }
}

extension TimedMuteController.Driver {
    static func live(ecpMonitor: ECPMonitor) -> Self {
        Self(
            read: { location in
                await readMuteState(location: location)
            },
            press: { location in
                try await pressMute(location: location, ecpMonitor: ecpMonitor)
            }
        )
    }

    private static func readMuteState(location: String) async -> MuteReading {
        guard let url = URL(string: "\(location)query/audio-device") else { return .unknown }
        let data: Data
        do {
            let (body, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 3))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .unknown }
            data = body
        } catch {
            return .unreachable
        }
        guard let audio = try? XMLStreamDecoder().decode(AudioDevice.self, from: data) else {
            return .unknown
        }
        return audio.globalInfo.muted ? .muted : .unmuted
    }

    @MainActor
    private static func pressMute(location: String, ecpMonitor: ECPMonitor) async throws {
        if let client = ecpMonitor.ecpClient, client.location.absoluteString == location, ecpMonitor.status == .connected {
            do {
                try await client.pressButton(.mute)
                return
            } catch {
                Log.connection.notice("Shared session failed to send mute, retrying on a new connection: \(error, privacy: .public)")
            }
        }
        guard let url = URL(string: location) else {
            throw URLError(.badURL)
        }
        try await ECPWebsocketClient(location: url).oneOff { session in
            try await session.pressButton(.mute)
        }
    }
}
#endif
