// Frames raw simulator captures into App Store screenshots (no alpha) with a caption.
// Usage: swift scripts/make-store-screenshots.swift <captions.json> <rawDir> <outDir> <width> <height>
import AppKit

let args = CommandLine.arguments
let captions = try! JSONDecoder().decode([[String]].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let rawDir = args[2], outDir = args[3]
let width = Int(args[4])!, height = Int(args[5])!
let W = CGFloat(width), H = CGFloat(height)
let k = W / 1320 // layout was designed at 1320 wide
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func fitted(_ text: String, weight: NSFont.Weight, maxSize: CGFloat, minSize: CGFloat, in rect: NSRect, color: NSColor) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    var size = maxSize
    while true {
        let s = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
        let b = s.boundingRect(with: NSSize(width: rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
        if b.height <= rect.height || size <= minSize { return s }
        size -= 4
    }
}

for (index, entry) in captions.enumerated() {
    let (name, headline, sub) = (entry[0], entry[1], entry[2])
    guard let raw = NSImage(contentsOfFile: "\(rawDir)/\(name).png") else { print("missing \(name)"); continue }
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGradient(colors: [NSColor(red: 0.08, green: 0.25, blue: 0.75, alpha: 1), NSColor(red: 0.24, green: 0.52, blue: 0.98, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -75)

    let titleRect = NSRect(x: 70 * k, y: H - 440 * k, width: W - 140 * k, height: 300 * k)
    fitted(headline, weight: .heavy, maxSize: 108 * k, minSize: 70 * k, in: titleRect, color: .white).draw(with: titleRect, options: [.usesLineFragmentOrigin])
    let subRect = NSRect(x: 90 * k, y: H - 560 * k, width: W - 180 * k, height: 110 * k)
    fitted(sub, weight: .medium, maxSize: 54 * k, minSize: 38 * k, in: subRect, color: NSColor(white: 1, alpha: 0.82)).draw(with: subRect, options: [.usesLineFragmentOrigin])

    let shotW = 1000 * k
    let shotH = shotW * raw.size.height / raw.size.width
    let shotRect = NSRect(x: (W - shotW) / 2, y: H - 620 * k - shotH, width: shotW, height: shotH)
    let clip = NSBezierPath(roundedRect: shotRect, xRadius: 90 * k, yRadius: 90 * k)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.4)
    shadow.shadowBlurRadius = 60 * k
    shadow.shadowOffset = NSSize(width: 0, height: -20 * k)
    shadow.set()
    NSColor.black.setFill()
    clip.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    raw.draw(in: shotRect)
    NSGraphicsContext.restoreGraphicsState()
    let border = NSBezierPath(roundedRect: shotRect.insetBy(dx: -6 * k, dy: -6 * k), xRadius: 96 * k, yRadius: 96 * k)
    border.lineWidth = 12 * k
    NSColor(white: 0.08, alpha: 1).setStroke()
    border.stroke()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    let out = "\(outDir)/\(String(format: "%02d", index + 1))-\(name).png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}
