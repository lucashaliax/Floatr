// Draws the Floatr app icon and the Safari toolbar glyph.
// Usage: swift tools/make_icons.swift   (from the project root)
import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// MARK: - App icon

func drawAppIcon(size s: CGFloat, in ctx: CGContext) {
    let u = s / 1024
    // macOS icon grid: 824pt body centred in 1024 with ~185pt corner radius.
    let body = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186 * u, cornerHeight: 186 * u, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 28 * u,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(CGColor(red: 0.08, green: 0.12, blue: 0.25, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Background: deep indigo to teal, like dusk over water.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(red: 0.07, green: 0.10, blue: 0.27, alpha: 1),
        CGColor(red: 0.10, green: 0.33, blue: 0.55, alpha: 1),
        CGColor(red: 0.16, green: 0.62, blue: 0.70, alpha: 1),
    ] as CFArray, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // Soft highlight at the top.
    let hl = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(hl, startCenter: CGPoint(x: body.midX, y: body.maxY), startRadius: 0,
                           endCenter: CGPoint(x: body.midX, y: body.maxY), endRadius: 600 * u, options: [])
    ctx.restoreGState()

    // The "screen": a thin rounded outline.
    let screen = CGRect(x: 218 * u, y: 300 * u, width: 588 * u, height: 420 * u)
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 52 * u, cornerHeight: 52 * u, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.55))
    ctx.setLineWidth(26 * u)
    ctx.strokePath()

    // The floating window: a warm "picture" raised off the screen's corner.
    let pip = CGRect(x: 470 * u, y: 196 * u, width: 400 * u, height: 260 * u)
    let pipPath = CGPath(roundedRect: pip, cornerWidth: 44 * u, cornerHeight: 44 * u, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18 * u), blur: 44 * u, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(pipPath)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(pipPath)
    ctx.clip()
    let warm = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(red: 1.00, green: 0.78, blue: 0.42, alpha: 1),
        CGColor(red: 0.98, green: 0.50, blue: 0.40, alpha: 1),
        CGColor(red: 0.80, green: 0.32, blue: 0.48, alpha: 1),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(warm, start: CGPoint(x: pip.midX, y: pip.maxY),
                           end: CGPoint(x: pip.midX, y: pip.minY), options: [])
    // A low sun and a horizon line: reads as "a video frame", not a logo.
    ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.82, alpha: 0.95))
    ctx.fillEllipse(in: CGRect(x: pip.minX + 220 * u, y: pip.minY + 92 * u, width: 92 * u, height: 92 * u))
    let hills = CGMutablePath()
    hills.move(to: CGPoint(x: pip.minX, y: pip.minY + 70 * u))
    hills.addCurve(to: CGPoint(x: pip.maxX, y: pip.minY + 96 * u),
                   control1: CGPoint(x: pip.minX + 130 * u, y: pip.minY + 150 * u),
                   control2: CGPoint(x: pip.minX + 250 * u, y: pip.minY + 30 * u))
    hills.addLine(to: CGPoint(x: pip.maxX, y: pip.minY))
    hills.addLine(to: CGPoint(x: pip.minX, y: pip.minY))
    hills.closeSubpath()
    ctx.addPath(hills)
    ctx.setFillColor(CGColor(red: 0.30, green: 0.16, blue: 0.36, alpha: 0.85))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.addPath(pipPath)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    ctx.setLineWidth(16 * u)
    ctx.strokePath()
}

func png(size: Int, scale: Int, draw: (CGFloat, CGContext) -> Void) -> Data {
    let px = size * scale
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(CGFloat(px), ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let iconSet = root.appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png(size: size, scale: scale, draw: drawAppIcon).write(to: iconSet.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appendingPathComponent("Contents.json"))
try #"{"info":{"version":1,"author":"xcode"}}"#.data(using: .utf8)!
    .write(to: root.appendingPathComponent("App/Resources/Assets.xcassets/Contents.json"))
// 1024 preview for the README.
try png(size: 1024, scale: 1, draw: drawAppIcon).write(to: root.appendingPathComponent("docs/icon.png"))

// MARK: - Toolbar glyph (template PDF: black on transparent, 16pt)

let pdfURL = root.appendingPathComponent("Extension/Resources/ToolbarIcon.pdf")
var box = CGRect(x: 0, y: 0, width: 16, height: 16)
let pdf = CGContext(pdfURL as CFURL, mediaBox: &box, nil)!
pdf.beginPDFPage(nil)
pdf.setStrokeColor(CGColor(gray: 0, alpha: 1))
pdf.setFillColor(CGColor(gray: 0, alpha: 1))
pdf.setLineWidth(1.2)
pdf.addPath(CGPath(roundedRect: CGRect(x: 1.1, y: 2.6, width: 13.8, height: 10.8), cornerWidth: 2, cornerHeight: 2, transform: nil))
pdf.strokePath()
pdf.addPath(CGPath(roundedRect: CGRect(x: 7.6, y: 4.2, width: 5.8, height: 4.2), cornerWidth: 1, cornerHeight: 1, transform: nil))
pdf.fillPath()
pdf.endPDFPage()
pdf.closePDF()

print("icons written")
