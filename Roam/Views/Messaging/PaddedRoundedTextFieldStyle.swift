#if os(visionOS)
import SwiftUI

struct PaddedRoundedTextFieldStyle: TextFieldStyle {
    // swiftlint:disable:next identifier_name
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .foregroundColor(.secondary)
            .allowsHitTesting(true)
            .hoverEffectDisabled()
            .background(
                Rectangle()
                    .fill(Color(.systemGray6).opacity(0.5))
                    .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
                    .shadow(color: Color.white.opacity(0.3), radius: 2, x: 0, y: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .focusable()
            .hoverEffect(.highlight)
    }
}

#if DEBUG
#Preview(
    "Padded Rounded Style",
    traits: .fixedLayout(width: 400, height: 300)
) {
    TextField("Test textfield", text: Binding(
        get: {"hi dude"},
        set: {_ in }
    ))
        .textFieldStyle(PaddedRoundedTextFieldStyle())
        .padding()
}
#endif
#endif
