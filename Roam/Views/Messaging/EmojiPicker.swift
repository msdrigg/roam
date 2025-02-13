#if os(macOS)
import SwiftUI
import AppKit

struct EmojiPicker: View {
    var body: some View {
        Button(action: {
            NSApp.orderFrontCharacterPalette(nil)
        }, label: {
            Image(systemName: "face.smiling")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(Color.gray)
        })
        .buttonStyle(PlainButtonStyle())
    }
}

#if DEBUG
#Preview("Emoji Picker") {
    EmojiPicker()
        .padding()
}
#endif
#endif
