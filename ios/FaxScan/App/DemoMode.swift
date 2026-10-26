#if DEBUG
import SwiftUI
import SwiftData

/// Debug-only sample content for screenshots and UI checks.
/// Launch with `-demo send|history|detail|cover|settings|paywall|preview`.
@MainActor
enum DemoMode {
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-demo"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static func container() -> ModelContainer {
        try! ModelContainer(for: FaxRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// Runs before any view is built, so every screen sees the sample sender.
    static func prepareDefaults() {
        UserDefaults.standard.set("Jordan Miller", forKey: SenderKeys.name)
        UserDefaults.standard.set("Miller & Co. Realty", forKey: SenderKeys.company)
        UserDefaults.standard.set("(415) 555-0182", forKey: SenderKeys.phone)
        UserDefaults.standard.set("jordan@millerco.example", forKey: SenderKeys.email)
    }

    static var coverSheet: CoverSheet {
        var sheet = CoverSheet.withSavedSender()
        sheet.toName = "Sam Rivera"
        sheet.toCompany = "Bayview Title Company"
        sheet.toFax = "(415) 555-0136"
        sheet.subject = "Signed purchase agreement"
        sheet.message = "Hi Sam, attached are the signed purchase agreement and the disclosure form for 1458 Oak Street. Please confirm once received. Thanks!"
        sheet.urgent = true
        sheet.pleaseReply = true
        return sheet
    }

    static func apply(screen: String, router: Router, draft: FaxDraft, context: ModelContext) {

        draft.recipientName = "Bayview Title Company"
        draft.faxDigits = "4155550136"
        draft.cover = coverSheet
        draft.cover.toName = ""
        draft.cover.toFax = ""
        draft.add(images: [samplePage(title: "Residential Purchase Agreement", lines: 26, signature: true),
                           samplePage(title: "Seller Disclosure Statement", lines: 30, signature: false),
                           samplePage(title: "Addendum A", lines: 18, signature: true)])

        let samples: [(String, String, Int, FaxStatus, Double, String?)] = [
            ("Bayview Title Company", "+14155550136", 4, .sending, -60, nil),
            ("Dr. Patel Family Medicine", "+16465550192", 2, .delivered, -3_600 * 5, nil),
            ("City Permit Office", "+13125550147", 6, .delivered, -86_400 * 1.2, nil),
            ("Harbor Insurance Claims", "+18005550111", 3, .failed, -86_400 * 2.5, "The line was busy. Try again in a few minutes."),
            ("Westside Pharmacy", "+12135550178", 1, .delivered, -86_400 * 4, nil),
            ("", "+17185550163", 5, .delivered, -86_400 * 6, nil),
        ]
        var firstID: UUID?
        for (name, number, pages, status, offset, failure) in samples {
            let record = FaxRecord(serverID: UUID().uuidString, recipientName: name, faxNumber: number,
                                   pageCount: pages, status: status, createdAt: .now.addingTimeInterval(offset))
            record.failureMessage = failure
            try? PDFBuilder.build(cover: draft.effectiveCover, pages: draft.pages.map(\.fileURL),
                                  totalPages: draft.totalPages, to: record.documentURL)
            context.insert(record)
            if firstID == nil, status == .delivered { firstID = record.id }
        }

        switch screen {
        case "history": router.tab = .history
        case "detail":
            router.tab = .history
            router.openFaxID = firstID
        case "cover", "coverpreview": router.tab = .cover
        case "settings": router.tab = .settings
        case "paywall": router.showPaywall = true
        default: router.tab = .send
        }
    }

    /// Draws a plausible document page: a heading, paragraph lines and an optional signature.
    static func samplePage(title: String, lines: Int, signature: Bool) -> UIImage {
        let size = CGSize(width: 1275, height: 1650)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            (title as NSString).draw(at: CGPoint(x: 110, y: 120), withAttributes: [
                .font: UIFont.systemFont(ofSize: 46, weight: .bold), .foregroundColor: UIColor.black])
            UIColor(white: 0.15, alpha: 1).setFill()
            context.fill(CGRect(x: 110, y: 196, width: 1055, height: 4))
            var generator = SystemRandomNumberGenerator()
            for i in 0..<lines {
                let y = 250 + CGFloat(i) * 44 + CGFloat(i / 6) * 30
                let width = i % 6 == 5 ? CGFloat.random(in: 300...600, using: &generator) : CGFloat.random(in: 900...1055, using: &generator)
                UIColor(white: 0.55, alpha: 1).setFill()
                context.fill(CGRect(x: 110, y: y, width: width, height: 14))
            }
            if signature {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 140, y: 1480))
                path.addCurve(to: CGPoint(x: 330, y: 1450), controlPoint1: CGPoint(x: 190, y: 1380), controlPoint2: CGPoint(x: 260, y: 1520))
                path.addCurve(to: CGPoint(x: 520, y: 1460), controlPoint1: CGPoint(x: 390, y: 1390), controlPoint2: CGPoint(x: 450, y: 1530))
                path.lineWidth = 6
                UIColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1).setStroke()
                path.stroke()
                UIColor.black.setFill()
                context.fill(CGRect(x: 110, y: 1500, width: 520, height: 3))
                ("Signature" as NSString).draw(at: CGPoint(x: 110, y: 1512), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.darkGray])
            }
        }
    }
}
#endif
