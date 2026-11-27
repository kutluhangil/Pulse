import Foundation

/// Mirrors `agent/internal/model/snapshot.go`. Keep both in sync (see docs/API.md).
public struct Snapshot: Codable, Sendable, Equatable {
    public static let supportedVersion = 1

    public var v: Int
    public var ts: Date
    public var host: Host
    public var health: Health
    public var cpu: CPU
    public var thermal: Thermal
    public var fan: Fan?
    public var mem: Mem
    public var disks: [Disk]
    public var net: Net
    public var containers: [Container]
    public var docker: DockerState
    public var probes: [Probe]
    public var system: SystemInfo

    public struct Host: Codable, Sendable, Equatable {
        public var name: String
        public var cpuModel: String
        public var cores: Int
        public var threads: Int
        public var memTotal: UInt64
        public var os: String
        public var kernel: String
        public var uptimeSec: UInt64
        public var agentVersion: String
    }

    public struct Health: Codable, Sendable, Equatable {
        public var score: Int
        public var label: String
        public var reasons: [String]
    }

    public struct CPU: Codable, Sendable, Equatable {
        public var usage: Double
        public var perThread: [Double]
        public var load: [Double]
        public var freqMHz: Double
        public var ioWait: Double
    }

    public struct Thermal: Codable, Sendable, Equatable {
        public var packageC: Double
        public var coresC: [Double]
        public var critC: Double
    }

    public struct Fan: Codable, Sendable, Equatable {
        public var label: String
        public var rpm: Int
        public var min: Int
        public var max: Int

        /// Speed above the idle floor, 0...1 (Mole's "Speed 20%").
        public var speedFraction: Double {
            guard max > min else { return 0 }
            return Swift.min(1, Swift.max(0, Double(rpm - min) / Double(max - min)))
        }
    }

    public struct Mem: Codable, Sendable, Equatable {
        public var total: UInt64
        public var used: UInt64
        public var available: UInt64
        public var cached: UInt64
        public var swapTotal: UInt64
        public var swapUsed: UInt64

        public var usedPercent: Double { total == 0 ? 0 : Double(used) / Double(total) * 100 }
    }

    public struct Disk: Codable, Sendable, Equatable {
        public var mount: String
        public var device: String
        public var total: UInt64
        public var used: UInt64
        public var free: UInt64
        public var readBps: UInt64
        public var writeBps: UInt64

        /// Same definition as `df`: blocks reserved for root are excluded.
        public var usedPercent: Double {
            let usable = used + free
            return usable == 0 ? 0 : Double(used) / Double(usable) * 100
        }
    }

    public struct Net: Codable, Sendable, Equatable {
        public var iface: String
        public var speedMbps: Int
        public var rxBps: UInt64
        public var txBps: UInt64
        public var rxTotal: UInt64
        public var txTotal: UInt64
    }

    public struct Container: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var project: String
        public var image: String
        public var state: String
        public var health: String
        public var statusText: String
        public var cpu: Double
        public var memBytes: UInt64
        public var memLimit: UInt64
        public var createdAt: Date
        public var exitCode: Int
        public var restartCount: Int
    }

    public struct DockerState: Codable, Sendable, Equatable {
        public var available: Bool
        public var version: String
        public var error: String?
    }

    public struct Probe: Codable, Sendable, Equatable, Identifiable {
        public var name: String
        public var url: String
        public var ok: Bool
        public var status: Int
        public var ms: Int
        public var error: String?
        public var checkedAt: Date
        public var id: String { name }
        public var checked: Bool { checkedAt.timeIntervalSince1970 > 0 }
    }

    public struct SystemInfo: Codable, Sendable, Equatable {
        public var aptUpdates: Int
        public var securityUpdates: Int
        public var rebootRequired: Bool
    }
}

public struct HistoryPoint: Codable, Sendable, Equatable {
    public var t: Int64
    public var cpu: Double
    public var mem: Double
    public var temp: Double
    public var rx: UInt64
    public var tx: UInt64
    public var dr: UInt64
    public var dw: UInt64

    public init(t: Int64, cpu: Double, mem: Double, temp: Double, rx: UInt64, tx: UInt64, dr: UInt64, dw: UInt64) {
        self.t = t; self.cpu = cpu; self.mem = mem; self.temp = temp
        self.rx = rx; self.tx = tx; self.dr = dr; self.dw = dw
    }

    public init(_ s: Snapshot) {
        self.init(t: Int64(s.ts.timeIntervalSince1970), cpu: s.cpu.usage, mem: s.mem.usedPercent,
                  temp: s.thermal.packageC, rx: s.net.rxBps, tx: s.net.txBps,
                  dr: s.disks.first?.readBps ?? 0, dw: s.disks.first?.writeBps ?? 0)
    }
}

public struct History: Codable, Sendable, Equatable {
    public var range: String
    public var step: Int
    public var points: [HistoryPoint]
}

public enum PulseJSON {
    /// Go encodes time.Time as RFC 3339 with up to nine fractional digits and
    /// the zero time as 0001-01-01T00:00:00Z; Foundation's ISO 8601 parser
    /// only understands milliseconds, so fractions are trimmed first.
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(raw)"))
        }
        return d
    }

    static func parseDate(_ raw: String) -> Date? {
        var s = raw
        if let dot = s.firstIndex(of: "."),
           let end = s[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let digits = s[s.index(after: dot)..<end]
            let ms = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            s.replaceSubrange(dot..<end, with: "." + ms)
        }
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let plain = Date.ISO8601FormatStyle()
        return (try? withFraction.parse(s)) ?? (try? plain.parse(s))
    }
}
