import AppKit
import Observation
import PulseCore
import PulseUI
import SwiftUI

/// Owns the menu bar item: the animated character and metrics, the drop-down
/// panel (left click) and the tools menu (right click; swappable in Settings).
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitor: Monitor
    private let prefs: Preferences
    private let actions: MenuActions
    private let updater: Updater
    private let panel: PanelWindow
    private var outsideClickMonitor: Any?
    private var animationTimer: Timer?
    private var phase = 0.0

    /// Shown until the first render and whenever rendering fails, so the item
    /// can never shrink to zero width and vanish.
    private static let fallback: NSImage = {
        let img = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Pulse")!
        img.isTemplate = true
        return img
    }()

    init(monitor: Monitor, prefs: Preferences, updater: Updater, panelActions: PanelActions, menuActions: MenuActions) {
        self.monitor = monitor
        self.prefs = prefs
        self.updater = updater
        actions = menuActions
        panel = PanelWindow { PanelView(monitor: monitor, prefs: prefs, actions: panelActions) }
        super.init()

        item.autosaveName = "PulseStatusItem"
        if let button = item.button {
            button.image = Self.fallback
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Pulse")
        }
        panel.onClose = { [weak self] in self?.panelDidClose() }
        observe()
    }

    // MARK: Rendering

    private func observe() {
        withObservationTracking {
            render()
            updateAnimationTimer()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private var isLive: Bool { monitor.connection == .live && !monitor.isStale }

    private var style: MenuBarRenderer.Style {
        MenuBarRenderer.Style(content: prefs.menuContent, animation: prefs.menuAnimation, layout: prefs.menuLayout)
    }

    private func render() {
        guard let button = item.button else { return }
        let columns = MenuBarRenderer.columns(for: monitor.snapshot, fields: prefs.effectiveMenuFields, live: isLive)
        let dot = MenuBarRenderer.dotColor(snapshot: monitor.snapshot, live: isLive)
        button.image = MenuBarRenderer.image(columns: columns, dot: dot, style: style, phase: phase) ?? Self.fallback
        button.toolTip = monitor.snapshot.map { "\($0.host.name) · \($0.health.score) \($0.health.label)" } ?? "Pulse"
    }

    /// The character runs only while data is live and motion is allowed; with
    /// "follows load" it speeds up as CPU usage rises (one loop per 1.4 s idle,
    /// 0.35 s at full load).
    private func updateAnimationTimer() {
        let animates = prefs.menuContent != .data && prefs.menuAnimation != .none && isLive
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animates else {
            animationTimer?.invalidate()
            animationTimer = nil
            return
        }
        guard animationTimer == nil else { return }
        let interval = 1.0 / 15.0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance(by: interval) }
        }
        timer.tolerance = interval / 3
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func advance(by dt: TimeInterval) {
        let cpu = prefs.animationFollowsLoad ? (monitor.snapshot?.cpu.usage ?? 0) : 0
        let loop = 1.4 - 1.05 * min(max(cpu, 0), 100) / 100
        phase = (phase + dt / loop).truncatingRemainder(dividingBy: 1)
        render()
    }

    // MARK: Clicks

    @objc private func clicked() {
        let right = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if right != prefs.swapClicks {
            showMenu()
        } else {
            togglePanel()
        }
    }

    func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    func openPanel() {
        guard let button = item.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        panel.show(below: anchor)
        item.button?.highlight(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
    }

    func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        panelDidClose()
    }

    private func panelDidClose() {
        item.button?.highlight(false)
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }

    func showMenu() {
        closePanel()
        guard let button = item.button else { return }
        let menu = StatusMenu.build(monitor: monitor, prefs: prefs, updater: updater, actions: actions,
                                    openPanel: { [weak self] in self?.openPanel() })
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }
}
