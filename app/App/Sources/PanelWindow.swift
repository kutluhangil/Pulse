import AppKit
import PulseUI
import SwiftUI

/// Borderless frosted panel that drops down from the status item and
/// keeps its top edge pinned there while its content grows or shrinks.
/// The SwiftUI view only exists while the panel is open, so a closed panel
/// costs no CPU for chart updates.
@MainActor
final class PanelWindow: NSPanel {
    var onClose: (() -> Void)?
    private var anchor: NSRect = .zero
    private let makeRoot: () -> PanelView

    init(makeRoot: @escaping () -> PanelView) {
        self.makeRoot = makeRoot
        super.init(contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 600),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    override var canBecomeKey: Bool { true }

    func show(below anchor: NSRect) {
        self.anchor = anchor
        let host = NSHostingController(rootView: makeRoot().frostedPanel())
        host.sizingOptions = .preferredContentSize
        contentViewController = host
        setContentSize(host.view.fittingSize)
        reposition()
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }

    private func reposition() {
        guard anchor != .zero else { return }
        let size = frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = anchor.minY - 6 - size.height
        setFrameOrigin(NSPoint(x: x, y: max(y, visible.minY + 8)))
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        contentViewController = nil
    }

    override func cancelOperation(_: Any?) {
        orderOut(nil)
        onClose?()
    }
}
