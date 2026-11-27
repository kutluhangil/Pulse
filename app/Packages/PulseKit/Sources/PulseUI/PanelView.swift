import PulseCore
import SwiftUI

/// Callbacks the host app provides (windows, URLs, quitting live in AppKit).
public struct PanelActions {
    public var openSettings: () -> Void
    public var showLogs: (Snapshot.Container) -> Void
    public var open: (URL) -> Void
    public var quit: () -> Void

    public init(openSettings: @escaping () -> Void, showLogs: @escaping (Snapshot.Container) -> Void,
                open: @escaping (URL) -> Void, quit: @escaping () -> Void) {
        self.openSettings = openSettings
        self.showLogs = showLogs
        self.open = open
        self.quit = quit
    }
}

public struct PanelView: View {
    let monitor: Monitor
    let prefs: Preferences
    let actions: PanelActions

    public init(monitor: Monitor, prefs: Preferences, actions: PanelActions) {
        self.monitor = monitor
        self.prefs = prefs
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            if let s = monitor.snapshot {
                HeaderView(snapshot: s, connection: monitor.connection, stale: monitor.isStale)
                if monitor.connection != .live {
                    ConnectionBanner(monitor: monitor, actions: actions)
                }
                MetricsGrid(snapshot: s, history: monitor.history, latencyMs: monitor.latencyMs)
                    .opacity(monitor.isStale ? 0.55 : 1)
                if !s.probes.isEmpty { SitesSection(probes: s.probes) }
                ContainersSection(snapshot: s, prefs: prefs, actions: actions)
                FooterView(snapshot: s, prefs: prefs, actions: actions)
            } else {
                EmptyStateView(monitor: monitor, actions: actions)
            }
        }
        .padding(Theme.panelPadding)
        .frame(width: Theme.panelWidth)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Header

struct HeaderView: View {
    let snapshot: Snapshot
    let connection: Monitor.Connection
    let stale: Bool

    var body: some View {
        let level = Level.health(snapshot.health.score)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: icon(level))
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(level == .good ? Theme.sun : Theme.color(level))
                    .symbolEffect(.pulse, isActive: level == .critical)
                Text("\(snapshot.health.score)")
                    .font(.system(size: 26, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText())
                Text(healthLabel(snapshot.health.score))
                    .font(.system(size: 14.5, weight: .semibold))
                    .padding(.top, 3)
                Spacer()
                LiveDot(connection: connection, stale: stale)
            }
            .help(reasonsText.isEmpty ? healthLabel(snapshot.health.score) : reasonsText)
            HStack(spacing: 5) {
                HeaderChip(text: shortCPU(snapshot.host.cpuModel))
                HeaderChip(text: Format.ramSize(snapshot.host.memTotal))
                HeaderChip(text: shortOS(snapshot.host.os))
                HeaderChip(text: uptimeText(snapshot.host.uptimeSec))
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private var reasonsText: String {
        snapshot.health.reasons.map(reasonText).joined(separator: " · ")
    }

    private func icon(_ level: Level) -> String {
        switch level {
        case .good: "sun.max"
        case .warn: "cloud.sun"
        case .critical: "exclamationmark.triangle"
        }
    }
}

struct HeaderChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary.opacity(0.85))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Theme.chipFill, in: .rect(cornerRadius: 5))
    }
}

/// Small connection light in the header corner; words only in the tooltip.
struct LiveDot: View {
    let connection: Monitor.Connection
    let stale: Bool

    var body: some View {
        let (text, color): (String, Color) = switch connection {
        case .live where !stale: (L("Live"), Theme.good)
        case .live, .connecting: (L("Connecting"), Theme.warn)
        case .unauthorized: (L("Token rejected"), Theme.critical)
        case .offline: (L("Offline"), Theme.critical)
        case .notConfigured: (L("Not set up"), Theme.warn)
        }
        Circle().fill(color).frame(width: 6, height: 6)
            .padding(6)
            .help(text)
            .accessibilityLabel(text)
    }
}

