import PulseCore

// MARK: - Shared wording

func healthLabel(_ score: Int) -> String {
    switch score {
    case 85...: L("Excellent")
    case 65...: L("Good")
    case 45...: L("Fair")
    default: L("Needs Attention")
    }
}

func activityText(_ a: Activity) -> String {
    switch a {
    case .idle: L("idle")
    case .normal: L("normal")
    case .busy: L("busy")
    case .high: L("high")
    }
}

func temperatureWord(_ l: Level) -> String {
    switch l {
    case .good: L("Normal")
    case .warn: L("Warm")
    case .critical: L("Hot")
    }
}

func memoryWord(_ l: Level) -> String {
    switch l {
    case .good: L("Normal")
    case .warn: L("High")
    case .critical: L("Critical")
    }
}

public func reasonText(_ code: String) -> String {
    switch code {
    case "cpu_high": L("High CPU")
    case "mem_high": L("High memory")
    case "swap_high": L("Heavy swap use")
    case "disk_full": L("Disk almost full")
    case "overheating": L("Overheating")
    case "disk_io_heavy": L("Heavy disk I/O")
    case "container_down": L("Container needs attention")
    case "site_down": L("A site is down")
    case "reboot_required": L("Restart required")
    case "security_updates": L("Security updates pending")
    case "docker_unreachable": L("Docker unreachable")
    default: code
    }
}

func shortCPU(_ model: String) -> String {
    // "Intel Core i7-3615QM" -> "i7-3615QM"; "AMD Ryzen 7 5700U" stays readable.
    let parts = model.split(separator: " ")
    if let tail = parts.last, tail.contains("-") { return String(tail) }
    return parts.suffix(2).joined(separator: " ")
}

/// "Ubuntu 24.04.5 LTS" -> "Ubuntu 24.04".
func shortOS(_ os: String) -> String {
    let words = os.replacingOccurrences(of: " LTS", with: "").split(separator: " ")
    return words.map { word in
        let parts = word.split(separator: ".")
        return parts.count > 2 && parts.allSatisfy({ Int($0) != nil }) ? parts.prefix(2).joined(separator: ".") : String(word)
    }.joined(separator: " ")
}

func uptimeText(_ secs: UInt64) -> String {
    let u = Format.uptime(secs)
    if u.days > 0 { return L("up \(u.days)d \(u.hours)h") }
    if u.hours > 0 { return L("up \(u.hours)h \(u.minutes)m") }
    return L("up \(u.minutes)m")
}

/// Plain-text status for the clipboard ("Copy Status Summary").
public func statusSummary(_ s: Snapshot) -> String {
    var lines = ["\(s.host.name) · \(L("health")) \(s.health.score) (\(healthLabel(s.health.score)))",
                 "CPU \(Format.percent(s.cpu.usage))% · \(Format.percent(s.thermal.packageC))°C · MEM \(Format.percent(s.mem.usedPercent))%"]
    if let d = s.disks.first {
        lines.append("\(L("Disk")) \(Format.percent(d.usedPercent))% · \(Format.bytes(d.free).text) \(L("free"))")
    }
    lines.append("\(L("Containers")): \(s.runningCount)/\(s.containers.count)" +
                 (s.failingContainers.isEmpty ? "" : " · " + s.failingContainers.map(\.name).joined(separator: ", ")))
    for p in s.probes { lines.append("\(p.name): \(p.ok ? "\(p.ms) ms" : (p.error ?? "down"))") }
    if !s.health.reasons.isEmpty { lines.append(s.health.reasons.map(reasonText).joined(separator: " · ")) }
    return lines.joined(separator: "\n")
}
