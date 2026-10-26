import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = Store.yearlyID
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var alert: AlertItem?

    private var plans: [PlanOption] {
        #if DEBUG
        if store.products.isEmpty && DemoMode.screen != nil { return PlanOption.demo }
        #endif
        return store.products.map { PlanOption(product: $0) }
    }

    private var selected: PlanOption? { plans.first { $0.id == selectedID } }

    private var trialEligible: Bool {
        #if DEBUG
        if store.products.isEmpty && DemoMode.screen != nil { return true }
        #endif
        return store.isEligibleForTrial
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                benefits
                if plans.isEmpty {
                    productsUnavailable
                } else {
                    VStack(spacing: 12) {
                        ForEach(plans) { plan in
                            PlanCard(plan: plan,
                                     isSelected: plan.id == selectedID,
                                     showsTrial: plan.id == Store.yearlyID && trialEligible && plan.trialDays != nil)
                                .onTapGesture { selectedID = plan.id }
                        }
                    }
                }
                purchaseSection
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.thinMaterial, in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Close")
        }
        .alert(item: $alert) { Alert(title: Text($0.title), message: Text($0.message)) }
        .onChange(of: store.isSubscribed) { _, subscribed in
            if subscribed { dismiss() }
        }
        .task {
            if store.products.isEmpty { await store.load() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Theme.accent.gradient)
                    .frame(width: 84, height: 84)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 28)
            Text("Fax & Scan Pro")
                .font(.largeTitle.bold())
            Text("Send faxes right from your iPhone. No fax machine or phone line needed.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            Benefit(symbol: "paperplane", text: "Send faxes to any US or Canada fax number")
            Benefit(symbol: "doc.on.doc", text: "Up to \(Theme.weeklyPageLimit) pages every week")
            Benefit(symbol: "checkmark.seal", text: "Delivery confirmation and fax history")
            Benefit(symbol: "doc.viewfinder", text: "Scanner and cover sheets are always free")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var productsUnavailable: some View {
        VStack(spacing: 10) {
            if store.isLoading {
                ProgressView()
            } else {
                Text(store.loadError ?? "Subscriptions are not available right now.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await store.load() } }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var purchaseSection: some View {
        VStack(spacing: 10) {
            if let selected {
                Text(billingSummary(for: selected))
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await purchase() }
            } label: {
                Group {
                    if isPurchasing { ProgressView().tint(.white) } else { Text(ctaTitle).font(.headline) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selected == nil || isPurchasing)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                Button(isRestoring ? "Restoring…" : "Restore Purchases") { Task { await restore() } }
                    .disabled(isRestoring)
                Link("Terms of Use", destination: AppLinks.terms)
                Link("Privacy Policy", destination: AppLinks.privacy)
            }
            .font(.footnote.weight(.medium))

            Text("Payment is charged to your Apple Account when you confirm the purchase. The subscription renews automatically unless you cancel it at least 24 hours before the end of the current period, and your account is charged for renewal within 24 hours before the period ends. If you start a free trial, any unused part of it ends when you buy a subscription. You can manage or cancel your subscription in your App Store account settings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var ctaTitle: String {
        guard let selected else { return "Continue" }
        if selected.id == Store.yearlyID, trialEligible, let days = selected.trialDays {
            return "Start \(days)-Day Free Trial"
        }
        return "Subscribe for \(selected.pricePerPeriod)"
    }

    private func billingSummary(for plan: PlanOption) -> String {
        if plan.id == Store.yearlyID, trialEligible, let days = plan.trialDays {
            return "Free for \(days) days, then \(plan.displayPrice) per \(plan.periodName). Cancel anytime."
        }
        return "\(plan.displayPrice) per \(plan.periodName), renews automatically. Cancel anytime."
    }

    private func purchase() async {
        guard let selected = selected?.product else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            if try await store.purchase(selected) { dismiss() }
        } catch {
            alert = AlertItem(title: "Purchase Not Completed", message: error.friendlyMessage)
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await store.restore()
            if !store.isSubscribed {
                alert = AlertItem(title: "No Subscription Found", message: "There's no active subscription for this Apple Account.")
            }
        } catch {
            alert = AlertItem(title: "Restore Failed", message: error.friendlyMessage)
        }
    }
}

private struct Benefit: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

/// What the paywall shows for one plan, built from a StoreKit product.
struct PlanOption: Identifiable {
    let id: String
    let title: String
    let displayPrice: String
    let periodName: String
    let weeklyEquivalent: String?
    let trialDays: Int?
    let product: Product?

    var pricePerPeriod: String { "\(displayPrice)/\(periodName)" }

    init(product: Product) {
        id = product.id
        title = product.id == Store.yearlyID ? "Yearly" : "Weekly"
        displayPrice = product.displayPrice
        periodName = product.subscription?.subscriptionPeriod.unitName ?? "period"
        weeklyEquivalent = product.weeklyEquivalent
        trialDays = product.trialDays
        self.product = product
    }

    init(id: String, title: String, displayPrice: String, periodName: String, weeklyEquivalent: String?, trialDays: Int?) {
        self.id = id
        self.title = title
        self.displayPrice = displayPrice
        self.periodName = periodName
        self.weeklyEquivalent = weeklyEquivalent
        self.trialDays = trialDays
        product = nil
    }

    #if DEBUG
    /// Matches the App Store Connect prices, for screenshots taken before the products are live.
    static let demo = [
        PlanOption(id: Store.yearlyID, title: "Yearly", displayPrice: "$39.99", periodName: "year", weeklyEquivalent: "$0.77/week", trialDays: 3),
        PlanOption(id: Store.weeklyID, title: "Weekly", displayPrice: "$4.99", periodName: "week", weeklyEquivalent: nil, trialDays: nil),
    ]
    #endif
}

private struct PlanCard: View {
    let plan: PlanOption
    let isSelected: Bool
    let showsTrial: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(plan.title)
                        .font(.headline)
                    if showsTrial, let days = plan.trialDays {
                        Text("\(days)-day free trial")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.tint.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }
                Text(plan.weeklyEquivalent.map { "Works out to \($0)" } ?? "Billed every week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(plan.pricePerPeriod)
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.separator)), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
