import SwiftUI
import SwiftData
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

struct SendView: View {
    @Environment(FaxDraft.self) private var draft
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context

    @State private var showScanner = false
    @State private var showFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var previewURL: URL?
    @State private var confirmSend = false
    @State private var isSending = false
    @State private var sendAfterPurchase = false
    @State private var alert: AlertItem?
    @FocusState private var numberFocused: Bool

    var body: some View {
        @Bindable var draft = draft
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Text("+1")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        TextField("Fax number", text: Binding(
                            get: { PhoneFormatter.pretty(draft.faxDigits) },
                            set: { draft.faxDigits = PhoneFormatter.nationalDigits($0) }))
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .font(.body.monospacedDigit())
                            .focused($numberFocused)
                    }
                    TextField("Recipient name (optional)", text: $draft.recipientName)
                        .textContentType(.name)
                } header: {
                    Text("To")
                } footer: {
                    Text("Send to fax numbers in the United States and Canada.")
                }

                Section {
                    if draft.pages.isEmpty {
                        emptyPages
                    } else {
                        PageStrip(draft: draft, onTap: { _ in preview() })
                            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    }
                    addButtons
                } header: {
                    Text("Documents")
                } footer: {
                    if !draft.pages.isEmpty {
                        Text("Touch and hold a page to move or remove it.")
                    }
                }

                Section {
                    Toggle("Add cover sheet", isOn: $draft.includeCover)
                    if draft.includeCover {
                        NavigationLink {
                            CoverSheetEditor(sheet: $draft.cover, showsRecipient: true)
                                .navigationTitle("Cover Sheet")
                        } label: {
                            LabeledContent("Subject", value: draft.cover.subject.isEmpty ? "None" : draft.cover.subject)
                        }
                    }
                } header: {
                    Text("Cover Sheet")
                } footer: {
                    Text("Your saved sender details from Settings are filled in for you.")
                }

                Section {
                    Button {
                        preview()
                    } label: {
                        Label("Preview Fax", systemImage: "eye")
                    }
                    .disabled(draft.totalPages == 0)
                }
            }
            .navigationTitle("Send Fax")
            .safeAreaInset(edge: .bottom) { sendBar }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { numberFocused = false }
                }
                if !draft.pages.isEmpty || !draft.faxDigits.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) { draft.reset() }
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner { images in
                    draft.add(images: images)
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                importFiles(result)
            }
            .onChange(of: photoItems) { _, items in
                Task { await importPhotos(items) }
            }
            .sheet(item: $previewURL) { url in
                PDFPreviewSheet(url: url, title: "Preview")
            }
            .confirmationDialog(confirmTitle, isPresented: $confirmSend, titleVisibility: .visible) {
                Button("Send Fax") { Task { await send() } }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: store.isSubscribed) { _, subscribed in
                if subscribed && sendAfterPurchase {
                    sendAfterPurchase = false
                    confirmSend = true
                }
            }
            .alert(item: $alert) { item in
                Alert(title: Text(item.title), message: Text(item.message))
            }
            .overlay {
                if isSending { SendingOverlay(pages: draft.totalPages) }
            }
            #if DEBUG
            .task {
                guard DemoMode.screen == "preview" else { return }
                try? await Task.sleep(for: .seconds(1.5))
                preview()
            }
            #endif
        }
    }

    private var emptyPages: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tint)
            Text("Add the pages you want to fax")
                .font(.subheadline.weight(.medium))
            Text("Scan paper documents, or pick photos and PDF files.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var addButtons: some View {
        HStack(spacing: 10) {
            AddSourceButton(title: "Scan", symbol: "camera.viewfinder") {
                if VNDocumentCameraViewController.isSupported {
                    showScanner = true
                } else {
                    alert = AlertItem(title: "Scanner Unavailable", message: "Document scanning isn't available on this device. Add photos or files instead.")
                }
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: Theme.maxPagesPerFax, matching: .images) {
                AddSourceLabel(title: "Photos", symbol: "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            AddSourceButton(title: "Files", symbol: "folder") { showFiles = true }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    }

    private var sendBar: some View {
        VStack(spacing: 6) {
            Button {
                startSend()
            } label: {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text(draft.totalPages > 0 ? "Send Fax · \(draft.totalPages) \(draft.totalPages == 1 ? "page" : "pages")" : "Send Fax")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSending)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private var confirmTitle: String {
        let number = draft.faxNumberE164.map(PhoneFormatter.display) ?? ""
        let pages = draft.totalPages == 1 ? "1 page" : "\(draft.totalPages) pages"
        return "Send \(pages) to \(number)?"
    }

    private func startSend() {
        numberFocused = false
        guard draft.faxNumberE164 != nil else {
            alert = AlertItem(title: "Check the Fax Number", message: "Enter a 10-digit US or Canada fax number, including the area code.")
            return
        }
        guard !draft.pages.isEmpty || draft.includeCover else {
            alert = AlertItem(title: "Nothing to Send", message: "Scan or add at least one page, or turn on the cover sheet.")
            return
        }
        guard draft.totalPages <= Theme.maxPagesPerFax else {
            alert = AlertItem(title: "Too Many Pages", message: "A fax can have up to \(Theme.maxPagesPerFax) pages. Remove some pages and try again.")
            return
        }
        guard store.isSubscribed else {
            sendAfterPurchase = true
            router.showPaywall = true
            return
        }
        confirmSend = true
    }

    private func send() async {
        guard let jws = store.activeJWS else {
            router.showPaywall = true
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            let record = try await FaxSender.send(draft: draft, jws: jws, context: context)
            draft.reset()
            router.openFaxID = record.id
            router.tab = .history
        } catch let error as FaxAPI.APIError where error.needsSubscription {
            await store.refreshEntitlements()
            alert = AlertItem(title: "Subscription Needed", message: error.message)
        } catch {
            alert = AlertItem(title: "Fax Not Sent", message: error.friendlyMessage)
        }
    }

    private func preview() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Preview-\(UUID().uuidString).pdf")
        do {
            try PDFBuilder.build(cover: draft.includeCover ? draft.effectiveCover : nil,
                                 pages: draft.pages.map(\.fileURL), totalPages: draft.totalPages, to: url)
            previewURL = url
        } catch {
            alert = AlertItem(title: "Preview Failed", message: error.localizedDescription)
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        draft.add(images: images)
        photoItems = []
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var failed = 0
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                if draft.add(pdf: url) == 0 { failed += 1 }
            } else if let image = UIImage(contentsOfFile: url.path) {
                draft.add(images: [image])
            } else {
                failed += 1
            }
        }
        if failed > 0 {
            alert = AlertItem(title: "Some Files Weren't Added", message: "\(failed) file(s) couldn't be opened. Locked PDFs aren't supported.")
        }
    }
}

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private struct AddSourceButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { AddSourceLabel(title: title, symbol: symbol) }
            .buttonStyle(.plain)
    }
}

private struct AddSourceLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PageStrip: View {
    let draft: FaxDraft
    let onTap: (DraftPage) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(draft.pages.enumerated()), id: \.element.id) { index, page in
                    VStack(spacing: 6) {
                        Image(uiImage: page.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 84, height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                        Text("Page \(index + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(page) }
                    .contextMenu {
                        if index > 0 {
                            Button { draft.move(page, by: -1) } label: { Label("Move Left", systemImage: "arrow.left") }
                        }
                        if index < draft.pages.count - 1 {
                            Button { draft.move(page, by: 1) } label: { Label("Move Right", systemImage: "arrow.right") }
                        }
                        Button(role: .destructive) { draft.remove(page) } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct SendingOverlay: View {
    let pages: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Sending your fax…")
                    .font(.headline)
                Text("Uploading \(pages) \(pages == 1 ? "page" : "pages") securely")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
