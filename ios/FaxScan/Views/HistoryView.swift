import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \FaxRecord.createdAt, order: .reverse) private var records: [FaxRecord]
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if records.isEmpty {
                    ContentUnavailableView {
                        Label("No Faxes Yet", systemImage: "tray")
                    } description: {
                        Text("Faxes you send appear here with their delivery status.")
                    } actions: {
                        Button("Send a Fax") { router.tab = .send }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(records) { record in
                            NavigationLink(value: record.id) { HistoryRow(record: record) }
                        }
                    }
                    .refreshable { await FaxSender.refresh(records) }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: UUID.self) { id in
                if let record = records.first(where: { $0.id == id }) {
                    FaxDetailView(record: record)
                }
            }
        }
        .task(id: scenePhase) {
            // Poll while something is still on its way.
            while scenePhase == .active && !Task.isCancelled {
                if records.contains(where: { !$0.status.isFinal }) { await FaxSender.refresh(records) }
                try? await Task.sleep(for: .seconds(8))
            }
        }
        .onAppear(perform: openRequestedFax)
        .onChange(of: router.openFaxID) { _, _ in openRequestedFax() }
    }

    private func openRequestedFax() {
        guard let id = router.openFaxID else { return }
        router.openFaxID = nil
        path = [id]
    }
}

private struct HistoryRow: View {
    let record: FaxRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(record.pageCount) \(record.pageCount == 1 ? "page" : "pages") · \(PhoneFormatter.pretty(record.faxNumber))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: record.status)
                Text(record.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FaxDetailView: View {
    @Bindable var record: FaxRecord
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showPreview = false
    @State private var confirmResend = false
    @State private var confirmDelete = false
    @State private var isSending = false
    @State private var alert: AlertItem?

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: record.status.symbol)
                        .font(.system(size: 44))
                        .foregroundStyle(StatusBadge(status: record.status).color)
                        .symbolEffect(.pulse, isActive: !record.status.isFinal)
                    Text(headline)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("Details") {
                if !record.recipientName.isEmpty {
                    LabeledContent("Recipient", value: record.recipientName)
                }
                LabeledContent("Fax number", value: PhoneFormatter.display(record.faxNumber))
                LabeledContent("Pages", value: "\(record.pageCount)")
                LabeledContent("Sent", value: record.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Status", value: record.status.title)
            }

            Section {
                if FileManager.default.fileExists(atPath: record.documentURL.path) {
                    Button { showPreview = true } label: { Label("View Document", systemImage: "doc.richtext") }
                    ShareLink(item: record.documentURL) { Label("Share PDF", systemImage: "square.and.arrow.up") }
                    if record.status.isFinal {
                        Button { startResend() } label: { Label("Send Again", systemImage: "arrow.clockwise") }
                    }
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete from History", systemImage: "trash") }
            }
        }
        .navigationTitle(record.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await FaxSender.refresh([record]) }
        .sheet(isPresented: $showPreview) { PDFPreviewSheet(url: record.documentURL, title: "Document") }
        .confirmationDialog("Send this fax again to \(PhoneFormatter.display(record.faxNumber))?", isPresented: $confirmResend, titleVisibility: .visible) {
            Button("Send Again") { Task { await resend() } }
        }
        .confirmationDialog("Delete this fax from your history? The document on this iPhone is deleted too.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        }
        .alert(item: $alert) { Alert(title: Text($0.title), message: Text($0.message)) }
        .overlay { if isSending { ProgressView("Sending…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
    }

    private var headline: String {
        switch record.status {
        case .queued: "Waiting to send"
        case .sending: "Sending now"
        case .delivered: "Fax delivered"
        case .failed: "Fax not delivered"
        }
    }

    private var detail: String {
        switch record.status {
        case .queued, .sending: "This usually takes about a minute per page. You can leave the app; the status updates when you come back."
        case .delivered: "The receiving fax machine confirmed all \(record.pageCount) \(record.pageCount == 1 ? "page" : "pages")."
        case .failed: (record.failureMessage ?? "The fax couldn't be delivered.") + " Pages from failed faxes don't count toward your weekly allowance."
        }
    }

    private func startResend() {
        guard store.isSubscribed else {
            router.showPaywall = true
            return
        }
        confirmResend = true
    }

    private func resend() async {
        guard let jws = store.activeJWS else { return }
        isSending = true
        defer { isSending = false }
        do {
            let new = try await FaxSender.resend(record, jws: jws, context: context)
            router.openFaxID = new.id
        } catch {
            alert = AlertItem(title: "Fax Not Sent", message: error.friendlyMessage)
        }
    }

    private func delete() {
        try? FileManager.default.removeItem(at: record.documentURL)
        context.delete(record)
        try? context.save()
        dismiss()
    }
}
