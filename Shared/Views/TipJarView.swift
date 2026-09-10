import StoreKit
import SwiftUI

#if os(iOS)
    import UIKit
#endif

// The tip jar is not offered on watchOS: the watch app is a companion surface
// with no room for a store, and `formStyle(.grouped)` isn't available there.
#if !os(watchOS)

/// The alternate app icons unlocked by tipping.
///
/// `assetName` must match the `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
/// entries; `nil` means the default icon.
enum AppIconOption: String, CaseIterable, Identifiable {
    case standard
    case pride = "AppIconPride"
    case retro = "AppIconRetro"
    case midnight = "AppIconMidnight"

    var id: String { rawValue }

    /// `UIApplication` wants `nil` rather than a name for the primary icon.
    var alternateIconName: String? {
        self == .standard ? nil : rawValue
    }

    /// Preview swatch image. Separate from the app-icon sets, which are not
    /// addressable as `Image(...)` at runtime.
    var previewAssetName: String {
        self == .standard ? "AppIconPreview" : "\(rawValue)Preview"
    }

    var displayName: String {
        switch self {
        case .standard: String(localized: "Default", comment: "Name of the default app icon")
        case .pride: String(localized: "Pride", comment: "Name of the rainbow app icon")
        case .retro: String(localized: "Retro", comment: "Name of the retro TV test-pattern app icon")
        case .midnight: String(localized: "Midnight", comment: "Name of the dark monochrome app icon")
        }
    }
}

/// The trailing marker on a settings row that tipping unlocks. A tinted
/// capsule at footnote size, so it reads as an offer rather than fine print.
struct TipToUnlockBadge: View {
    @AppStorageColor(UserDefaultKeys.customAccentColor) private var accentColor: Color = Color("AccentColor")

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .imageScale(.small)
            Text("Tip to unlock", comment: "Label on a locked cosmetic setting")
                .fontWeight(.semibold)
        }
        .font(.footnote)
        .foregroundStyle(accentColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(accentColor.opacity(0.15)))
        // Never truncate to "Tip to unl…" - the row title wraps first.
        .fixedSize()
    }
}

struct TipJarView: View {
    @State private var store = TipStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Roam is free and open source, with no ads.",
                        comment: "Headline at the top of the tip jar"
                    )
                    .font(.headline)

                    Text(
                        "If it's been useful, you can leave a tip. Any tip unlocks custom accent colors and the alternate app icons. Every tier unlocks the same things.",
                        comment: "Explanation of what tipping does"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(TipTier.allCases) { tier in
                    TipTierRow(tier: tier, store: store)
                }
            } header: {
                Text("Leave a tip", comment: "Section header above the list of tip tiers")
            } footer: {
                if store.hasTipped {
                    Label(
                        String(
                            localized: "Thanks. Your extras are unlocked.",
                            comment: "Confirmation shown once the user has tipped"
                        ),
                        systemImage: "checkmark.seal.fill"
                    )
                    .foregroundStyle(.green)
                }
            }

            Section {
                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    HStack {
                        Text("Restore Purchases", comment: "Button to restore previous in-app purchases")
                        Spacer()
                        if store.isRestoring {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isRestoring)
            } footer: {
                Text(
                    "Already tipped on another device? Restore to unlock the extras here.",
                    comment: "Explanation of the restore purchases button"
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Tip Jar", comment: "Navigation title of the tip jar page"))
        .task {
            await store.loadProducts()
            // Unconditional: opening the tip jar is exactly when a purchase
            // made on another device needs to already be reflected.
            await store.refreshEntitlements()
        }
        .alertingError(message: "Purchase Failed", error: $store.purchaseError)
        .customAccentColorTint()
    }
}

private struct TipTierRow: View {
    let tier: TipTier
    let store: TipStore
    @Environment(\.purchase) private var purchase

    private var product: Product? {
        store.product(for: tier)
    }

    private var isPurchased: Bool {
        store.purchasedProductIDs.contains(tier.rawValue)
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(tier.emoji)
                .font(.system(size: 24))
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.secondary.opacity(0.12)))

            Text(tier.displayName)
                .font(.body.weight(.medium))
                // Long tier names in other locales wrap instead of shoving the
                // price button off the row.
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            price
        }
        .padding(.vertical, 6)
    }

    /// `.fixedSize()` throughout: a price is short, and letting the button
    /// shrink to "$10..." to satisfy the row is never the right trade.
    @ViewBuilder
    private var price: some View {
        Group {
            if isPurchased {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            } else if let product {
                Button(product.displayPrice) {
                    Task { await store.purchase(product, using: purchase) }
                }
                .buttonStyle(.glassIfSupported(isProminent: true))
            } else if inScreenshotTestingContext() {
                // Screenshot runs must be deterministic, and the redacted pill
                // below hides the purchase affordance the reviewer needs to
                // see. Amounts match App Store Connect; nothing is purchasable.
                Button(tier.placeholderPrice) {}
                    .buttonStyle(.glassIfSupported(isProminent: true))
            } else {
                // Products still loading (or unavailable, e.g. no network).
                Text(tier.placeholderPrice)
                    .foregroundStyle(.secondary)
                    .redacted(reason: .placeholder)
            }
        }
        .font(.callout.weight(.semibold))
        .controlSize(.large)
        .fixedSize()
    }
}

#if os(iOS)
    /// Alternate app icons are an iOS/iPadOS affordance - `setAlternateIconName`
    /// has no macOS, watchOS or visionOS equivalent.
    struct AppIconPickerView: View {
        @State private var store = TipStore.shared
        @AppStorage(UserDefaultKeys.alternateAppIcon) private var selectedIcon: String = AppIconOption.standard
            .rawValue
        @State private var iconError: Error?

        private let columns = [GridItem(.adaptive(minimum: 72), spacing: 16)]

        var body: some View {
            Form {
                Section {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(AppIconOption.allCases) { option in
                            Button {
                                select(option)
                            } label: {
                                VStack(spacing: 6) {
                                    Image(option.previewAssetName)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                .strokeBorder(
                                                    selectedIcon == option.rawValue ? Color.accentColor : .clear,
                                                    lineWidth: 3
                                                )
                                        }
                                    Text(option.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                } footer: {
                    Text(
                        "Choose the icon shown on your Home Screen.",
                        comment: "Explanation under the alternate app icon picker"
                    )
                }
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: "App Icon", comment: "Navigation title of the app icon picker"))
            .alertingError(message: "Couldn't Change Icon", error: $iconError)
            .customAccentColorTint()
        }

        private func select(_ option: AppIconOption) {
            guard UIApplication.shared.supportsAlternateIcons else { return }

            UIApplication.shared.setAlternateIconName(option.alternateIconName) { error in
                Task { @MainActor in
                    if let error {
                        Log.userInteraction.error("Failed setting alternate icon \(error, privacy: .public)")
                        iconError = error
                    } else {
                        selectedIcon = option.rawValue
                        Log.userInteraction.notice("Alternate icon set to \(option.rawValue, privacy: .public)")
                    }
                }
            }
        }
    }
#endif

#endif
