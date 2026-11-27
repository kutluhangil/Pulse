import AppKit
import PulseClient
import PulseCore
import PulseUI
import Observation
import ServiceManagement
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences()
    private lazy var monitor = Monitor(config: prefs.serverConfig, alertSettings: prefs.alerts)
    private lazy var notifier = Notifier()
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?
    private var logWindows: [String: NSWindow] = [:]

    static func main() {
        if let i = CommandLine.arguments.firstIndex(of: "--configure") {
            exit(configure(arguments: Array(CommandLine.arguments[(i + 1)...])))
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_: Notification) {
        let open: (URL) -> Void = { [weak self] url in
            self?.statusItem?.closePanel()
            NSWorkspace.shared.open(url)
        }
        let panelActions = PanelActions(
            openSettings: { [weak self] in self?.openSettings() },
            showLogs: { [weak self] in self?.showLogs($0) },
            open: open,
            quit: { NSApp.terminate(nil) }
        )
        let menuActions = MenuActions(
            openSettings: { [weak self] in self?.openSettings() },
            showLogs: { [weak self] in self?.showLogs($0) },
            open: open,
            copySummary: { [weak self] in
                guard let s = self?.monitor.snapshot else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(statusSummary(s), forType: .string)
            },
            reconnect: { [weak self] in self?.monitor.reconnect() },
            pauseNotifications: { [weak self] duration in
                self?.prefs.notificationsPausedUntil = duration.map { Date().addingTimeInterval($0) }
            },
            about: { [weak self] in self?.openSettings(tab: .about) },
            quit: { NSApp.terminate(nil) }
        )
        statusItem = StatusItemController(monitor: monitor, prefs: prefs, panelActions: panelActions, menuActions: menuActions)

        monitor.onAlerts = { [weak self] events in
            guard let self, !prefs.notificationsPaused else { return }
            let host = monitor.snapshot?.host.name ?? prefs.host ?? "Server"
            for e in events { notifier.post(e, host: host) }
        }
        notifier.requestAuthorization()
        monitor.start()
        observeShortcut()

        if prefs.serverConfig == nil {
            openSettings()
        } else if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.statusItem?.openPanel() }
        } else if let i = CommandLine.arguments.firstIndex(of: "--show-settings") {
            let name = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : ""
            openSettings(tab: SettingsTab(rawValue: name) ?? .general)
        } else if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.statusItem?.showMenu() }
        }
    }

    private lazy var hotKey = HotKey { [weak self] in self?.statusItem?.togglePanel() }

    private func observeShortcut() {
        withObservationTracking {
            if prefs.panelShortcut { hotKey.register() } else { hotKey.unregister() }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeShortcut() }
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        statusItem?.togglePanel()
        return false
    }

    // MARK: Windows

    private func openSettings(tab: SettingsTab = .general) {
        statusItem?.closePanel()
        if settingsWindow == nil {
            let launchAtLogin = Binding<Bool>(
                get: { SMAppService.mainApp.status == .enabled },
                set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        NSLog("Pulse: login item change failed: \(error.localizedDescription)")
                    }
                }
            )
            let window = SettingsWindow()
            let view = SettingsView(prefs: prefs, monitor: monitor, launchAtLogin: launchAtLogin, version: Self.version,
                                    initialTab: tab, close: { [weak window] in window?.close() },
                                    restart: { Self.relaunch() })
            window.contentViewController = NSHostingController(rootView: view)
            window.center()
            settingsWindow = window
        } else {
            NotificationCenter.default.post(name: .pulseSelectSettingsTab, object: tab)
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Restart to apply a language change.
    private static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func showLogs(_ container: Snapshot.Container) {
        guard let client = monitor.client else { return }
        statusItem?.closePanel()
        if let existing = logWindows[container.id] {
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: LogsView(client: client, container: container)))
        window.title = container.name
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 480))
        window.isReleasedWhenClosed = false
        window.center()
        logWindows[container.id] = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.logWindows.removeValue(forKey: container.id) }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Scriptable setup: `Pulse --configure <address> [--ssh user@host] [--login] < token`.
    /// The token is read from stdin so it never appears in `ps` or shell history.
    private static func configure(arguments: [String]) -> Int32 {
        guard let address = arguments.first, !address.hasPrefix("--") else {
            FileHandle.standardError.write(Data("usage: Pulse --configure <address> [--ssh user@host] [--login] < token\n".utf8))
            return 64
        }
        let token = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefs = Preferences()
        prefs.address = address
        if !token.isEmpty { prefs.token = token }
        if let s = arguments.firstIndex(of: "--ssh"), s + 1 < arguments.count { prefs.sshTarget = arguments[s + 1] }
        if arguments.contains("--login") {
            do { try SMAppService.mainApp.register() } catch {
                FileHandle.standardError.write(Data("Pulse: could not add login item: \(error.localizedDescription)\n".utf8))
            }
        }
        guard prefs.serverConfig != nil else {
            FileHandle.standardError.write(Data("Pulse: address or token missing\n".utf8))
            return 65
        }
        print("Pulse configured for \(address)")
        return 0
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
