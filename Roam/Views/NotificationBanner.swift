import SwiftUI
import Foundation

struct NotificationBanner: View {
    let message: LocalizedStringResource
    let level: Level
    let onClick: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    init(message: LocalizedStringResource, onClick: (() -> Void)? = nil, level: Level = .error) {
        self.message = message
        self.onClick = onClick
        self.level = level
    }

    var body: some View {
        if onClick != nil {
            Button(action: { onClick?() }, label: {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(
                        colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(backgroundColor)
                    .cornerRadius(3.0)
                    .cornerRadius(5)
            })
            .buttonStyle(.plain)
            #if !os(tvOS)
                .controlSize(.small)
            #endif
        } else {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(
                    colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8)
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(backgroundColor)
                .cornerRadius(3.0)
                .cornerRadius(5)
        }
    }

    private var backgroundColor: Color {
        switch level {
        case .info:
            Color.accentColor.opacity(0.3)
        case .warning:
            Color.orange.opacity(0.3)
        case .error:
            Color.red.opacity(0.3)
        }
    }

    enum Level {
        case warning, error, info
    }
}

#if DEBUG
#Preview("Clickable") {
    NotificationBanner(message: "Message (clickable)", onClick: {})
        .padding()
}

#Preview("Not clickable") {
    NotificationBanner(message: "Message (not clickable)")
        .padding()
}

#Preview("Info") {
    NotificationBanner(message: "Message (not clickable)", level: .info)
        .padding()
}
#endif
