import AppKit

/// Animated menu bar characters, drawn procedurally (no bitmap assets) so they
/// stay crisp at any scale and follow the menu bar's light or dark appearance.
/// `phase` runs 0..<1 over one loop; the caller advances it, faster under load.
public enum MenuBarSprites {
    public static let size = NSSize(width: 20, height: 18)

    /// Frames per loop used for GIF previews; the live item interpolates freely.
    public static let previewFrames = 12

    /// Whether the sprite already shows health (so no separate dot is needed).
    public static func encodesHealth(_ kind: MenuAnimation) -> Bool {
        kind == .server || kind == .pulse
    }

    public static func draw(_ kind: MenuAnimation, phase: Double, health: NSColor, in rect: NSRect) {
        switch kind {
        case .server: server(phase, health, rect)
        case .cat: cat(phase, rect)
        case .pulse: pulse(phase, health, rect)
        case .none: break
        }
    }

    // MARK: Server: a little rack unit that hops, squashes on landing and blinks its LEDs.

    private static func server(_ phase: Double, _ health: NSColor, _ r: NSRect) {
        let ink = NSColor.labelColor
        let hop = max(0, sin(phase * 2 * .pi))            // 0 on the ground, 1 at the top
        let landing = max(0, -sin(phase * 2 * .pi))        // squash while touching down
        let w: CGFloat = 12 + landing * 1.6
        let h: CGFloat = 12 - landing * 1.8
        let x = r.midX - w / 2
        let y = r.minY + 2 + hop * 4.2

        // Shadow shrinks as it rises.
        ink.withAlphaComponent(0.22).setFill()
        let sw = 10 - hop * 4
        NSBezierPath(ovalIn: NSRect(x: r.midX - sw / 2, y: r.minY, width: sw, height: 1.6)).fill()

        let body = NSRect(x: x, y: y, width: w, height: h)
        ink.setStroke()
        let box = NSBezierPath(roundedRect: body.insetBy(dx: 0.6, dy: 0.6), xRadius: 2.2, yRadius: 2.2)
        box.lineWidth = 1.2
        box.stroke()
        for i in 0..<3 {
            let sy = body.minY + 2.4 + CGFloat(i) * 3.2
            let slot = NSBezierPath()
            slot.move(to: NSPoint(x: body.minX + 2.4, y: sy))
            slot.line(to: NSPoint(x: body.maxX - 5, y: sy))
            slot.lineWidth = 1
            slot.stroke()
            // LEDs take the health colour and blink in turn.
            let on = Int(phase * 6 + Double(i)) % 3 != 0
            (on ? health : health.withAlphaComponent(0.25)).setFill()
            NSBezierPath(ovalIn: NSRect(x: body.maxX - 3.8, y: sy - 1, width: 2, height: 2)).fill()
        }
    }

    // MARK: Cat: a small runner whose legs swing, body bobs and tail waves.

    private static func cat(_ phase: Double, _ r: NSRect) {
        let ink = NSColor.labelColor
        let t = phase * 2 * .pi
        let bob = CGFloat(abs(sin(t))) * 1.2
        ink.setFill()
        ink.setStroke()

        // Body and head.
        let body = NSRect(x: r.minX + 4, y: r.minY + 6 + bob, width: 10, height: 5.5)
        NSBezierPath(roundedRect: body, xRadius: 2.75, yRadius: 2.75).fill()
        let head = NSRect(x: body.maxX - 2, y: body.minY + 2.5, width: 6, height: 5.5)
        NSBezierPath(ovalIn: head).fill()
        // Ears.
        for dx in [0.6, 3.4] as [CGFloat] {
            let ear = NSBezierPath()
            ear.move(to: NSPoint(x: head.minX + dx, y: head.maxY - 1.2))
            ear.line(to: NSPoint(x: head.minX + dx + 1.1, y: head.maxY + 1.8))
            ear.line(to: NSPoint(x: head.minX + dx + 2.2, y: head.maxY - 1.2))
            ear.close()
            ear.fill()
        }
        // Eye.
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: head.maxX - 2.4, y: head.midY + 0.2, width: 1.1, height: 1.1)).fill()

        // Tail waves.
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: body.minX + 0.5, y: body.midY + 1))
        tail.curve(to: NSPoint(x: body.minX - 3.2, y: body.maxY + 2.5 + CGFloat(sin(t * 2)) * 1.2),
                   controlPoint1: NSPoint(x: body.minX - 2, y: body.midY),
                   controlPoint2: NSPoint(x: body.minX - 3.5, y: body.maxY))
        tail.lineWidth = 1.4
        tail.lineCapStyle = .round
        tail.stroke()

        // Legs: front and back pairs swing in opposition.
        let legs: [(CGFloat, Double)] = [(body.minX + 2, 0), (body.minX + 3.5, .pi), (body.maxX - 2.5, .pi), (body.maxX - 1, 0)]
        for (lx, offset) in legs {
            let swing = CGFloat(sin(t + offset)) * 2.2
            let leg = NSBezierPath()
            leg.move(to: NSPoint(x: lx, y: body.minY + 0.8))
            leg.line(to: NSPoint(x: lx + swing, y: r.minY + 1 + max(0, CGFloat(cos(t + offset))) * 1.2))
            leg.lineWidth = 1.3
            leg.lineCapStyle = .round
            leg.stroke()
        }
    }

    // MARK: Pulse: a heartbeat trace scrolling right to left in the health colour.

    private static func pulse(_ phase: Double, _ health: NSColor, _ r: NSRect) {
        let beat: [(CGFloat, CGFloat)] = [(0, 0), (0.30, 0), (0.36, 0.25), (0.42, -0.35), (0.50, 0.95),
                                          (0.57, -0.55), (0.63, 0.12), (0.70, 0), (1, 0)]
        let path = NSBezierPath()
        let mid = r.midY
        let amp = r.height * 0.42
        let shift = CGFloat(phase) * r.width
        for copy in 0...1 {
            for (i, (bx, by)) in beat.enumerated() {
                let p = NSPoint(x: r.minX + (bx + CGFloat(copy)) * r.width - shift, y: mid + by * amp)
                if copy == 0 && i == 0 { path.move(to: p) } else { path.line(to: p) }
            }
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: r).addClip()
        health.setStroke()
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
