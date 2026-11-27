import AppKit
import PulseCore
import PulseUI

/// Things the tools menu can do that live outside the status item.
struct MenuActions {
    var openSettings: () -> Void
    var showLogs: (Snapshot.Container) -> Void
    var open: (URL) -> Void
    var copySummary: () -> Void
    var reconnect: () -> Void
    var pauseNotifications: (TimeInterval?) -> Void   // nil resumes
    var about: () -> Void
    var quit: () -> Void
}

/// The right-click tools menu (Mole-style: SF Symbol on every row).
@MainActor
enum StatusMenu {
    static func build(monitor: Monitor, prefs: Preferences, actions: MenuActions, openPanel: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let s = monitor.snapshot

        menu.addItem(ActionItem(String(localized: "Open Pulse"), symbol: "rectangle.grid.2x2", action: openPanel))
        menu.addItem(ActionItem(String(localized: "Settings…"), symbol: "gearshape", key: ",", action: actions.openSettings))
        menu.addItem(.separator())

        if let url = prefs.resolvedSSH {
            menu.addItem(ActionItem(String(localized: "SSH into Server"), symbol: "terminal") { actions.open(url) })
        }
        if let url = prefs.resolvedPortainer {
            menu.addItem(ActionItem("Portainer", symbol: "shippingbox") { actions.open(url) })
        }
        if let url = prefs.resolvedCockpit {
            menu.addItem(ActionItem("Cockpit", symbol: "gauge.with.dots.needle.33percent") { actions.open(url) })
        }

        menu.addItem(logsItem(s, actions: actions))
        if let sites = sitesItem(s, actions: actions) { menu.addItem(sites) }
        menu.addItem(.separator())

        menu.addItem(ActionItem(String(localized: "Copy Status Summary"), symbol: "doc.on.doc", action: actions.copySummary))
        menu.addItem(ActionItem(String(localized: "Reconnect"), symbol: "arrow.clockwise", action: actions.reconnect))

        menu.addItem(pauseItem(prefs: prefs, actions: actions))
        menu.addItem(.separator())

        menu.addItem(ActionItem(String(localized: "Check for Updates"), symbol: "arrow.down.circle") {
            actions.open(URL(string: "https://github.com/kutluhangil/Pulse/releases")!)
        })
        menu.addItem(ActionItem(String(localized: "About Pulse"), symbol: "info.circle", action: actions.about))
        menu.addItem(.separator())
        menu.addItem(ActionItem(String(localized: "Quit Pulse"), symbol: "rectangle.portrait.and.arrow.right", key: "q",
                                action: actions.quit))
        return menu
    }

    private static func logsItem(_ s: Snapshot?, actions: MenuActions) -> NSMenuItem {
        let logs = NSMenuItem(title: String(localized: "Container Logs"), action: nil, keyEquivalent: "")
        logs.alwaysShowImage()
        logs.image = symbol("doc.text.magnifyingglass")
        let logsMenu = NSMenu()
        for c in s?.sortedContainers ?? [] {
            let row = ActionItem(c.name, symbol: nil) { actions.showLogs(c) }
            row.image = dot(Theme.nsColor(ContainerStatus(c).level))
            logsMenu.addItem(row)
        }
        logs.submenu = logsMenu
        logs.isEnabled = !(s?.containers.isEmpty ?? true)
        return logs

    }

    private static func sitesItem(_ s: Snapshot?, actions: MenuActions) -> NSMenuItem? {
        guard let probes = s?.probes, !probes.isEmpty else { return nil }
        let sites = NSMenuItem(title: String(localized: "Open Site"), action: nil, keyEquivalent: "")
        sites.alwaysShowImage()
        sites.image = symbol("globe")
        let sitesMenu = NSMenu()
        for p in probes {
            guard let url = URL(string: p.url) else { continue }
            let row = ActionItem("\(p.name)  ·  \(p.ok ? "\(p.ms) ms" : (p.error ?? "down"))", symbol: nil) { actions.open(url) }
            row.image = dot(p.ok ? .systemGreen : .systemRed)
            sitesMenu.addItem(row)
        }
        sites.submenu = sitesMenu
        return sites
    }

    private static func pauseItem(prefs: Preferences, actions: MenuActions) -> NSMenuItem {
        let pause = NSMenuItem(title: String(localized: "Pause Notifications"), action: nil, keyEquivalent: "")
        pause.alwaysShowImage()
        pause.image = symbol(prefs.notificationsPaused ? "bell.slash.fill" : "bell.slash")
        let pauseMenu = NSMenu()
        pauseMenu.addItem(ActionItem(String(localized: "For 1 Hour"), symbol: nil) { actions.pauseNotifications(3600) })
        pauseMenu.addItem(ActionItem(String(localized: "For 8 Hours"), symbol: nil) { actions.pauseNotifications(8 * 3600) })
        pauseMenu.addItem(ActionItem(String(localized: "Until Tomorrow"), symbol: nil) {
            let tomorrow = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400)).addingTimeInterval(8 * 3600)
            actions.pauseNotifications(tomorrow.timeIntervalSinceNow)
        })
        if prefs.notificationsPaused {
            pauseMenu.addItem(.separator())
            let resume = ActionItem(String(localized: "Resume Now"), symbol: nil) { actions.pauseNotifications(nil) }
            pauseMenu.addItem(resume)
        }
        pause.submenu = pauseMenu
        return pause
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private static func dot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in
            color.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
    }
}

extension NSMenuItem {
    /// macOS 27 hides menu item images by default; Pulse's tools menu keeps
    /// them, like Mole's.
    func alwaysShowImage() {
        if #available(macOS 27, *) { preferredImageVisibility = .visible }
    }
}

/// NSMenuItem that runs a closure.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String?, key: String = "", action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        alwaysShowImage()
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
