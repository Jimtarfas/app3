import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @AppStorage(SenderKeys.name) private var name = ""
    @AppStorage(SenderKeys.company) private var company = ""
    @AppStorage(SenderKeys.phone) private var phone = ""
    @AppStorage(SenderKeys.fax) private var fax = ""
    @AppStorage(SenderKeys.email) private var email = ""
    @State private var usage: FaxAPI.Usage?
    @State private var showManage = false
    @State private var isRestoring = false
    @State private var alert: AlertItem?

    var body: some View {
        NavigationStack {
            Form {
                subscriptionSection

                Section {
                    TextField("Name", text: $name).textContentType(.name)
                    TextField("Company", text: $company).textContentType(.organizationName)
                    TextField("Phone", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                    TextField("Fax", text: $fax).keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Your Details")
                } footer: {
                    Text("Used to fill in the sender on your cover sheets. Stored only on this iPhone.")
                }

                Section("Help & Legal") {
                    Link(destination: AppLinks.support) { Label("Help & Support", systemImage: "questionmark.circle") }
                    Link(destination: URL(string: "mailto:\(AppLinks.supportEmail)?subject=Fax%20%26%20Scan%20Support")!) {
                        Label("Contact Us", systemImage: "envelope")
                    }
                    Link(destination: AppLinks.privacy) { Label("Privacy Policy", systemImage: "hand.raised") }
                    Link(destination: AppLinks.terms) { Label("Terms of Use", systemImage: "doc.plaintext") }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.versionString)
                }
            }
            .navigationTitle("Settings")
            .manageSubscriptionsSheet(isPresented: $showManage)
            .task(id: store.activeJWS) { await loadUsage() }
            .alert(item: $alert) { Alert(title: Text($0.title), message: Text($0.message)) }
        }
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        Section {
            if let transaction = store.activeTransaction {
                LabeledContent("Plan", value: "Fax & Scan Pro · \(store.planName)")
                if let expires = transaction.expirationDate {
                    LabeledContent("Renews or ends", value: expires.formatted(date: .abbreviated, time: .omitted))
                }
                if let usage {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Pages this week", value: "\(usage.pagesUsed) of \(usage.pageLimit)")
                        ProgressView(value: Double(min(usage.pagesUsed, usage.pageLimit)), total: Double(max(usage.pageLimit, 1)))
                    }
                }
                Button("Manage Subscription") { showManage = true }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fax & Scan Pro")
                        .font(.headline)
                    Text("Send faxes to US and Canada numbers, up to \(Theme.weeklyPageLimit) pages a week. Scanning and cover sheets are free.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                Button("See Plans") { router.showPaywall = true }
                    .fontWeight(.semibold)
            }
            Button {
                Task { await restore() }
            } label: {
                HStack {
                    Text("Restore Purchases")
                    if isRestoring { Spacer(); ProgressView() }
                }
            }
            .disabled(isRestoring)
        } header: {
            Text("Subscription")
        }
    }

    private func loadUsage() async {
        guard let jws = store.activeJWS else { usage = nil; return }
        usage = try? await FaxAPI().usage(transaction: jws)
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await store.restore()
            alert = store.isSubscribed
                ? AlertItem(title: "Purchases Restored", message: "Your Fax & Scan Pro subscription is active.")
                : AlertItem(title: "No Subscription Found", message: "There's no active subscription for this Apple Account.")
        } catch {
            alert = AlertItem(title: "Restore Failed", message: error.friendlyMessage)
        }
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
