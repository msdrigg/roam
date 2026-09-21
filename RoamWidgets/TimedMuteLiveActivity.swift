#if os(iOS)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct TimedMuteLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimedMuteActivityAttributes.self) { context in
            AccentTinted { TimedMuteLockScreenView(context: context) }
                .activityBackgroundTint(Color.widgetBackground)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AccentTinted {
                        Label {
                            Text(context.attributes.deviceName)
                                .lineLimit(1)
                        } icon: {
                            TimedMuteIcon(status: context.state.status, isStale: context.isStale)
                        }
                        .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimedMuteCountdown(context: context)
                        .font(.title2.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AccentTinted { TimedMuteDetail(context: context) }
                }
            } compactLeading: {
                AccentTinted { TimedMuteIcon(status: context.state.status, isStale: context.isStale) }
            } compactTrailing: {
                // A ring rather than digits: iPhone Duo's vertical island is
                // too narrow for a countdown.
                AccentTinted { TimedMuteRing(context: context) }
            } minimal: {
                AccentTinted { TimedMuteIcon(status: context.state.status, isStale: context.isStale) }
            }
        }
    }
}

private struct TimedMuteLockScreenView: View {
    let context: ActivityViewContext<TimedMuteActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TimedMuteIcon(status: context.state.status, isStale: context.isStale)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.deviceName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(statusText(context))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                TimedMuteCountdown(context: context)
                    .font(.title.weight(.semibold))
            }
            TimedMuteDetail(context: context)
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}

/// The progress bar while the timer runs, and the Unmute button whenever the
/// sound is still off.
private struct TimedMuteDetail: View {
    let context: ActivityViewContext<TimedMuteActivityAttributes>

    private var isCounting: Bool {
        context.state.status == .muted && !context.isStale
    }

    var body: some View {
        if isCounting || showsUnmuteButton(context) {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            if isCounting {
                ProgressView(
                    timerInterval: context.attributes.startedAt...context.state.endsAt,
                    countsDown: true
                ) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                Spacer(minLength: 0)
            }
            if showsUnmuteButton(context) {
                Button(intent: UnmuteTimedMuteIntent()) {
                    Label(
                        String(localized: "Unmute", comment: "Button on the timed mute Live Activity that turns the sound back on now"),
                        systemImage: "speaker.wave.2.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct TimedMuteCountdown: View {
    let context: ActivityViewContext<TimedMuteActivityAttributes>

    var body: some View {
        if context.state.status == .muted, !context.isStale {
            Text(timerInterval: context.attributes.startedAt...context.state.endsAt, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct TimedMuteRing: View {
    let context: ActivityViewContext<TimedMuteActivityAttributes>

    var body: some View {
        if context.state.status == .muted, !context.isStale {
            ProgressView(
                timerInterval: context.attributes.startedAt...context.state.endsAt,
                countsDown: true
            ) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .frame(width: 20, height: 20)
        } else {
            TimedMuteIcon(status: context.state.status, isStale: context.isStale)
        }
    }
}

/// Applies the accent colour the user picked in the app, as the other widgets do.
private struct AccentTinted<Content: View>: View {
    @AppStorageColor(UserDefaultKeys.customAccentColor) private var customAccentColor: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        content.tint(customAccentColor)
    }
}

private struct TimedMuteIcon: View {
    let status: TimedMuteActivityAttributes.ContentState.Status
    let isStale: Bool

    var body: some View {
        switch status {
        case .unmuted:
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.green)
        case .unmuteFailed:
            Image(systemName: "speaker.slash.fill")
                .foregroundStyle(.orange)
        case .muted, .unmuting:
            Image(systemName: "speaker.slash.fill")
                .foregroundStyle(isStale ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint))
        }
    }
}

private func showsUnmuteButton(_ context: ActivityViewContext<TimedMuteActivityAttributes>) -> Bool {
    switch context.state.status {
    case .muted, .unmuteFailed: true
    case .unmuting, .unmuted: false
    }
}

private func statusText(_ context: ActivityViewContext<TimedMuteActivityAttributes>) -> String {
    switch context.state.status {
    case .muted where context.isStale:
        String(localized: "Mute timer ended", comment: "Timed mute Live Activity status once the countdown has run out but the TV was not unmuted yet")
    case .muted:
        String(localized: "Muted", comment: "Timed mute Live Activity status while the countdown runs")
    case .unmuting:
        String(localized: "Unmuting…", comment: "Timed mute Live Activity status while Roam turns the sound back on")
    case .unmuted:
        String(localized: "Sound back on", comment: "Timed mute Live Activity status after the TV was unmuted")
    case .unmuteFailed:
        String(localized: "Couldn't unmute", comment: "Timed mute Live Activity status when Roam failed to unmute the TV")
    }
}

#Preview("Lock screen", as: .content, using: TimedMuteActivityAttributes(deviceName: "Living Room TV", startedAt: .now)) {
    TimedMuteLiveActivity()
} contentStates: {
    TimedMuteActivityAttributes.ContentState(status: .muted, endsAt: .now.addingTimeInterval(60))
    TimedMuteActivityAttributes.ContentState(status: .unmuteFailed, endsAt: .now)
}
#endif
