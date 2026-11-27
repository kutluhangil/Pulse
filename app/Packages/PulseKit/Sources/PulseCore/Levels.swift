import Foundation

/// Traffic-light level shared by tiles, chips and the menu bar dot.
/// Thresholds match the agent's health score (agent/internal/health).
public enum Level: Int, Sendable, Comparable {
    case good, warn, critical

    public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

    public static func cpu(_ pct: Double) -> Level { pct < 50 ? .good : pct < 85 ? .warn : .critical }
    public static func temperature(_ c: Double) -> Level { c < 65 ? .good : c < 85 ? .warn : .critical }
    public static func memory(_ pct: Double) -> Level { pct < 70 ? .good : pct < 88 ? .warn : .critical }
    public static func disk(_ pct: Double) -> Level { pct < 80 ? .good : pct < 93 ? .warn : .critical }
    public static func health(_ score: Int) -> Level { score >= 85 ? .good : score >= 65 ? .warn : .critical }
}

/// Words shown under the big numbers, as in Mole ("idle · 12 cores").
public enum Activity: String, Sendable {
    case idle, normal, busy, high

    public static func cpu(_ pct: Double) -> Activity {
        switch pct {
        case ..<10: .idle
        case ..<50: .normal
        case ..<85: .busy
        default: .high
        }
    }
}

public enum ContainerStatus: Sendable, Equatable {
    case healthy, running, starting, stopped, failing

    public init(_ c: Snapshot.Container) {
        switch c.state {
        case "restarting", "dead": self = .failing
        case "exited": self = c.exitCode == 0 ? .stopped : .failing
        case "created", "paused": self = .stopped
        default:
            switch c.health {
            case "unhealthy": self = .failing
            case "starting": self = .starting
            case "healthy": self = .healthy
            default: self = .running
            }
        }
    }

    public var level: Level {
        switch self {
        case .healthy, .running: .good
        case .starting, .stopped: .warn
        case .failing: .critical
        }
    }

    public var isFailing: Bool { self == .failing }
}

public extension Snapshot {
    /// Containers needing attention first, then by CPU.
    var sortedContainers: [Container] {
        containers.sorted { a, b in
            let la = ContainerStatus(a).level, lb = ContainerStatus(b).level
            if la != lb { return la > lb }
            if a.cpu != b.cpu { return a.cpu > b.cpu }
            return a.name < b.name
        }
    }

    var runningCount: Int { containers.filter { $0.state == "running" }.count }
    var failingContainers: [Container] { containers.filter { ContainerStatus($0).isFailing } }
    var downProbes: [Probe] { probes.filter { $0.checked && !$0.ok } }

    /// Count shown in the footer "Alerts" column.
    var attentionCount: Int {
        failingContainers.count + downProbes.count + (system.rebootRequired ? 1 : 0)
            + (Level.temperature(thermal.packageC) == .critical ? 1 : 0)
            + ((disks.first.map { Level.disk($0.usedPercent) } ?? .good) == .critical ? 1 : 0)
    }
}

/// Short container name: drops the compose project prefix and the replica
/// suffix ("perde-test-jellyfin-1" in project "perde-test" -> "jellyfin").
public func displayName(_ c: Snapshot.Container) -> String {
    var name = c.name
    if !c.project.isEmpty, name.hasPrefix(c.project + "-") {
        name.removeFirst(c.project.count + 1)
    }
    if let dash = name.lastIndex(of: "-"), Int(name[name.index(after: dash)...]) != nil, dash != name.startIndex {
        name = String(name[..<dash])
    }
    return name.isEmpty ? c.name : name
}
