// Builds every Pulse icon from the master artwork docs/design/logo.png:
// the macOS AppIcon set (logo on a squircle tile), the Linux hicolor PNGs,
// and the site's favicon and touch icons.
// Usage: swift scripts/make-icon.swift [repo-root]
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
func at(_ path: String) -> URL { root.appendingPathComponent(path) }

guard let logo = NSImage(contentsOf: at("docs/design/logo.png")) else { fatalError("docs/design/logo.png missing") }

enum Tile { case none, squircle, square }

func color(_ hex: UInt32) -> NSColor {
    NSColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

/// Renders the logo at `px` pixels. `fill` is the share of the canvas (or tile) the logo takes.
func render(_ px: Int, tile: Tile, fill: CGFloat) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    NSGraphicsContext.current!.imageInterpolation = .high

    var body = CGRect(x: 0, y: 0, width: s, height: s)
    if tile != .none {
        if tile == .squircle {
            // macOS icon grid: 824/1024 body with a continuous-corner squircle and a soft drop shadow.
            body = body.insetBy(dx: s * 100 / 1024, dy: s * 100 / 1024)
        }
        let radius = tile == .squircle ? body.width * 0.225 : 0
        let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
        if tile == .squircle {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
            NSColor.black.setFill()
            shape.fill()
            ctx.restoreGState()
        }
        ctx.saveGState()
        shape.addClip()
        NSGradient(colors: [color(0xF4F8FE), color(0xBCD3F2)])!.draw(in: body, angle: -90)
        ctx.restoreGState()
    }

    let side = body.width * fill
    let rect = CGRect(x: body.midX - side / 2, y: body.midY - side / 2, width: side, height: side)
    if tile != .none {
        ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.025), blur: side * 0.05, color: color(0x0A1733).withAlphaComponent(0.35).cgColor)
    }
    logo.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ path: String) throws {
    try FileManager.default.createDirectory(at: at(path).deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: at(path))
}

// macOS
let set = "app/App/Resources/Assets.xcassets/AppIcon.appiconset"
var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try write(render(pt * scale, tile: .squircle, fill: 0.8), "\(set)/\(name)")
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: at("\(set)/Contents.json"))
try #"{"info":{"author":"xcode","version":1}}"#.write(to: at("app/App/Resources/Assets.xcassets/Contents.json"), atomically: true, encoding: .utf8)
try write(render(1024, tile: .squircle, fill: 0.8), "docs/design/icon.png")

// Linux (GNOME icons carry their own shape, so no tile; a small margin like the Adwaita grid)
for px in [48, 64, 128, 256, 512] {
    try write(render(px, tile: .none, fill: 0.9), "linux/data/icons/\(px).png")
}
try write(render(256, tile: .none, fill: 0.9), "linux/pulse_monitor/icons/io.github.kutluhangil.Pulse.png")

// Site
try write(render(64, tile: .none, fill: 1), "site/public/favicon.png")
try write(render(96, tile: .none, fill: 1), "site/public/mark.png")
try write(render(256, tile: .none, fill: 0.92), "site/public/icon-256.png")
try write(render(180, tile: .square, fill: 0.78), "site/public/apple-touch-icon.png")
print("icons written")
