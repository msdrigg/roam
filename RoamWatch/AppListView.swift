import Foundation
import os.log
import SwiftUI

struct AppListView: View {
    private nonisolated static let logger = Logger(
        subsystem: getLogSubsystem(),
        category: String(describing: AppListView.self)
    )

    let device: DeviceAppEntity?
    let apps: [AppLink]
    let onClick: ((AppLink) -> Void)?

    init(device: DeviceAppEntity, apps: [AppLink], onClick: ((AppLink) -> Void)? = nil) {
        self.device = device
        self.apps = apps
        self.onClick = onClick
    }

    @State var appClicks: [String: Int] = [:]
    func appPressCount(_ app: String) -> Int {
        appClicks[app] ?? 0
    }

    func incrementAppPressCount(_ app: String) {
        appClicks[app] = (appClicks[app] ?? 0) + 1
    }

    var body: some View {
        List {
            ForEach(apps) { app in
                Button(action: {
                    incrementAppPressCount(app.id)
                    Task {
                        onClick?(app)
                        do {
                            try await launchApp(app: app.toAppEntity(), device: device)
                        } catch {
                            Self.logger.error("Error opening app \(app.id, privacy: .public): \(error, privacy: .public)")
                        }
                    }
                }, label: {
                    Label {
                        Text(app.name)
                    } icon: {
                        DataImage(from: app.icon, fallback: "questionmark.app")
                            .resizable().aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .frame(width: 32, height: 32)
                            .shadow(radius: 4)
                    }
                    .labelStyle(AppIconLabelStyle())
                })
                .sensoryFeedback(.impact, trigger: appPressCount(app.id))
            }
            if apps.isEmpty {
                Text("No apps", comment: "Text indicator that there are no apps available")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AppIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 8) {
            configuration.icon
            configuration.title
        }
    }
}
