import AppKit
import SwiftUI

/// Live, looping preview of a menu bar character for the settings row.
struct SpritePreview: View {
    let kind: MenuAnimation

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: kind == .none)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            Image(nsImage: NSImage(size: MenuBarSprites.size, flipped: false) { r in
                MenuBarSprites.draw(kind, phase: phase, health: .systemGreen, in: r)
                return true
            })
        }
        .frame(width: MenuBarSprites.size.width, height: MenuBarSprites.size.height)
        .opacity(kind == .none ? 0 : 1)
    }
}
