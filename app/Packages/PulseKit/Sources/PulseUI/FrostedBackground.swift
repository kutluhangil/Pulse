import AppKit
import SwiftUI

/// Frosted panel backdrop: a behind-window blur (NSVisualEffectView) under a
/// dark blue tint, like a classic macOS HUD rather than Liquid Glass.
public struct FrostedBackground: NSViewRepresentable {
    public init() {}

    public func makeNSView(context _: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }

    public func updateNSView(_: NSVisualEffectView, context _: Context) {}
}

public extension View {
    /// Rounded frosted panel with the Pulse blue wash, no border.
    func frostedPanel(cornerRadius: CGFloat = Theme.panelRadius) -> some View {
        background {
            ZStack {
                FrostedBackground()
                LinearGradient(stops: [.init(color: Theme.tintTop, location: 0), .init(color: Theme.tintMid, location: 0.45),
                                       .init(color: Theme.tintBottom, location: 1)], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}
