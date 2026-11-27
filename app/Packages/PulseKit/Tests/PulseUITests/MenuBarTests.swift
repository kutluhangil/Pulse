import AppKit
import Foundation
import ImageIO
import PulseCore
import Testing
import UniformTypeIdentifiers
@testable import PulseUI

private func snapshot() throws -> Snapshot {
    let url = try #require(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
    return try PulseJSON.decoder().decode(Snapshot.self, from: Data(contentsOf: url))
}

/// Renders an image on a menu-bar-like background at `scale`.
private func bitmap(_ img: NSImage, dark: Bool, scale: CGFloat = 4) -> CGImage {
    let size = NSSize(width: img.size.width + 12, height: img.size.height)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
        (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSRect(origin: .zero, size: size).fill()
        img.draw(in: NSRect(x: 6, y: 0, width: img.size.width, height: img.size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

@Suite struct MenuBarTests {
    @Test func columnsFollowFieldsAndLevels() throws {
        var s = try snapshot()
        s.thermal.packageC = 91
        let cols = MenuBarRenderer.columns(for: s, fields: [.temp, .cpu, .containers], live: true)
        #expect(cols.map(\.label) == ["TMP", "CPU", "CTR"])
        #expect(cols[0].value == "91°C" && cols[0].level == .critical)
        #expect(cols[2].value == "\(s.runningCount)")
        let offline = MenuBarRenderer.columns(for: s, fields: [.temp], live: false)
        #expect(offline[0].value == "—")
        #expect(MenuBarRenderer.dotColor(snapshot: s, live: false) == .systemGray)
    }

    @Test @MainActor func everyStyleHasWidth() throws {
        let s = try snapshot()
        let cols = MenuBarRenderer.columns(for: s, fields: [.temp, .cpu, .mem], live: true)
        for content in MenuContent.allCases {
            for animation in MenuAnimation.allCases {
                for layout in MenuLayout.allCases {
                    let style = MenuBarRenderer.Style(content: content, animation: animation, layout: layout)
                    let img = try #require(MenuBarRenderer.image(columns: cols, dot: .systemGreen, style: style, phase: 0.3))
                    #expect(img.size.height == 22 && img.size.width > 0)
                }
            }
        }
        // Icon-only with no animation still shows the dot.
        let bare = MenuBarRenderer.image(columns: [], dot: .systemGreen, style: .init(content: .icon, animation: .none))
        #expect((bare?.size.width ?? 0) >= 7)
    }

    /// With PULSE_SNAPSHOT_DIR set, writes animated GIF previews of each
    /// character (dark and light menu bar) for design review.
    @Test @MainActor func writesPreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["PULSE_SNAPSHOT_DIR"] else { return }
        let s = try snapshot()
        let cols = MenuBarRenderer.columns(for: s, fields: [.temp, .cpu, .mem], live: true)
        for animation in [MenuAnimation.server, .cat, .pulse] {
            for dark in [true, false] {
                let url = URL(fileURLWithPath: dir).appending(path: "menubar-\(animation.rawValue)-\(dark ? "dark" : "light").gif")
                let frames = 24
                let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil))
                CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                for f in 0..<frames {
                    let img = try #require(MenuBarRenderer.image(columns: cols, dot: .systemGreen,
                                                                 style: .init(animation: animation), phase: Double(f) / Double(frames)))
                    CGImageDestinationAddImage(dest, bitmap(img, dark: dark),
                                               [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.06]] as CFDictionary)
                }
                #expect(CGImageDestinationFinalize(dest))
                // A frame strip PNG too, for quick viewing.
                if dark {
                    let strip = URL(fileURLWithPath: dir).appending(path: "menubar-\(animation.rawValue)-strip.png")
                    let sdest = try #require(CGImageDestinationCreateWithURL(strip as CFURL, UTType.png.identifier as CFString, 1, nil))
                    let tiles = (0..<6).compactMap { f in
                        MenuBarRenderer.image(columns: cols, dot: .systemGreen, style: .init(animation: animation), phase: Double(f) / 6)
                            .map { bitmap($0, dark: true) }
                    }
                    let w = tiles[0].width, h = tiles[0].height
                    let ctx = CGContext(data: nil, width: w, height: h * tiles.count, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    for (i, t) in tiles.enumerated() { ctx.draw(t, in: CGRect(x: 0, y: h * (tiles.count - 1 - i), width: w, height: h)) }
                    CGImageDestinationAddImage(sdest, ctx.makeImage()!, nil)
                    #expect(CGImageDestinationFinalize(sdest))
                }
            }
        }
    }

    @Test func wording() {
        #expect(shortOS("Ubuntu 24.04.5 LTS") == "Ubuntu 24.04")
        #expect(shortOS("Debian GNU/Linux 12 (bookworm)") == "Debian GNU/Linux 12 (bookworm)")
        #expect(shortCPU("Intel Core i7-3615QM") == "i7-3615QM")
        #expect(reasonText("unknown_code") == "unknown_code")
    }
}
