import PulseClient
import PulseCore
import SwiftUI
import UserNotifications

/// Settings window content: frosted backdrop, pill tabs, one row per option.
public struct SettingsView: View {
    @Bindable var prefs: Preferences
    let monitor: Monitor
    @Binding var launchAtLogin: Bool
    let version: String
    let close: () -> Void
    let restart: () -> Void

    @State private var tab: SettingsTab
    @State private var address = ""
    @State private var token = ""
    @State private var testResult: (ok: Bool, text: String)?
    @State private var testing = false
    @State private var notificationsAllowed: Bool?
    @State private var languageAtOpen: AppLanguage?

    public init(prefs: Preferences, monitor: Monitor, launchAtLogin: Binding<Bool>, version: String,
                initialTab: SettingsTab = .general, close: @escaping () -> Void, restart: @escaping () -> Void) {
        self.prefs = prefs
        self.monitor = monitor
        self._launchAtLogin = launchAtLogin
        self.version = version
        self.close = close
        self.restart = restart
        self._tab = State(initialValue: initialTab)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PillTabs(selection: $tab)
                HStack {
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.10), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 0) {
                    switch tab {
                    case .general: general
                    case .server: server
                    case .menuBar: menuBar
                    case .alerts: alerts
                    case .about: about
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.automatic)
        }
        .frame(width: 600, height: 640)
        .frostedPanel(cornerRadius: 22)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear {
            address = prefs.address
            token = prefs.token
            languageAtOpen = prefs.language
            refreshNotificationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseSelectSettingsTab)) { note in
            if let t = note.object as? SettingsTab { tab = t }
        }
    }
}

// MARK: General

extension SettingsView {

    @ViewBuilder private var general: some View {
        SettingRow(title: L("Notifications"), detail: L("Alerts arrive as macOS notifications")) {
            switch notificationsAllowed {
            case true?: StatusBadge(ok: true, text: L("Granted"))
            case false?:
                PillButton(title: L("Allow")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            case nil: ProgressView().controlSize(.small)
            }
        }
        RowDivider()
        SettingRow(title: L("Language"), detail: L("Follow system, restart Pulse after changing")) {
            HStack(spacing: 8) {
                if let languageAtOpen, languageAtOpen != prefs.language {
                    PillButton(title: L("Restart"), action: restart)
                }
                PillPicker(selection: $prefs.language, options: [
                    (.system, L("Follow system")), (.en, "English"), (.tr, "Türkçe"),
                ])
            }
        }
        RowDivider()
        SettingRow(title: L("Launch at login"), detail: L("Server status is in the menu bar when you reach the desktop")) {
            GreenToggle(isOn: $launchAtLogin)
        }
        RowDivider()
        SettingRow(title: L("Panel shortcut"), detail: L("⌃⌥⌘P shows or hides the panel from any app")) {
            GreenToggle(isOn: $prefs.panelShortcut)
        }
        RowDivider()
        SettingRow(title: L("Swap left and right clicks"), detail: L("Left-click opens the tools menu, right-click opens the panel")) {
            GreenToggle(isOn: $prefs.swapClicks)
        }
        RowDivider()
        SettingRow(title: L("Pause notifications"), detail: pauseDetail) {
            PillPicker(selection: Binding(get: { pausedHoursOption }, set: { v in
                prefs.notificationsPausedUntil = v == 0 ? nil : Date().addingTimeInterval(Double(v) * 3600)
            }), options: [(0, L("Off")), (1, L("1 hour")), (8, L("8 hours")), (24, L("24 hours"))])
        }
    }

    /// Picker value for the current pause: the smallest option covering what is left.
    private var pausedHoursOption: Int {
        guard prefs.notificationsPaused, let until = prefs.notificationsPausedUntil else { return 0 }
        let hours = until.timeIntervalSinceNow / 3600
        return [1, 8, 24].first { Double($0) >= hours - 0.01 } ?? 24
    }

    private var pauseDetail: String {
        guard prefs.notificationsPaused, let until = prefs.notificationsPausedUntil else {
            return L("Silence alerts for a while, the panel keeps updating")
        }
        return L("Paused until \(until.formatted(date: .omitted, time: .shortened))")
    }

    private func refreshNotificationStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        }
    }
}

