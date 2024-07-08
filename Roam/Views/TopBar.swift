import Foundation
import SwiftUI

struct TopBar: View {
    let pressCounter: (RemoteButton) -> Int
    let action: (RemoteButton) -> Void

    @ScaledMetric var buttonWidth = globalButtonWidth
    @ScaledMetric var buttonHeight = globalButtonHeight
    @ScaledMetric var buttonSpacing = globalButtonSpacing

    var body: some View {
        HStack(spacing: buttonSpacing * 2) {
            Button(action: { action(.back) }, label: {
                Label("Back", systemImage: "arrow.left")
                    .frame(width: buttonWidth, height: buttonHeight)
            })
            #if !os(tvOS) && !os(watchOS)
            .customKeyboardShortcut(.back)
            #endif
            #if os(macOS)
            .buttonStyle(.borderedProminent)
            .tint(Color.secondary)
            #endif
            #if !os(visionOS)
            .sensoryFeedback(.impact, trigger: pressCounter(.back))
            #endif
            .symbolEffect(.bounce, value: pressCounter(.back))

            Button("Power On/Off", systemImage: "power", role: .destructive, action: { action(.power) })
                .font(.title)
                .foregroundStyle(.red)
                .buttonStyle(.plain)
            #if !os(visionOS)
                .sensoryFeedback(.impact, trigger: pressCounter(.power))
            #endif
                .symbolEffect(.bounce, value: pressCounter(.power))
            #if !os(tvOS) && !os(watchOS)
                .customKeyboardShortcut(.power)
            #endif

            Button(action: { action(.home) }, label: {
                Label("Home", systemImage: "house")
                    .frame(width: buttonWidth, height: buttonHeight)
            })
            #if os(macOS)
            .buttonStyle(.borderedProminent)
            .tint(Color.secondary)
            #endif
            #if !os(tvOS) && !os(watchOS)
            .customKeyboardShortcut(.home)
            #endif
            #if !os(visionOS)
            .sensoryFeedback(.impact, trigger: pressCounter(.home))
            #endif
            .symbolEffect(.bounce, value: pressCounter(.home))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
