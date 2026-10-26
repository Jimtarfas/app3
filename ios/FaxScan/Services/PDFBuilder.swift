import UIKit

/// Builds US Letter PDFs: an optional cover sheet followed by the scanned or imported pages.
enum PDFBuilder {
    static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

    static func build(cover: CoverSheet?, pages: [URL], totalPages: Int, to url: URL) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format())
        try renderer.writePDF(to: url) { context in
            if let cover {
                context.beginPage()
                CoverSheetRenderer.draw(cover, totalPages: totalPages, in: pageRect)
            }
            for page in pages {
                guard let image = UIImage(contentsOfFile: page.path) else { continue }
                context.beginPage()
                UIColor.white.setFill()
                UIRectFill(pageRect)
                image.draw(in: aspectFit(image.size, in: pageRect.insetBy(dx: 18, dy: 18)))
            }
        }
    }

    static func coverOnly(_ cover: CoverSheet, to url: URL) throws {
        try build(cover: cover, pages: [], totalPages: 1, to: url)
    }

    private static func format() -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextCreator as String: "Fax & Scan"]
        return format
    }

    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
}

enum CoverSheetRenderer {
    static func draw(_ sheet: CoverSheet, totalPages: Int, in page: CGRect) {
        UIColor.white.setFill()
        UIRectFill(page)

        let margin: CGFloat = 54
        let width = page.width - margin * 2
        var y: CGFloat = 54

        // Title and date
        text("FAX", font: .systemFont(ofSize: 54, weight: .black), at: CGPoint(x: margin, y: y))
        let date = sheet.date.formatted(date: .long, time: .omitted)
        let dateFont = UIFont.systemFont(ofSize: 12, weight: .medium)
        let dateWidth = (date as NSString).size(withAttributes: [.font: dateFont]).width
        text(date, font: dateFont, at: CGPoint(x: page.width - margin - dateWidth, y: y + 40))
        y += 74
        rule(y: y, from: margin, width: width, thickness: 3)
        y += 22

        // To / From columns
        let column = (width - 24) / 2
        let toRows = [("To", sheet.toName), ("Company", sheet.toCompany), ("Fax", sheet.toFax), ("Phone", sheet.toPhone)]
        let fromRows = [("From", sheet.fromName), ("Company", sheet.fromCompany), ("Fax", sheet.fromFax),
                        ("Phone", sheet.fromPhone), ("Email", sheet.fromEmail)]
        let leftBottom = rows(toRows, x: margin, y: y, width: column)
        let rightBottom = rows(fromRows, x: margin + column + 24, y: y, width: column)
        y = max(leftBottom, rightBottom) + 10
        rule(y: y, from: margin, width: width, thickness: 1)
        y += 16

        // Subject and page count
        y = rows([("Subject", sheet.subject), ("Pages", "\(totalPages) including cover")], x: margin, y: y, width: width) + 8

        // Checkboxes
        let boxes = [("Urgent", sheet.urgent), ("For Review", sheet.forReview),
                     ("Please Comment", sheet.pleaseComment), ("Please Reply", sheet.pleaseReply)]
        var x = margin
        for (label, checked) in boxes {
            let box = CGRect(x: x, y: y + 2, width: 12, height: 12)
            let path = UIBezierPath(rect: box)
            path.lineWidth = 1.2
            UIColor.black.setStroke()
            path.stroke()
            if checked {
                let check = UIBezierPath()
                check.move(to: CGPoint(x: box.minX + 2.5, y: box.midY))
                check.addLine(to: CGPoint(x: box.minX + 5, y: box.maxY - 2.5))
                check.addLine(to: CGPoint(x: box.maxX - 2, y: box.minY + 2))
                check.lineWidth = 1.8
                check.stroke()
            }
            let font = UIFont.systemFont(ofSize: 11, weight: .medium)
            text(label, font: font, at: CGPoint(x: x + 17, y: y))
            x += 17 + (label as NSString).size(withAttributes: [.font: font]).width + 22
        }
        y += 30

        // Message
        text("MESSAGE", font: .systemFont(ofSize: 10, weight: .bold), color: .darkGray, at: CGPoint(x: margin, y: y))
        y += 16
        let footerHeight: CGFloat = sheet.confidential ? 70 : 20
        let messageBox = CGRect(x: margin, y: y, width: width, height: page.height - y - margin - footerHeight)
        let border = UIBezierPath(roundedRect: messageBox, cornerRadius: 4)
        border.lineWidth = 1
        UIColor.lightGray.setStroke()
        border.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        (sheet.message as NSString).draw(
            with: messageBox.insetBy(dx: 12, dy: 12),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.black, .paragraphStyle: paragraph],
            context: nil)

        if sheet.confidential {
            let notice = "CONFIDENTIALITY NOTICE: This fax may contain confidential information intended only for the recipient named above. If you received it in error, please notify the sender and destroy all copies."
            (notice as NSString).draw(
                with: CGRect(x: margin, y: page.height - margin - 52, width: width, height: 52),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: UIFont.systemFont(ofSize: 8.5), .foregroundColor: UIColor.darkGray],
                context: nil)
        }
    }

    /// Draws "Label: value" rows and returns the y after the last one.
    private static func rows(_ items: [(String, String)], x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        var y = y
        let labelWidth: CGFloat = 62
        for (label, value) in items {
            text(label.uppercased(), font: .systemFont(ofSize: 9, weight: .bold), color: .darkGray, at: CGPoint(x: x, y: y + 3))
            let valueRect = CGRect(x: x + labelWidth, y: y, width: width - labelWidth, height: 18)
            (value as NSString).draw(with: valueRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                     attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: UIColor.black],
                                     context: nil)
            rule(y: y + 19, from: x + labelWidth, width: width - labelWidth, thickness: 0.5, color: .lightGray)
            y += 27
        }
        return y
    }

    private static func text(_ string: String, font: UIFont, color: UIColor = .black, at point: CGPoint) {
        (string as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private static func rule(y: CGFloat, from x: CGFloat, width: CGFloat, thickness: CGFloat, color: UIColor = .black) {
        color.setFill()
        UIRectFill(CGRect(x: x, y: y, width: width, height: thickness))
    }
}
