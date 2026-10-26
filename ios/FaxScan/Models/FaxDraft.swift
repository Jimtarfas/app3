import SwiftUI
import PDFKit

/// One page waiting to be faxed. The full-size image lives in a temporary file
/// so a 50-page fax doesn't have to sit in memory.
struct DraftPage: Identifiable, Equatable {
    let id = UUID()
    let fileURL: URL
    let thumbnail: UIImage
}

@MainActor @Observable
final class FaxDraft {
    var recipientName = ""
    var faxDigits = ""
    var pages: [DraftPage] = []
    var includeCover = true
    var cover = CoverSheet.withSavedSender()

    init() {
        // Pages left over from a previous launch can't be reached any more.
        try? FileManager.default.removeItem(at: PageStore.folder)
        try? FileManager.default.createDirectory(at: PageStore.folder, withIntermediateDirectories: true)
    }

    var totalPages: Int { pages.count + (includeCover ? 1 : 0) }

    var faxNumberE164: String? { PhoneFormatter.e164(faxDigits) }

    func add(images: [UIImage]) {
        for image in images {
            if let page = PageStore.save(image) { pages.append(page) }
        }
    }

    func add(pdf url: URL) -> Int {
        guard let document = PDFDocument(url: url) else { return 0 }
        var added = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if let image = PageStore.render(page), let saved = PageStore.save(image) {
                pages.append(saved)
                added += 1
            }
        }
        return added
    }

    func remove(_ page: DraftPage) {
        pages.removeAll { $0.id == page.id }
        try? FileManager.default.removeItem(at: page.fileURL)
    }

    func move(_ page: DraftPage, by offset: Int) {
        guard let index = pages.firstIndex(of: page) else { return }
        let target = index + offset
        guard pages.indices.contains(target) else { return }
        pages.swapAt(index, target)
    }

    /// The cover sheet as it will be sent, with the recipient filled in from the form.
    var effectiveCover: CoverSheet {
        var sheet = cover
        if sheet.toName.isEmpty { sheet.toName = recipientName }
        if sheet.toFax.isEmpty, let number = faxNumberE164 { sheet.toFax = PhoneFormatter.display(number) }
        return sheet
    }

    func reset() {
        for page in pages { try? FileManager.default.removeItem(at: page.fileURL) }
        recipientName = ""
        faxDigits = ""
        pages = []
        includeCover = true
        cover = CoverSheet.withSavedSender()
    }
}

enum PageStore {
    static let folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DraftPages", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Fax machines print at roughly 200 dpi, so a letter page never needs more than 2200 px.
    static let maxDimension: CGFloat = 2200

    static func save(_ image: UIImage) -> DraftPage? {
        let scaled = downscale(image, to: maxDimension)
        guard let data = scaled.jpegData(compressionQuality: 0.7) else { return nil }
        let url = folder.appendingPathComponent(UUID().uuidString + ".jpg")
        do { try data.write(to: url) } catch { return nil }
        return DraftPage(fileURL: url, thumbnail: downscale(scaled, to: 400))
    }

    static func render(_ page: PDFPage) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(maxDimension / max(bounds.width, bounds.height), 200.0 / 72.0)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    static func downscale(_ image: UIImage, to maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return image }
        let factor = maxSide / longest
        let target = CGSize(width: (size.width * factor).rounded(), height: (size.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
