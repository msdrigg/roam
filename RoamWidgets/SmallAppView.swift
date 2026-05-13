import Foundation
import SwiftUI

#if !os(watchOS)
struct SmallAppView: View {
    let device: Device?
    let apps: [ AppLink]
    let appIcons: [String: Image]
    let rows: Int

    var appRows: [[ AppLink?]] {
        if device == nil, apps.isEmpty {
            if rows == 1 {
                return [[nil, nil]]
            } else {
                return [[nil, nil], [nil, nil]]
            }
        }
        let cappedApps = Array(apps.prefix(4))
        let rowCount = rows
        var rowSize = cappedApps.count / rowCount
        if rowSize == 0 {
            rowSize = 1
        }
        var rows: [[ AppLink?]] = []

        for i in stride(from: 0, to: cappedApps.count, by: rowSize) {
            let endIndex = min(i + rowCount, cappedApps.count)
            let row = Array(cappedApps[i ..< endIndex])
            rows.append(row + [nil, nil][..<(rowCount - row.count)])
        }

        return rows
    }

    var body: some View {
        Grid {
            ForEach(appRows.indices, id: \.self) { index in
                let row = appRows[index]
                GridRow {
                    ForEach(row.indices, id: \.self) { rowIndex in
                        if let app = row[rowIndex] {
                            Button(intent: LaunchAppIntent(app, device: device)) {
                                VStack(spacing: 0) {
                                    if let icon = appIcons[app.id] {
                                        icon
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .shadow(radius: 4)
                                    } else {
                                        Image(systemName: "questionmark.app.fill")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 0))
                                            .shadow(radius: 4)
                                    }

                                    Text(app.name)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(width: 60)
                                        .frame(height: 10)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 2)
                                }
                            }
                            .buttonStyle(.plain)
                        } else if device != nil {
                            Spacer()
                        } else {
                            VStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.5))
                                    .shadow(radius: 4)

                                Text("App", comment: "Placeholder label for an app")
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(width: 60)
                                    .frame(height: 10)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.all, 4)
        .fontDesign(.rounded)
        .font(.body.bold())
        .buttonBorderShape(.roundedRectangle)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.iconOnly)
        .customAccentColorTint()
    }
}
#else
import WidgetKit

struct SmallAppView: View {
    let device: Device?
    let apps: [ AppLink]
    let appIcons: [String: Image]
    let rows: Int

    var appRow: [ AppLink?] {
        var paddedArray = apps.prefix(3).map { Optional($0) }
        while paddedArray.count < 3 {
            paddedArray.append(nil)
        }
        return paddedArray
    }

    var body: some View {
        AccessoryWidgetGroup(String(localized: "Roku Apps", comment: "Label on a widget for interactions with my application"), systemImage: "app.dashed") {
            ForEach(appRow.indices, id: \.self) { rowIndex in
                if let app = appRow[rowIndex] {
                    Button(intent: LaunchAppIntent(app, device: device)) {
                        FallibleImage(from: app.iconURL, fallback: "questionmark.app.fill", maxSize: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(radius: 4)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                } else if device != nil {
                    Spacer()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.5))
                        .shadow(radius: 4)
                }
            }
        }
        .padding(.all, 4)
        .fontDesign(.rounded)
        .font(.body.bold())
        .accessoryWidgetGroupStyle(.roundedSquare)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .customAccentColorTint()
    }
}
#endif

#if DEBUG
#Preview("TwoRowsSmallAppView") {
    SmallAppView(device: nil, apps: [], appIcons: [:], rows: 2)
        .frame(width: 200, height: 200)
        .padding(.all, 12)
}

#Preview("OneRowSmallAppView") {
    SmallAppView(device: nil, apps: [], appIcons: [:], rows: 1)
        .frame(width: 200, height: 100)
        .padding(.all, 12)
}
#endif
