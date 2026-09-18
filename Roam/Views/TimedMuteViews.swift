#if os(iOS) || os(visionOS)
import SwiftUI

/// Tracks the hold-to-pick menu on the mute button. `ButtonGrid` reads it to
/// keep the button's own tap from toggling mute when a hold ends.
struct MuteHoldState: Equatable {
    enum Menu: Equatable {
        case hidden
        /// The finger that opened the menu is still down.
        case dragging
        /// The hold ended on the button, so the chips wait for a tap.
        case tapToPick
    }

    var menu: Menu = .hidden
    var highlighted: Int?
    var lastEnded: Date = .distantPast

    var swallowsTap: Bool {
        menu != .hidden || Date.now.timeIntervalSince(lastEnded) < 0.5
    }
}

struct TimedMuteHoldModifier: ViewModifier {
    @Binding var state: MuteHoldState
    let onSelect: (Int) -> Void

    @State private var buttonSize: CGSize = .zero
    @State private var revealCount = 0

    private let durations = TimedMuteController.durations
    private let chipWidth: CGFloat = 60
    private let chipSpacing: CGFloat = 6
    private let menuGap: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self, of: \.size) { buttonSize = $0 }
            .simultaneousGesture(holdGesture)
            .overlay(alignment: .top) {
                if state.menu != .hidden {
                    TimedMuteMenu(
                        durations: durations,
                        highlighted: state.highlighted,
                        chipWidth: chipWidth,
                        chipSpacing: chipSpacing,
                        onSelect: commit
                    )
                    .fixedSize()
                    .offset(y: buttonSize.height + menuGap)
                    .transition(
                        .scale(scale: 0.85, anchor: .top)
                            .combined(with: .opacity)
                    )
                }
            }
            .animation(.spring(duration: 0.25, bounce: 0.2), value: state.menu)
            .animation(.spring(duration: 0.18), value: state.highlighted)
            // Keeps the device pager from taking the sideways slide as a page swipe.
            .preference(key: AppsScrollingPreferenceKey.self, value: state.menu == .dragging)
            .task(id: state.menu) {
                guard state.menu == .tapToPick else { return }
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                state.menu = .hidden
            }
            #if !os(visionOS)
            .sensoryFeedback(.impact(weight: .medium), trigger: revealCount)
            .sensoryFeedback(.selection, trigger: state.highlighted) { _, new in new != nil }
            #endif
            .accessibilityActions {
                ForEach(durations, id: \.self) { seconds in
                    Button(String(
                        localized: "Mute for \(seconds) seconds",
                        comment: "Accessibility action on the mute button that mutes for a set time"
                    )) {
                        onSelect(seconds)
                    }
                }
            }
    }

    private var holdGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35, maximumDistance: 14)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if state.menu != .dragging {
                    state.menu = .dragging
                    state.highlighted = nil
                    revealCount += 1
                }
                if let drag {
                    let zone = zone(at: drag.location)
                    if zone != state.highlighted {
                        state.highlighted = zone
                    }
                }
            }
            .onEnded { value in
                guard case .second(true, let drag) = value else { return }
                state.lastEnded = .now
                let location = drag?.location ?? CGPoint(x: buttonSize.width / 2, y: buttonSize.height / 2)
                if let zone = zone(at: location) {
                    commit(durations[zone])
                } else if CGRect(origin: .zero, size: buttonSize).insetBy(dx: -16, dy: -16).contains(location) {
                    state.highlighted = nil
                    state.menu = .tapToPick
                } else {
                    state.highlighted = nil
                    state.menu = .hidden
                }
            }
    }

    /// Anywhere below the button counts, split into columns by the chip
    /// edges, so the slide does not have to land exactly on a chip.
    private func zone(at point: CGPoint) -> Int? {
        guard point.y > buttonSize.height + menuGap / 2 else { return nil }
        let offset = point.x - buttonSize.width / 2
        let edge = chipWidth / 2 + chipSpacing / 2
        if offset < -edge {
            return 0
        } else if offset > edge {
            return durations.count - 1
        }
        return durations.count / 2
    }

    private func commit(_ seconds: Int) {
        state.lastEnded = .now
        state.highlighted = nil
        state.menu = .hidden
        onSelect(seconds)
    }
}

