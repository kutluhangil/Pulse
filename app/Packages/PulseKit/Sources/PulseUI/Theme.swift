import AppKit
import PulseCore
import SwiftUI

/// Design tokens. Proportions follow Mole for Mac's Status popover (340 pt
/// wide, compact two-column tiles); the palette is Pulse's own blue.
public enum Theme {
    public static let panelWidth: CGFloat = 340
    public static let panelRadius: CGFloat = 20
    static let panelPadding: CGFloat = 10
    static let gap: CGFloat = 8
    static let tileRadius: CGFloat = 13
    static let tilePadding: CGFloat = 10
    static let chartHeight: CGFloat = 18

    // Frosted backdrop tint over the blur: a coloured top that sinks into near
    // black at the bottom, like Mole's warm-to-dark wash but in blue.
    static let tintTop = Color(red: 0.13, green: 0.25, blue: 0.44).opacity(0.80)
    static let tintMid = Color(red: 0.07, green: 0.12, blue: 0.22).opacity(0.86)
    static let tintBottom = Color(red: 0.04, green: 0.05, blue: 0.08).opacity(0.92)

    static let good = Color(red: 0.40, green: 0.84, blue: 0.62)
    static let warn = Color(red: 0.98, green: 0.76, blue: 0.38)
    static let critical = Color(red: 0.98, green: 0.42, blue: 0.40)
    static let accent = Color(red: 0.42, green: 0.66, blue: 1.00)   // bars, network, meters
    static let line = Color(red: 0.55, green: 0.80, blue: 1.00)     // memory and temperature lines
    static let sun = Color(red: 0.56, green: 0.90, blue: 0.80)

    static let tileFill = Color.white.opacity(0.06)
    static let chipFill = Color.white.opacity(0.10)
    static let track = Color.white.opacity(0.12)

    public static func nsColor(_ level: Level) -> NSColor {
        switch level {
        case .good: .systemGreen
        case .warn: .systemOrange
        case .critical: .systemRed
        }
    }

    public static func color(_ level: Level) -> Color {
        switch level {
        case .good: good
        case .warn: warn
        case .critical: critical
        }
    }

    /// Per-thread bar colour: blue at rest, green when working, amber/red under load.
    static func barColor(_ pct: Double) -> Color {
        switch pct {
        case ..<25: accent
        case ..<60: good
        case ..<85: warn
        default: critical
        }
    }

    static let bigNumber = Font.system(size: 21, weight: .bold).monospacedDigit()
    static let unit = Font.system(size: 12, weight: .semibold)
    static let title = Font.system(size: 11.5, weight: .medium)
    static let caption = Font.system(size: 11.5, weight: .medium).monospacedDigit()
    static let chip = Font.system(size: 10.5, weight: .semibold).monospacedDigit()
    static let row = Font.system(size: 12, weight: .semibold)
    static let rowValue = Font.system(size: 11.5, weight: .medium).monospacedDigit()
}

/// Localized string from this package's catalog.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
