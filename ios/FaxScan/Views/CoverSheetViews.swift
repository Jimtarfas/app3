import SwiftUI

/// The fields of a cover sheet, used both when sending and in the free generator tab.
struct CoverSheetEditor: View {
    @Binding var sheet: CoverSheet
    /// When sending, the recipient comes from the Send form unless typed here.
    var showsRecipient: Bool
    var intro: String?

    var body: some View {
        Form {
            if let intro {
                Section {
                    Label(intro, systemImage: "gift")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Recipient") {
                TextField(showsRecipient ? "Name (uses the Send form)" : "Name", text: $sheet.toName)
                TextField("Company", text: $sheet.toCompany)
                TextField(showsRecipient ? "Fax (uses the Send form)" : "Fax number", text: $sheet.toFax)
                    .keyboardType(.phonePad)
                TextField("Phone", text: $sheet.toPhone)
                    .keyboardType(.phonePad)
            }
            Section("Sender") {
                TextField("Your name", text: $sheet.fromName)
                    .textContentType(.name)
                TextField("Company", text: $sheet.fromCompany)
                    .textContentType(.organizationName)
                TextField("Phone", text: $sheet.fromPhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                TextField("Fax", text: $sheet.fromFax)
                    .keyboardType(.phonePad)
                TextField("Email", text: $sheet.fromEmail)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
            Section("Message") {
                TextField("Subject", text: $sheet.subject)
                TextField("Message", text: $sheet.message, axis: .vertical)
                    .lineLimit(4...10)
                DatePicker("Date", selection: $sheet.date, displayedComponents: .date)
            }
            Section("Marks") {
                Toggle("Urgent", isOn: $sheet.urgent)
                Toggle("For Review", isOn: $sheet.forReview)
                Toggle("Please Comment", isOn: $sheet.pleaseComment)
                Toggle("Please Reply", isOn: $sheet.pleaseReply)
                Toggle("Confidentiality notice", isOn: $sheet.confidential)
            }
        }
    }
}

/// A free fax cover sheet generator: fill it in, then print, share or save it as a PDF.
struct CoverSheetTab: View {
    @State private var sheet = CoverSheet.withSavedSender()
    @State private var previewURL: URL?

    var body: some View {
        NavigationStack {
            CoverSheetEditor(sheet: $sheet, showsRecipient: false,
                             intro: "Free fax cover sheet maker. Fill it in, then tap Preview to print it or share it as a PDF.")
                .navigationTitle("Cover Sheet")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Preview") { makePreview() }
                            .fontWeight(.semibold)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Reset") { sheet = CoverSheet.withSavedSender() }
                    }
                }
                .sheet(item: $previewURL) { url in
                    PDFPreviewSheet(url: url, title: "Cover Sheet")
                }
        }
        #if DEBUG
        .onAppear {
            if DemoMode.screen == "cover" { sheet = DemoMode.coverSheet }
            if DemoMode.screen == "coverpreview" { sheet = DemoMode.coverSheet; makePreview() }
        }
        #endif
    }

    private func makePreview() {
        let name = sheet.toName.isEmpty ? "Fax Cover Sheet" : "Fax Cover Sheet - \(sheet.toName)"
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(safe).pdf")
        if (try? PDFBuilder.coverOnly(sheet, to: url)) != nil { previewURL = url }
    }
}
