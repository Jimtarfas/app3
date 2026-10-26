import Foundation
import StoreKit

@MainActor @Observable
final class Store {
    static let yearlyID = "com.faxandscan.app.yearly"
    static let weeklyID = "com.faxandscan.app.weekly"
    static let productIDs = [yearlyID, weeklyID]

    private(set) var products: [Product] = []
    private(set) var activeTransaction: Transaction?
    /// The signed transaction the backend verifies before it sends a fax.
    private(set) var activeJWS: String?
    private(set) var isEligibleForTrial = false
    private(set) var loadError: String?
    private(set) var isLoading = false

    var isSubscribed: Bool { activeTransaction != nil }

    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = fetched.sorted { $0.id == Self.yearlyID && $1.id != Self.yearlyID }
            loadError = fetched.isEmpty ? "Subscriptions are not available right now." : nil
        } catch {
            loadError = "Couldn't load subscriptions. Check your connection and try again."
        }
        if let yearly = product(Self.yearlyID), let subscription = yearly.subscription {
            isEligibleForTrial = await subscription.isEligibleForIntroOffer
        }
        await refreshEntitlements()
    }

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    func refreshEntitlements() async {
        var best: (Transaction, String)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  (transaction.expirationDate ?? .distantFuture) > .now else { continue }
            if best == nil || (transaction.expirationDate ?? .distantPast) > (best!.0.expirationDate ?? .distantPast) {
                best = (transaction, result.jwsRepresentation)
            }
        }
        activeTransaction = best?.0
        activeJWS = best?.1
    }

    /// Returns true when the purchase went through.
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase(options: [.appAccountToken(DeviceID.current)])
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw StoreError.unverified
            }
            await transaction.finish()
            await refreshEntitlements()
            return true
        case .pending:
            throw StoreError.pending
        case .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    var planName: String {
        switch activeTransaction?.productID {
        case Self.yearlyID: "Yearly"
        case Self.weeklyID: "Weekly"
        default: "None"
        }
    }

    enum StoreError: LocalizedError {
        case unverified, pending
        var errorDescription: String? {
            switch self {
            case .unverified: "The App Store couldn't verify this purchase."
            case .pending: "Your purchase is waiting for approval. It will unlock automatically once approved."
            }
        }
    }
}

extension Product {
    /// "$39.99/year" or "$4.99/week"
    var pricePerPeriod: String {
        guard let period = subscription?.subscriptionPeriod else { return displayPrice }
        return "\(displayPrice)/\(period.unitName)"
    }

    /// The yearly price spread over 52 weeks, for comparison with the weekly plan.
    var weeklyEquivalent: String? {
        guard let period = subscription?.subscriptionPeriod, period.unit == .year, period.value == 1 else { return nil }
        let perWeek = price / 52
        return perWeek.formatted(priceFormatStyle) + "/week"
    }

    var trialDays: Int? {
        guard let offer = subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        default: return nil
        }
    }
}

extension Product.SubscriptionPeriod {
    var unitName: String {
        // StoreKit can report a weekly plan as seven days.
        if unit == .day && value == 7 { return "week" }
        let base: String
        switch unit {
        case .day: base = "day"
        case .week: base = "week"
        case .month: base = "month"
        case .year: base = "year"
        @unknown default: base = "period"
        }
        return value == 1 ? base : "\(value) \(base)s"
    }
}