// MARK: Server

extension SettingsView {

    @ViewBuilder private var server: some View {
        SettingRow(title: L("Agent address"), detail: L("Host and port on your tailnet")) {
            RowField(text: $address, prompt: "server.tailnet.ts.net:9123")
        }
        RowDivider()
        SettingRow(title: L("Token"), detail: L("From ./deploy/deploy.sh --copy-token, stays on this Mac")) {
            RowField(text: $token, prompt: "••••••••", secure: true)
        }
        RowDivider()
        SettingRow(title: L("Connection"), detail: connectionDetail) {
            HStack(spacing: 8) {
                if testing { ProgressView().controlSize(.small) }
                PillButton(title: L("Test"), disabled: testing || !canTest) {
                    Task { await test() }
                }
                PillButton(title: L("Save"), disabled: address == prefs.address && token == prefs.token) { save() }
            }
        }
        RowDivider()
        SettingRow(title: "SSH", detail: L("Opened from the panel and the tools menu")) {
            RowField(text: $prefs.sshTarget, prompt: "user@server")
        }
        RowDivider()
        SettingRow(title: "Portainer", detail: L("Leave empty to use port 9443 on the agent host")) {
            RowField(text: $prefs.portainerURL, prompt: prefs.resolvedPortainer?.absoluteString ?? "https://…")
        }
        RowDivider()
        SettingRow(title: "Cockpit", detail: L("Leave empty to use port 9090 on the agent host")) {
            RowField(text: $prefs.cockpitURL, prompt: prefs.resolvedCockpit?.absoluteString ?? "https://…")
        }
        if let s = monitor.snapshot {
            RowDivider()
            SettingRow(title: s.host.name, detail: "\(s.host.os) · \(s.host.kernel) · Docker \(s.docker.version)") {
                Text(L("Agent \(s.host.agentVersion)")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
    }

    private var canTest: Bool {
        ServerConfig(address: address, token: token).baseURL != nil && !token.isEmpty
    }

    private var connectionDetail: String {
        if let testResult { return testResult.text }
        switch monitor.connection {
        case .live: return L("Live, one update per second")
        case .connecting: return L("Connecting…")
        case .offline(let reason): return reason
        case .unauthorized: return L("Token rejected")
        case .notConfigured: return L("Not set up")
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        let client = AgentClient(config: ServerConfig(address: address, token: token))
        do {
            let s = try await client.snapshot()
            testResult = (true, L("\(s.host.name) · health \(s.health.score)"))
        } catch {
            testResult = (false, error as? AgentError == .unauthorized ? L("Token rejected") : Monitor.describe(error))
        }
    }

    private func save() {
        prefs.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        prefs.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        testResult = nil
        monitor.update(config: prefs.serverConfig)
    }
}

// MARK: Menu bar

extension SettingsView {

    private var metricOptions: [(MenuField?, String)] {
        MenuField.allCases.map { ($0, fieldName($0)) }
    }

    @ViewBuilder private var menuBar: some View {
        SettingRow(title: L("Menu bar content"), detail: L("Choose an icon, live data, or both")) {
            PillPicker(selection: $prefs.menuContent, options: [
                (.icon, L("Icon")), (.data, L("Live data")), (.both, L("Both")),
            ])
        }
        RowDivider()
        SettingRow(title: L("Animated icon"), detail: L("A little character that runs while the server is live")) {
            HStack(spacing: 10) {
                SpritePreview(kind: prefs.menuAnimation)
                PillPicker(selection: $prefs.menuAnimation, options: [
                    (.server, L("Server")), (.cat, L("Cat")), (.pulse, L("Heartbeat")), (.none, L("None")),
                ])
            }
        }
        RowDivider()
        SettingRow(title: L("Speed follows CPU load"), detail: L("Runs faster as the server gets busier")) {
            GreenToggle(isOn: $prefs.animationFollowsLoad)
        }
        RowDivider()
        SettingRow(title: L("Data layout"), detail: L("Columns or a single line")) {
            PillPicker(selection: $prefs.menuLayout, options: [(.columns, L("Columns")), (.line, L("Single line"))])
        }
        RowDivider()
        SettingRow(title: L("Show live network speed"), detail: L("Adds the current download speed")) {
            GreenToggle(isOn: $prefs.showNetworkSpeed)
        }
        ForEach(0..<Preferences.maxMenuFields, id: \.self) { slot in
            RowDivider()
            SettingRow(title: slotTitle(slot), detail: slotDetail(slot)) {
                PillPicker(selection: Binding<MenuField?>(
                    get: { slot < prefs.menuFields.count ? prefs.menuFields[slot] : nil },
                    set: { prefs.setMenuField($0, at: min(slot, prefs.menuFields.count)) }
                ), options: metricOptions + [(nil, L("Hidden"))])
            }
        }
    }

    private func slotTitle(_ slot: Int) -> String {
        [L("First status metric"), L("Second status metric"), L("Third status metric")][slot]
    }

    private func slotDetail(_ slot: Int) -> String {
        [L("Choose temperature, CPU, memory or another metric"), L("Choose another metric, or leave this slot hidden"),
         L("Add one more metric")][slot]
    }

    private func fieldName(_ f: MenuField) -> String {
        switch f {
        case .temp: L("CPU temperature")
        case .cpu: L("CPU usage")
        case .mem: L("Memory usage")
        case .disk: L("Disk usage")
        case .net: L("Download speed")
        case .containers: L("Running containers")
        }
    }
}

// MARK: Alerts

extension SettingsView {

    @ViewBuilder private var alerts: some View {
        SettingRow(title: L("Send notifications"), detail: L("Turn every Pulse alert on or off")) {
            GreenToggle(isOn: alertBinding(\.enabled))
        }
        Group {
            RowDivider()
            SettingRow(title: L("CPU temperature"), detail: L("Alert after 30 s above this")) {
                PillPicker(selection: alertBinding(\.hotC), options: [70, 75, 80, 85, 90, 95].map { (Double($0), "\($0) °C") })
            }
            RowDivider()
            SettingRow(title: L("Memory"), detail: L("Alert after a minute above this")) {
                PillPicker(selection: alertBinding(\.memoryPct), options: [75, 80, 85, 90, 95].map { (Double($0), "\($0) %") })
            }
            RowDivider()
            SettingRow(title: L("Disk"), detail: L("Alert when the disk passes this")) {
                PillPicker(selection: alertBinding(\.diskPct), options: [70, 75, 80, 85, 90, 95].map { (Double($0), "\($0) %") })
            }
            RowDivider()
            SettingRow(title: L("Containers"), detail: L("A container stops or turns unhealthy")) {
                GreenToggle(isOn: alertBinding(\.containers))
            }
            RowDivider()
            SettingRow(title: L("Sites"), detail: L("A site fails two checks in a row")) {
                GreenToggle(isOn: alertBinding(\.probes))
            }
            RowDivider()
            SettingRow(title: L("Server unreachable"), detail: L("No data from the agent for a minute")) {
                GreenToggle(isOn: alertBinding(\.offline))
            }
            RowDivider()
            SettingRow(title: L("Restart required"), detail: L("Installed updates are waiting for a reboot")) {
                GreenToggle(isOn: alertBinding(\.reboot))
            }
        }
        .disabled(!prefs.alerts.enabled)
        .opacity(prefs.alerts.enabled ? 1 : 0.5)
    }

    private func alertBinding<T>(_ path: WritableKeyPath<AlertSettings, T>) -> Binding<T> {
        Binding(
            get: { prefs.alerts[keyPath: path] },
            set: { value in
                prefs.alerts[keyPath: path] = value
                monitor.alertSettings = prefs.alerts
            }
        )
    }
}

// MARK: About

extension SettingsView {

    private var about: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Pulse").font(.system(size: 24, weight: .bold))
            Text(L("Version \(version)")).foregroundStyle(.secondary)
            if let agent = monitor.snapshot?.host.agentVersion {
                Text(L("Agent \(agent)")).font(.caption).foregroundStyle(.secondary)
            }
            Text(L("Live monitor for your home server. Free software under GPL-3.0."))
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Text(L("Health score adapted from Mole by tw93."))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                PillButton(title: "GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/kutluhangil/Pulse")!) }
                PillButton(title: "Mole") { NSWorkspace.shared.open(URL(string: "https://github.com/tw93/Mole")!) }
            }
            .padding(.top, 4)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }
}

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