struct ConnectionBanner: View {
    let monitor: Monitor
    let actions: PanelActions

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(Theme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(reason).font(.system(size: 12, weight: .semibold))
                if let last = monitor.lastUpdate {
                    Text(L("Last data \(last.formatted(.relative(presentation: .named)))"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(L("Retry")) { monitor.reconnect() }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(10)
        .background(Theme.warn.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    private var reason: String {
        switch monitor.connection {
        case .offline(let r): r
        case .unauthorized: L("The agent rejected the token")
        case .connecting: L("Reconnecting…")
        default: L("No data for a while")
        }
    }
}

// MARK: - Metric tiles

struct MetricsGrid: View {
    let snapshot: Snapshot
    let history: ChartHistory
    let latencyMs: Double?

    private let columns = [GridItem(.flexible(), spacing: Theme.gap), GridItem(.flexible(), spacing: Theme.gap)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.gap) {
            cpu
            temperature
            memory
            disk
            network
            fanOrIO
        }
    }

    private var recent: ArraySlice<HistoryPoint> { history.recent(90) }

    private var cpu: some View {
        let c = snapshot.cpu
        let temp = snapshot.thermal.packageC
        return Tile(icon: "cpu", title: "CPU",
                    chip: temp > 0 ? "\(Format.percent(temp))°C" : nil,
                    chipLevel: temp > 0 ? Level.temperature(temp) : nil) {
            BigValue(number: Format.percent(c.usage), unit: "%")
            ThreadBars(values: c.perThread)
            Caption(text: "\(activityText(Activity.cpu(c.usage))) · \(L("\(snapshot.host.threads) threads"))")
        }
        .help(L("Load average 1/5/15 min: \(c.load.map { Format.number($0, locale: .current, digits: 2) }.joined(separator: " / "))"))
    }

    private var temperature: some View {
        let t = snapshot.thermal
        let level = Level.temperature(t.packageC)
        return Tile(icon: "thermometer.medium", title: L("Temp"),
                    chip: temperatureWord(level), chipLevel: level) {
            BigValue(number: t.packageC > 0 ? Format.percent(t.packageC) : "–", unit: "°C")
            Sparkline(series: [.init(id: "temp", color: Theme.line, values: recent.map(\.temp))], domain: 25...100)
            Caption(text: t.coresC.isEmpty ? L("No sensor") : L("\(t.coresC.count) cores · max \(Format.percent(t.coresC.max() ?? 0))°C"))
        }
    }

    private var memory: some View {
        let m = snapshot.mem
        let level = Level.memory(m.usedPercent)
        return Tile(icon: "memorychip", title: "MEM", chip: memoryWord(level), chipLevel: level) {
            BigValue(number: Format.percent(m.usedPercent), unit: "%")
            Sparkline(series: [.init(id: "mem", color: Theme.line, values: recent.map(\.mem))], domain: 0...100, filled: true)
            Caption(text: "\(Format.bytes(m.used).text) / \(Format.bytes(m.total).text)")
        }
        .help(L("Swap \(Format.bytes(m.swapUsed).text) of \(Format.bytes(m.swapTotal).text) · cache \(Format.bytes(m.cached).text)"))
    }

    @ViewBuilder private var disk: some View {
        if let d = snapshot.disks.first {
            let level = Level.disk(d.usedPercent)
            let free = Format.bytes(d.free)
            Tile(icon: "internaldrive", title: L("Free space"), chip: Format.bytes(d.total).text,
                 chipLevel: level == .good ? nil : level) {
                BigValue(number: free.number, unit: free.unit)
                Meter(fraction: d.usedPercent / 100, color: level == .good ? Theme.accent : Theme.color(level))
                Caption(text: L("\(Format.bytes(d.used).text) used · \(Format.percent(d.usedPercent))%"))
            }
            .help(L("Disk read \(Format.rate(d.readBps).text) · write \(Format.rate(d.writeBps).text)"))
        }
    }

    private var network: some View {
        let n = snapshot.net
        let down = Format.rate(n.rxBps)
        return Tile(icon: "globe", title: L("Network"), chip: linkKind(n)) {
            BigValue(number: down.number, unit: down.unit)
            Sparkline(series: [
                .init(id: "rx", color: Theme.accent, values: recent.map { Double($0.rx) }),
                .init(id: "tx", color: Theme.good, values: recent.map { Double($0.tx) }),
            ])
            Caption(text: L("Upload \(Format.rate(n.txBps).text)"), trailing: lagText)
        }
        .help(L("\(linkSpeed(n)) \(n.iface) · received \(Format.bytes(n.rxTotal).text) · sent \(Format.bytes(n.txTotal).text)"))
    }

    @ViewBuilder private var fanOrIO: some View {
        if let f = snapshot.fan {
            Tile(icon: "fan", title: L("Fan"), chip: L("Speed \(Format.percent(f.speedFraction * 100))%")) {
                BigValue(number: Format.rpm(f.rpm), unit: "RPM")
                Text(L("Managed automatically"))
                    .font(Theme.caption).foregroundStyle(.primary.opacity(0.85))
                    .frame(height: Theme.chartHeight, alignment: .leading)
                HStack(spacing: 5) {
                    FanPill(text: L("Auto"), active: true)
                    FanPill(text: "Min", active: false).help("\(Format.rpm(f.min)) RPM")
                    FanPill(text: "Max", active: false).help("\(Format.rpm(f.max)) RPM")
                }
                .help(L("\(f.label) fan · \(Format.rpm(f.min))–\(Format.rpm(f.max)) RPM. Pulse only reads it; the server controls the fan."))
            }
        } else {
            let d = snapshot.disks.first
            let read = Format.rate(d?.readBps ?? 0)
            Tile(icon: "arrow.up.arrow.down", title: L("Disk I/O")) {
                BigValue(number: read.number, unit: read.unit)
                Sparkline(series: [
                    .init(id: "r", color: Theme.accent, values: recent.map { Double($0.dr) }),
                    .init(id: "w", color: Theme.line, values: recent.map { Double($0.dw) }),
                ])
                Caption(text: L("Write \(Format.rate(d?.writeBps ?? 0).text)"))
            }
        }
    }

    private var lagText: String? {
        guard let ms = latencyMs else { return nil }
        return ms < 60 ? L("Low Lag") : ms < 200 ? L("\(Int(ms)) ms") : L("High Lag")
    }

    private func linkKind(_ n: Snapshot.Net) -> String {
        n.iface.hasPrefix("wl") ? "Wi-Fi" : "Ethernet"
    }

    private func linkSpeed(_ n: Snapshot.Net) -> String {
        guard n.speedMbps > 0 else { return "" }
        return n.speedMbps >= 1000 ? "\(n.speedMbps / 1000) Gb/s" : "\(n.speedMbps) Mb/s"
    }
}

// MARK: - Sites

struct SitesSection: View {
    let probes: [Snapshot.Probe]

    var body: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "cloud").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                ForEach(probes) { p in
                    HStack(spacing: 5) {
                        StatusDot(level: !p.checked ? .warn : p.ok ? .good : .critical)
                        Text(p.name).font(Theme.row).lineLimit(1)
                        Text(p.checked ? (p.ok ? "\(p.ms) ms" : (p.error ?? "HTTP \(p.status)")) : "…")
                            .font(Theme.rowValue)
                            .foregroundStyle(p.ok || !p.checked ? Color.secondary : Theme.critical)
                            .lineLimit(1)
                    }
                    .help(p.url)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }
}

struct FanPill: View {
    let text: String
    let active: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(active ? Theme.accent.opacity(0.28) : Theme.chipFill, in: .capsule)
    }
}