private struct TimedMuteMenu: View {
    let durations: [Int]
    let highlighted: Int?
    let chipWidth: CGFloat
    let chipSpacing: CGFloat
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("Mute for", comment: "Header of the menu that mutes the TV for a set time")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            HStack(spacing: chipSpacing) {
                ForEach(Array(durations.enumerated()), id: \.element) { index, seconds in
                    chip(seconds, isHighlighted: highlighted == index)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 6)
        .padding(.bottom, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(alignment: .top) {
            Caret()
                .fill(.regularMaterial)
                .frame(width: 16, height: 8)
                .offset(y: -7)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .labelStyle(.titleAndIcon)
        .fontDesign(.rounded)
    }

    private func chip(_ seconds: Int, isHighlighted: Bool) -> some View {
        Button {
            onSelect(seconds)
        } label: {
            VStack(spacing: -1) {
                Text(seconds, format: .number)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("sec", comment: "Unit under a timed mute duration, short for seconds")
                    .font(.caption2.weight(.medium))
                    .opacity(0.75)
            }
            .frame(width: chipWidth, height: 48)
            .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                isHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.08)),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .scaleEffect(isHighlighted ? 1.08 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(
            localized: "Mute for \(seconds) seconds",
            comment: "Accessibility action on the mute button that mutes for a set time"
        ))
    }
}

private struct Caret: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// The compact status row shown in the remote's banner slot while a timed
/// mute runs, and briefly after it ends or fails.
struct TimedMuteStatusPill: View {
    let phase: TimedMutePhase
    let onUnmute: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Group {
            switch phase {
            case .idle:
                EmptyView()
            case .muting:
                pill(tint: nil) {
                    ProgressView().controlSize(.mini)
                    Text("Muting…", comment: "Shown while the TV is being muted for a set time")
                }
            case .active(let session):
                ActiveTimedMutePill(session: session, onUnmute: onUnmute)
            case .unmuting:
                pill(tint: nil) {
                    ProgressView().controlSize(.mini)
                    Text("Unmuting…", comment: "Shown while a timed mute is turning the sound back on")
                }
            case .unmuted:
                pill(tint: .green) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.green)
                    Text("Sound back on", comment: "Shown briefly after a timed mute unmutes the TV")
                }
            case .muteFailed:
                Button(action: onDismiss) {
                    pill(tint: .red) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Couldn't mute TV", comment: "Shown when a timed mute fails to mute the TV")
                    }
                }
                .buttonStyle(.plain)
            case .unmuteFailed:
                pill(tint: .red) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Couldn't unmute TV", comment: "Shown when a timed mute fails to unmute the TV")
                    Button(action: onUnmute) {
                        Text("Retry", comment: "Button that retries unmuting the TV after a timed mute failed")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button(
                        String(localized: "Dismiss", comment: "Button that hides a timed mute message"),
                        systemImage: "xmark.circle.fill",
                        action: onDismiss
                    )
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
            }
        }
        .preference(key: BottomBannerVisibleKey.self, value: phase != .idle)
        #if !os(visionOS)
        .sensoryFeedback(trigger: phase) { _, new in
            switch new {
            case .active: .success
            case .muteFailed, .unmuteFailed: .error
            default: nil
            }
        }
        #endif
    }

    private func pill<Content: View>(tint: Color?, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 7) {
            content()
        }
        .font(.footnote.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background((tint ?? .clear).opacity(0.18), in: Capsule())
        .background(.regularMaterial, in: Capsule())
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

private struct ActiveTimedMutePill: View {
    let session: TimedMuteSession
    let onUnmute: () -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let remaining = max(0, session.endsAt.timeIntervalSince(context.date))
            let fraction = session.duration > 0 ? remaining / session.duration : 0
            HStack(spacing: 8) {
                CountdownRing(fraction: fraction)
                    .frame(width: 18, height: 18)
                Text("Muted", comment: "Label on the timed mute countdown")
                    .fontWeight(.semibold)
                Text(Self.format(remaining))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(countsDown: true))
                Button(action: onUnmute) {
                    Label(
                        String(localized: "Unmute", comment: "Button that ends a timed mute early"),
                        systemImage: "speaker.wave.2.fill"
                    )
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("TimedMuteUnmuteButton")
            }
            .font(.footnote)
            .lineLimit(1)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(height: 34)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.tint.opacity(0.22))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .background(.regularMaterial, in: Capsule())
            .clipShape(Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(
                localized: "Muted, \(Int(remaining.rounded(.up))) seconds left",
                comment: "Accessibility label for the timed mute countdown"
            ))
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private static func format(_ remaining: TimeInterval) -> String {
        let seconds = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct CountdownRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 7.5, weight: .bold))
        }
    }
}

#if DEBUG
#Preview("Timed mute pill") {
    let target = TimedMuteTarget(deviceId: "1", location: "http://tv/", name: "Living Room", reportsMuteState: true)
    let session = TimedMuteSession(target: target, startedAt: .now, endsAt: .now.addingTimeInterval(60))
    VStack(spacing: 12) {
        TimedMuteStatusPill(phase: .muting(target), onUnmute: {}, onDismiss: {})
        TimedMuteStatusPill(phase: .active(session), onUnmute: {}, onDismiss: {})
        TimedMuteStatusPill(phase: .unmuted(target), onUnmute: {}, onDismiss: {})
        TimedMuteStatusPill(phase: .muteFailed(target), onUnmute: {}, onDismiss: {})
        TimedMuteStatusPill(phase: .unmuteFailed(session), onUnmute: {}, onDismiss: {})
    }
    .padding()
}
#endif
#endif
