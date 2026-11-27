import Foundation

public struct AlertSettings: Codable, Sendable, Equatable {
    public var enabled = true
    public var hotC = 85.0
    public var hotHold: TimeInterval = 30
    public var memoryPct = 90.0
    public var memoryHold: TimeInterval = 60
    public var diskPct = 85.0
    public var offlineHold: TimeInterval = 60
    public var containers = true
    public var probes = true
    public var reboot = true
    public var offline = true
    /// After an alert resolves, the same alert stays quiet this long.
    public var cooldown: TimeInterval = 600

    public init() {}

    /// Missing keys (settings saved by an older version) fall back to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        hotC = try c.decodeIfPresent(Double.self, forKey: .hotC) ?? d.hotC
        hotHold = try c.decodeIfPresent(TimeInterval.self, forKey: .hotHold) ?? d.hotHold
        memoryPct = try c.decodeIfPresent(Double.self, forKey: .memoryPct) ?? d.memoryPct
        memoryHold = try c.decodeIfPresent(TimeInterval.self, forKey: .memoryHold) ?? d.memoryHold
        diskPct = try c.decodeIfPresent(Double.self, forKey: .diskPct) ?? d.diskPct
        offlineHold = try c.decodeIfPresent(TimeInterval.self, forKey: .offlineHold) ?? d.offlineHold
        containers = try c.decodeIfPresent(Bool.self, forKey: .containers) ?? d.containers
        probes = try c.decodeIfPresent(Bool.self, forKey: .probes) ?? d.probes
        reboot = try c.decodeIfPresent(Bool.self, forKey: .reboot) ?? d.reboot
        offline = try c.decodeIfPresent(Bool.self, forKey: .offline) ?? d.offline
        cooldown = try c.decodeIfPresent(TimeInterval.self, forKey: .cooldown) ?? d.cooldown
    }
}

public enum AlertKind: String, Sendable, Codable {
    case offline, hot, memory, disk, container, probe, reboot
}

public struct AlertEvent: Sendable, Equatable {
    public enum Phase: Sendable { case fired, resolved }

    public let key: String
    public let kind: AlertKind
    public let phase: Phase
    /// Container or probe name; empty for machine-wide alerts.
    public let subject: String
    /// Measured value when it fired (°C, %), 0 when not applicable.
    public let value: Double
}

/// Turns a stream of snapshots into fire/resolve events with hold times
/// (condition must persist), hysteresis (one alert per episode) and a
/// cooldown after recovery. Pure logic: the app feeds it and posts
/// notifications for the returned events.
public struct AlertEngine: Sendable {
    public var settings: AlertSettings

    private var pendingSince: [String: Date] = [:]
    private var active: [String: AlertKind] = [:]
    private var resolvedAt: [String: Date] = [:]
    private var probeFailures: [String: (count: Int, lastCheck: Date)] = [:]

    public init(settings: AlertSettings = AlertSettings()) {
        self.settings = settings
    }

    public var activeKeys: Set<String> { Set(active.keys) }

    public mutating func evaluate(_ snapshot: Snapshot?, connected: Bool, now: Date) -> [AlertEvent] {
        guard settings.enabled else { return [] }
        var events: [AlertEvent] = []
        func check(_ key: String, _ kind: AlertKind, _ on: Bool, hold: TimeInterval = 0, subject: String = "", value: Double = 0) {
            if let e = step(key: key, kind: kind, on: on, hold: hold, subject: subject, value: value, now: now) {
                events.append(e)
            }
        }

        check("offline", .offline, settings.offline && (!connected || snapshot == nil), hold: settings.offlineHold)
        guard connected, let s = snapshot else { return events }

        check("hot", .hot, s.thermal.packageC >= settings.hotC, hold: settings.hotHold, value: s.thermal.packageC)
        check("memory", .memory, s.mem.usedPercent >= settings.memoryPct, hold: settings.memoryHold, value: s.mem.usedPercent)
        if let d = s.disks.first {
            check("disk", .disk, d.usedPercent >= settings.diskPct, value: d.usedPercent)
        }
        if settings.reboot {
            check("reboot", .reboot, s.system.rebootRequired)
        }

        if settings.containers {
            var seen = Set<String>()
            for c in s.containers {
                let key = "container:" + c.name
                seen.insert(key)
                check(key, .container, ContainerStatus(c).isFailing, subject: c.name)
            }
            // A failing container that disappeared (removed) is resolved.
            for key in active.keys where key.hasPrefix("container:") && !seen.contains(key) {
                check(key, .container, false, subject: String(key.dropFirst("container:".count)))
            }
        }

        if settings.probes {
            for p in s.probes where p.checked {
                let key = "probe:" + p.name
                var f = probeFailures[p.name] ?? (0, .distantPast)
                if p.checkedAt != f.lastCheck {
                    f = (p.ok ? 0 : f.count + 1, p.checkedAt)
                    probeFailures[p.name] = f
                }
                // Two consecutive failed checks before alerting.
                check(key, .probe, f.count >= 2, subject: p.name)
            }
        }
        return events
    }

    private mutating func step(key: String, kind: AlertKind, on: Bool, hold: TimeInterval,
                               subject: String, value: Double, now: Date) -> AlertEvent? {
        if on {
            if active[key] != nil { return nil }
            let since = pendingSince[key] ?? now
            pendingSince[key] = since
            guard now.timeIntervalSince(since) >= hold else { return nil }
            if let r = resolvedAt[key], now.timeIntervalSince(r) < settings.cooldown { return nil }
            active[key] = kind
            return AlertEvent(key: key, kind: kind, phase: .fired, subject: subject, value: value)
        }
        pendingSince[key] = nil
        guard active.removeValue(forKey: key) != nil else { return nil }
        resolvedAt[key] = now
        return AlertEvent(key: key, kind: kind, phase: .resolved, subject: subject, value: value)
    }
}
