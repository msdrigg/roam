#if os(iOS)
import ActivityKit
import AppIntents
import Foundation

struct TimedMuteActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Status: String, Codable, Hashable {
            case muted
            case unmuting
            case unmuted
            case unmuteFailed
        }

        var status: Status
        var endsAt: Date
    }

    var deviceName: String
    var startedAt: Date
}

/// The Live Activity's Unmute button. A `LiveActivityIntent` runs in the app's
/// process, launching it in the background if needed, so it reaches the same
/// `TimedMuteController` as the in-app pill.
struct UnmuteTimedMuteIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Unmute", comment: "Title for the intent behind the Unmute button on the timed mute Live Activity")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await TimedMuteActivityBridge.unmute?()
        return .result()
    }
}

/// Set by the app at launch. Stays nil in the widget extension, which never
/// runs the intent.
@MainActor
enum TimedMuteActivityBridge {
    static var unmute: (@MainActor () async -> Void)?
}
#endif
