// Renders the Pulse app icon into app/App/Resources/Assets.xcassets/AppIcon.appiconset.
// Usage: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let set = root.appendingPathComponent("app/App/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 body with a continuous-corner squircle.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    NSColor.black.setFill()
    shape.fill()
    ctx.restoreGState()

    shape.addClip()
    NSGradient(colors: [NSColor(red: 0.20, green: 0.17, blue: 0.13, alpha: 1), NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)])!
        .draw(in: body, angle: -90)
    // Soft green glow behind the trace.
    NSGradient(colors: [NSColor(red: 0.36, green: 0.82, blue: 0.55, alpha: 0.28), .clear])!
        .draw(fromCenter: NSPoint(x: body.midX, y: body.midY), radius: 0,
              toCenter: NSPoint(x: body.midX, y: body.midY), radius: body.width * 0.55, options: [])

    // Faint server rack slots.
    NSColor.white.withAlphaComponent(0.06).setFill()
    for i in 0..<3 {
        let h = body.height * 0.11
        let y = body.minY + body.height * 0.14 + CGFloat(i) * h * 1.35
        NSBezierPath(roundedRect: CGRect(x: body.minX + body.width * 0.16, y: y, width: body.width * 0.68, height: h),
                     xRadius: h * 0.3, yRadius: h * 0.3).fill()
    }

    // ECG trace.
    let p = NSBezierPath()
    let pts: [(CGFloat, CGFloat)] = [(0.10, 0.56), (0.32, 0.56), (0.39, 0.66), (0.46, 0.34), (0.55, 0.84), (0.62, 0.48), (0.67, 0.56), (0.90, 0.56)]
    for (i, pt) in pts.enumerated() {
        let point = NSPoint(x: body.minX + body.width * pt.0, y: body.minY + body.height * pt.1)
        i == 0 ? p.move(to: point) : p.line(to: point)
    }
    p.lineWidth = body.width * 0.055
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    ctx.setShadow(offset: .zero, blur: s * 0.035, color: NSColor(red: 0.36, green: 0.9, blue: 0.6, alpha: 0.9).cgColor)
    NSColor(red: 0.40, green: 0.90, blue: 0.60, alpha: 1).setStroke()
    p.stroke()

    // Live dot.
    let r = body.width * 0.045
    NSColor(red: 0.55, green: 1.0, blue: 0.72, alpha: 1).setFill()
    NSBezierPath(ovalIn: CGRect(x: body.minX + body.width * 0.90 - r, y: body.minY + body.height * 0.56 - r, width: 2 * r, height: 2 * r)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try render(pt * scale).write(to: set.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: set.appendingPathComponent("Contents.json"))
let catalog = set.deletingLastPathComponent().appendingPathComponent("Contents.json")
try #"{"info":{"author":"xcode","version":1}}"#.write(to: catalog, atomically: true, encoding: .utf8)
try render(1024).write(to: root.appendingPathComponent("docs/design/icon.png"))
print("icon written")
