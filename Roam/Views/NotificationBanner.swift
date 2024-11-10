import SwiftUI
import Foundation

struct NotificationBanner: View {
    let message: String
    let level: Level
    let onDismiss: (() -> Void)?
    let onClick: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    init(message: String, onClick: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil, level: Level = .error) {
        self.message = message
        self.onDismiss = onDismiss
        self.level = level
        self.onClick = onClick
    }

    var body: some View {
        if let onClick {
            Button(action: onClick, label: {
                Text(message)
                    .lineLimit(2)
                    .truncationMode(.tail)
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
            .help(message)
        } else {
            HStack(alignment: .top, spacing: 10) {
                Text(message)
#if os(macOS)
                    .lineLimit(2)
                    .truncationMode(.tail)
#endif
                    .font(.subheadline)

                if let onDismiss {
                    Button("Dismiss", systemImage: "x.circle.fill", action: onDismiss)
                        .controlSize(.small)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                }
            }
            .foregroundStyle(
                colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .cornerRadius(3.0)
            .cornerRadius(5)
            .help(message)
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
    NotificationBanner(message: "Message (clickable)", onDismiss: {})
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
