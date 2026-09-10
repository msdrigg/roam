import Foundation
import StoreKit
// `PurchaseAction` comes from the StoreKit ⨯ SwiftUI cross-import overlay, so
// both modules have to be imported here for the type to resolve.
import SwiftUI

/// The four tip tiers, in ascending price order.
///
/// Non-consumable rather than consumable: guideline 3.1.1 requires a restore
/// mechanism, and `Transaction.currentEntitlements` covers the whole account.
/// Every tier unlocks the same thing.
enum TipTier: String, CaseIterable, Identifiable, Sendable {
    case coffee = "com.msdrigg.roam.tip.coffee"
    case latte = "com.msdrigg.roam.tip.latte"
    case lunch = "com.msdrigg.roam.tip.lunch"
    case dinner = "com.msdrigg.roam.tip.dinner"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .coffee: "☕️"
        case .latte: "🥛"
        case .lunch: "🥪"
        case .dinner: "🍝"
        }
    }

    var displayName: String {
        switch self {
        case .coffee: String(localized: "Black Coffee", comment: "Name of the smallest tip tier")
        case .latte: String(localized: "Latte", comment: "Name of the second tip tier")
        case .lunch: String(localized: "Lunch", comment: "Name of the third tip tier")
        case .dinner: String(localized: "Dinner", comment: "Name of the largest tip tier")
        }
    }

    var placeholderPrice: String {
        switch self {
        case .coffee: "$3.00"
        case .latte: "$5.00"
        case .lunch: "$10.00"
        case .dinner: "$20.00"
        }
    }
}

@Observable @MainActor
final class TipStore {
    static let shared = TipStore()

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoadingProducts: Bool = false
    private(set) var isRestoring: Bool = false

    var purchaseError: Error?

    private(set) var isDeveloperUnlocked: Bool

    private var updateListener: Task<Void, Never>?

    private init() {
        isDeveloperUnlocked = UserDefaults.standard.bool(forKey: UserDefaultKeys.developerCosmeticsUnlock)

        Self.grandfatherExistingUsersIfNeeded()

        updateListener = Task { [weak self] in
            // `Transaction.updates` carries purchases made outside this
            // process: Ask to Buy approvals, other devices, and revocations.
            for await update in Transaction.updates {
                guard let self else { return }
                if case let .verified(transaction) = update {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }


    // MARK: - Entitlement

    var hasTipped: Bool {
        !purchasedProductIDs.isEmpty || isGrandfathered || isDeveloperUnlocked
    }

    var isGrandfathered: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultKeys.cosmeticsGrandfathered)
    }

    /// Runs once per install. If the user had already set a custom accent color
    /// back when it was free, grant the unlock permanently - taking away
    /// something someone was actively using is not a trade worth making.
    private static func grandfatherExistingUsersIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: UserDefaultKeys.didEvaluateCosmeticsGrandfathering) else {
            return
        }
        defaults.set(true, forKey: UserDefaultKeys.didEvaluateCosmeticsGrandfathering)

        if defaults.object(forKey: UserDefaultKeys.customAccentColor) != nil {
            Log.data.notice("Grandfathering cosmetics for pre-existing custom accent color")
            defaults.set(true, forKey: UserDefaultKeys.cosmeticsGrandfathered)
        }
    }

    // MARK: - Developer unlock

    /// Sent from support into a user's chat to grant the tip extras without a
    /// purchase. Versioned, so minting `_v2` retires this one.
    static let developerUnlockCode = ":auto_unlock_iap_v1:"

    static func isDeveloperUnlockCode(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == developerUnlockCode
    }

    /// Grants the extras permanently on this device. Local only: not an
    /// entitlement, so it never touches StoreKit. Returns true only on the call
    /// that flips the unlock, so callers celebrate once.
    @discardableResult
    func redeemDeveloperUnlock() -> Bool {
        guard !isDeveloperUnlocked else { return false }

        isDeveloperUnlocked = true
        UserDefaults.standard.set(true, forKey: UserDefaultKeys.developerCosmeticsUnlock)
        Log.userInteraction.notice("Developer unlock code redeemed")
        return true
    }

    // MARK: - Loading

    /// Prices never change under us mid-session, so the catalog loads once.
    /// Entitlements are the part that goes stale, and they refresh separately.
    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loaded = try await Product.products(for: TipTier.allCases.map(\.rawValue))
            products = loaded.sorted { $0.price < $1.price }
            Log.backend.notice("Loaded \(self.products.count, privacy: .public) tip products")
        } catch {
            Log.backend.error("Failed loading tip products \(error, privacy: .public)")
        }
    }

    func refreshEntitlements() async {
        var owned: Set<String> = []
        for await entitlement in Transaction.currentEntitlements {
            guard case let .verified(transaction) = entitlement else { continue }
            guard transaction.revocationDate == nil else { continue }
            owned.insert(transaction.productID)
        }
        purchasedProductIDs = owned
        UserDefaults.standard.set(Date(), forKey: UserDefaultKeys.dateOfLastEntitlementRefresh)
        Log.backend.notice("Tip entitlements refreshed count=\(owned.count, privacy: .public)")
    }

    private static let entitlementRefreshInterval: TimeInterval = 60 * 60 * 24

    /// For screens that only need to know whether the tip extras are unlocked -
    /// Settings, mainly. Reading `currentEntitlements` is local and cheap, but
    /// Settings gets opened constantly and a purchase made elsewhere already
    /// arrives live over `Transaction.updates`, so once a day per install is
    /// enough to catch the case where the app wasn't running when it happened.
    func refreshEntitlementsIfStale() async {
        let lastRefresh = UserDefaults.standard
            .object(forKey: UserDefaultKeys.dateOfLastEntitlementRefresh) as? Date

        // `abs` so a clock that jumped forward and back doesn't wedge the
        // refresh off until the stored date catches up again.
        if let lastRefresh, abs(lastRefresh.timeIntervalSinceNow) < Self.entitlementRefreshInterval {
            return
        }

        await refreshEntitlements()
    }

    func product(for tier: TipTier) -> Product? {
        products.first { $0.id == tier.rawValue }
    }

    // MARK: - Purchasing

    /// Buys through SwiftUI's `PurchaseAction` rather than `Product.purchase()`,
    /// which visionOS does not offer. `PurchaseAction` resolves the scene from
    /// the environment, keeping one code path across platforms.
    func purchase(_ product: Product, using purchase: PurchaseAction) async {
        do {
            let result = try await purchase(product)

            switch result {
            case let .success(verification):
                guard case let .verified(transaction) = verification else {
                    Log.backend.error("Tip purchase failed StoreKit verification")
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
                Log.userInteraction.notice("Tip purchased \(product.id, privacy: .public)")

            case .userCancelled:
                Log.userInteraction.notice("Tip purchase cancelled by user")

            case .pending:
                Log.userInteraction.notice("Tip purchase pending approval")

            @unknown default:
                break
            }
        } catch {
            Log.backend.error("Tip purchase failed \(error, privacy: .public)")
            purchaseError = error
        }
    }

    func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            Log.userInteraction.notice("Restored purchases")
        } catch {
            Log.backend.error("Restoring purchases failed \(error, privacy: .public)")
            purchaseError = error
        }
    }
}
