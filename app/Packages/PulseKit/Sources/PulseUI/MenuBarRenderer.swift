import AppKit
import PulseCore

/// Draws the status item: an optional animated character (or a health dot)
/// followed by the chosen metrics, either stacked "label / value" columns
/// (Mole style) or a single line. Always returns an image with non-zero width
/// so the item can never collapse and vanish (Mole issue #1163).
public enum MenuBarRenderer {
    public struct Column: Equatable {
        public let label: String
        public let value: String
        public let level: Level?
    }

    public struct Style: Equatable {
        public var content: MenuContent = .both
        public var animation: MenuAnimation = .server
        public var layout: MenuLayout = .columns

        public init(content: MenuContent = .both, animation: MenuAnimation = .server, layout: MenuLayout = .columns) {
            self.content = content
            self.animation = animation
            self.layout = layout
        }
    }

    public static func columns(for snapshot: Snapshot?, fields: [MenuField], live: Bool) -> [Column] {
        fields.map { field in
            guard live, let s = snapshot else { return Column(label: field.label, value: "—", level: nil) }
            switch field {
            case .temp:
                let t = s.thermal.packageC
                return Column(label: field.label, value: t > 0 ? "\(Int(t.rounded()))°C" : "—", level: Level.temperature(t))
            case .cpu:
                return Column(label: field.label, value: "\(Int(s.cpu.usage.rounded()))%", level: Level.cpu(s.cpu.usage))
            case .mem:
                return Column(label: field.label, value: "\(Int(s.mem.usedPercent.rounded()))%", level: Level.memory(s.mem.usedPercent))
            case .disk:
                let p = s.disks.first?.usedPercent ?? 0
                return Column(label: field.label, value: "\(Int(p.rounded()))%", level: Level.disk(p))
            case .net:
                return Column(label: field.label, value: Format.rate(s.net.rxBps).text.replacingOccurrences(of: " ", with: ""), level: nil)
            case .containers:
                let failing = !s.failingContainers.isEmpty
                return Column(label: field.label, value: "\(s.runningCount)", level: failing ? .critical : nil)
            }
        }
    }

    private static var labelFont: NSFont { NSFont.systemFont(ofSize: 8.5, weight: .semibold) }
    private static var valueFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold) }
    private static var lineLabelFont: NSFont { NSFont.systemFont(ofSize: 9, weight: .semibold) }
    private static var lineValueFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold) }
    private static let height: CGFloat = 22
    private static let dotSize: CGFloat = 7
    private static let spacing: CGFloat = 8

    public static func image(columns allColumns: [Column], dot: NSColor, style: Style = Style(), phase: Double = 0) -> NSImage? {
        let columns = style.content == .icon ? [] : allColumns
        let sprite: MenuAnimation = style.content == .data ? .none : style.animation
        let showDot = sprite == .none || !MenuBarSprites.encodesHealth(sprite)
        let leadWidth = (sprite == .none ? 0 : MenuBarSprites.size.width + 2) + (showDot ? dotSize : 0)

        let cells: [(Column, CGFloat)] = columns.map { col in
            switch style.layout {
            case .columns:
                let lw = (col.label as NSString).size(withAttributes: [.font: labelFont]).width
                let vw = (col.value as NSString).size(withAttributes: [.font: valueFont]).width
                return (col, ceil(max(lw, vw)))
            case .line:
                let lw = (col.label as NSString).size(withAttributes: [.font: lineLabelFont]).width
                let vw = (col.value as NSString).size(withAttributes: [.font: lineValueFont]).width
                return (col, ceil(lw + 3 + vw))
            }
        }
        let dataWidth = cells.map(\.1).reduce(0, +) + spacing * CGFloat(max(cells.count - 1, 0))
        let width = max(leadWidth + (cells.isEmpty ? 0 : spacing) + dataWidth, dotSize)

        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            if sprite != .none {
                let r = NSRect(x: x, y: (height - MenuBarSprites.size.height) / 2,
                               width: MenuBarSprites.size.width, height: MenuBarSprites.size.height)
                MenuBarSprites.draw(sprite, phase: phase, health: dot, in: r)
                x += MenuBarSprites.size.width + 2
            }
            if showDot {
                dot.setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: (height - dotSize) / 2, width: dotSize, height: dotSize)).fill()
                x += dotSize
            }
            if !cells.isEmpty { x += spacing }
            for (col, w) in cells {
                drawCell(col, x: x, width: w, layout: style.layout)
                x += w + spacing
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func valueColor(_ level: Level?) -> NSColor {
        switch level {
        case .warn?: .systemOrange
        case .critical?: .systemRed
        default: .labelColor
        }
    }

    private static func drawCell(_ col: Column, x: CGFloat, width w: CGFloat, layout: MenuLayout) {
        switch layout {
        case .columns:
            let label = NSAttributedString(string: col.label, attributes: [
                .font: labelFont, .foregroundColor: NSColor.secondaryLabelColor, .kern: 0.3,
            ])
            let value = NSAttributedString(string: col.value, attributes: [.font: valueFont, .foregroundColor: valueColor(col.level)])
            label.draw(at: NSPoint(x: x + (w - label.size().width) / 2, y: 11.5))
            value.draw(at: NSPoint(x: x + (w - value.size().width) / 2, y: -0.5))
        case .line:
            let label = NSAttributedString(string: col.label,
                                           attributes: [.font: lineLabelFont, .foregroundColor: NSColor.secondaryLabelColor])
            let value = NSAttributedString(string: col.value, attributes: [.font: lineValueFont, .foregroundColor: valueColor(col.level)])
            label.draw(at: NSPoint(x: x, y: 5.5))
            value.draw(at: NSPoint(x: x + label.size().width + 3, y: 3))
        }
    }

    public static func dotColor(snapshot: Snapshot?, live: Bool) -> NSColor {
        guard live, let s = snapshot else { return .systemGray }
        switch Level.health(s.health.score) {
        case .good: return .systemGreen
        case .warn: return .systemOrange
        case .critical: return .systemRed
        }
    }
}
