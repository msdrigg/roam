//
//  CenterController.swift
//  Roam
//
//  Created by Scott Driggers on 10/20/23.
//

import Foundation
import SwiftUI

struct CenterController: View {
    let pressCounter: (RemoteButton) -> Int
    let action: (RemoteButton) -> Void
    var usesNativeGlassButtons = false
    @State private var pressCount: [RemoteButton: Int] = [:]

    @ScaledMetric var buttonWidth = globalButtonWidth
    @ScaledMetric var buttonHeight = globalButtonHeight
    @ScaledMetric var buttonSpacing = globalButtonSpacing

    @Environment(\.layoutDirection) var layoutDirection

    var body: some View {
        let buttons: [(String?, RemoteButton, String, CustomKeyboardShortcut.Key)?] = [
            nil, ("chevron.up", .up, "Up", .up), nil,
            ("chevron.left", .left, "Left", .left),
            (nil, .select, String(localized: "Ok", comment: "Center button on a remote. Meaning select/enter. Must be 3 characters or less, or a symbol if not possible"), .ok),
            ("chevron.right", .right, "Right", .right),
            nil, ("chevron.down", .down, "Down", .down), nil,
        ]
        return VStack(alignment: .center) {
            Grid(horizontalSpacing: buttonSpacing / 5, verticalSpacing: buttonSpacing / 5) {
                ForEach(0 ..< 3) { row in
                    GridRow {
                        ForEach(0 ..< 3) { col in
                            if let button = buttons[row * 3 + col] {
                                Button(action: { action(button.1) }, label: {
                                    if let systemImage = button.0 {
                                        Label(button.2, systemImage: systemImage)
                                            .frame(width: buttonWidth, height: buttonHeight)
                                            .symbolEffect(.bounce, value: pressCounter(button.1))
                                    } else {
                                        Label(button.2, systemImage: "checkmark")
                                            .labelStyle(.titleOnly)
                                            .frame(width: buttonWidth, height: buttonHeight)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                            .scaleEffect((pressCount[button.1] ?? 0) != pressCounter(button.1) ? 1.15 :
                                                1.0)
                                            .animation(
                                                .interpolatingSpring(stiffness: 80, damping: 5),
                                                value: (pressCount[button.1] ?? 0) != pressCounter(button.1)
                                            )
                                            .onChange(of: pressCounter(button.1)) { _, newValue in
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                    pressCount[button.1] = newValue
                                                }
                                            }
                                            .environment(\.layoutDirection, layoutDirection)
                                    }
                                })
                                .accessibilityIdentifier(button.2)
                                #if !os(watchOS)
                                .modifier(CustomKeyboardShortcutModifier(title: button.3))
                                #endif
                                #if !os(visionOS)
                                .sensoryFeedback(.impact, trigger: pressCounter(button.1))
                                #endif
                            } else {
                                Spacer().frame(maxWidth: buttonWidth, maxHeight: buttonHeight)
                            }
                        }
                    }
                }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .fixedSize()
        .id("controllerGrid")
    }
}
