// Renders the 1024×1024 app icon (no alpha): a document with a paper plane on a blue gradient.
// Usage: swift scripts/make-icon.swift ios/FaxScan/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

let size = 1024
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let canvas = NSRect(x: 0, y: 0, width: size, height: size)

NSGradient(colors: [NSColor(red: 0.10, green: 0.31, blue: 0.85, alpha: 1),
                    NSColor(red: 0.27, green: 0.56, blue: 1.00, alpha: 1)])!.draw(in: canvas, angle: 60)

// Document with a folded corner
let doc = NSRect(x: 262, y: 190, width: 440, height: 580)
let fold: CGFloat = 110
let page = NSBezierPath()
page.move(to: NSPoint(x: doc.minX + 36, y: doc.minY))
page.line(to: NSPoint(x: doc.maxX - 36, y: doc.minY))
page.curve(to: NSPoint(x: doc.maxX, y: doc.minY + 36), controlPoint1: NSPoint(x: doc.maxX - 16, y: doc.minY), controlPoint2: NSPoint(x: doc.maxX, y: doc.minY + 16))
page.line(to: NSPoint(x: doc.maxX, y: doc.maxY - fold))
page.line(to: NSPoint(x: doc.maxX - fold, y: doc.maxY))
page.line(to: NSPoint(x: doc.minX + 36, y: doc.maxY))
page.curve(to: NSPoint(x: doc.minX, y: doc.maxY - 36), controlPoint1: NSPoint(x: doc.minX + 16, y: doc.maxY), controlPoint2: NSPoint(x: doc.minX, y: doc.maxY - 16))
page.line(to: NSPoint(x: doc.minX, y: doc.minY + 36))
page.curve(to: NSPoint(x: doc.minX + 36, y: doc.minY), controlPoint1: NSPoint(x: doc.minX, y: doc.minY + 16), controlPoint2: NSPoint(x: doc.minX + 16, y: doc.minY))
page.close()

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.set()
NSColor.white.setFill()
page.fill()
NSGraphicsContext.restoreGraphicsState()

let corner = NSBezierPath()
corner.move(to: NSPoint(x: doc.maxX, y: doc.maxY - fold))
corner.line(to: NSPoint(x: doc.maxX - fold + 18, y: doc.maxY - fold))
corner.curve(to: NSPoint(x: doc.maxX - fold, y: doc.maxY - fold + 18), controlPoint1: NSPoint(x: doc.maxX - fold + 6, y: doc.maxY - fold), controlPoint2: NSPoint(x: doc.maxX - fold, y: doc.maxY - fold + 6))
corner.line(to: NSPoint(x: doc.maxX - fold, y: doc.maxY))
corner.close()
NSColor(red: 0.80, green: 0.87, blue: 0.98, alpha: 1).setFill()
corner.fill()

// Text lines
NSColor(red: 0.74, green: 0.80, blue: 0.90, alpha: 1).setFill()
for (i, width) in [250.0, 330, 330, 300, 200].enumerated() {
    let y = doc.maxY - 170 - CGFloat(i) * 62
    NSBezierPath(roundedRect: NSRect(x: doc.minX + 56, y: y, width: CGFloat(width), height: 26), xRadius: 13, yRadius: 13).fill()
}

// Paper plane badge
let badgeCenter = NSPoint(x: 700, y: 280)
let badge = NSBezierPath(ovalIn: NSRect(x: badgeCenter.x - 150, y: badgeCenter.y - 150, width: 300, height: 300))
NSGraphicsContext.saveGraphicsState()
let badgeShadow = NSShadow()
badgeShadow.shadowColor = NSColor(white: 0, alpha: 0.3)
badgeShadow.shadowBlurRadius = 30
badgeShadow.shadowOffset = NSSize(width: 0, height: -10)
badgeShadow.set()
NSColor(red: 1.0, green: 0.55, blue: 0.13, alpha: 1).setFill()
badge.fill()
NSGraphicsContext.restoreGraphicsState()

let plane = NSBezierPath()
let c = badgeCenter
plane.move(to: NSPoint(x: c.x - 92, y: c.y + 6))
plane.line(to: NSPoint(x: c.x + 96, y: c.y + 80))
plane.line(to: NSPoint(x: c.x + 40, y: c.y - 92))
plane.line(to: NSPoint(x: c.x - 4, y: c.y - 30))
plane.line(to: NSPoint(x: c.x - 26, y: c.y - 78))
plane.line(to: NSPoint(x: c.x - 30, y: c.y - 16))
plane.close()
NSColor.white.setFill()
plane.fill()
let crease = NSBezierPath()
crease.move(to: NSPoint(x: c.x - 30, y: c.y - 16))
crease.line(to: NSPoint(x: c.x + 96, y: c.y + 80))
crease.lineWidth = 10
NSColor(red: 1.0, green: 0.86, blue: 0.70, alpha: 1).setStroke()
crease.stroke()

let image = context.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: output)
print("wrote \(output.path)")
