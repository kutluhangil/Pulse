import PulseCore

/// Localized notification wording for alert events.
public enum AlertText {
    public static func content(for e: AlertEvent, host: String) -> (title: String, body: String) {
        let value = Format.percent(e.value)
        switch (e.kind, e.phase) {
        case (.offline, .fired): return (L("\(host) is unreachable"), L("No data from the Pulse agent for over a minute."))
        case (.offline, .resolved): return (L("\(host) is back"), L("Live data is flowing again."))
        case (.hot, .fired): return (L("\(host) is running hot"), L("CPU at \(value) °C."))
        case (.hot, .resolved): return (L("\(host) cooled down"), L("CPU temperature is back to normal."))
        case (.memory, .fired): return (L("\(host) is low on memory"), L("Memory use at \(value) %."))
        case (.memory, .resolved): return (L("\(host) memory is back to normal"), "")
        case (.disk, .fired): return (L("\(host) disk is filling up"), L("Disk use at \(value) %."))
        case (.disk, .resolved): return (L("\(host) disk has room again"), "")
        case (.container, .fired): return (L("Container \(e.subject) needs attention"), L("It stopped, crashed or turned unhealthy."))
        case (.container, .resolved): return (L("Container \(e.subject) recovered"), "")
        case (.probe, .fired): return (L("\(e.subject) is down"), L("The site failed two checks in a row."))
        case (.probe, .resolved): return (L("\(e.subject) is back up"), "")
        case (.reboot, .fired): return (L("\(host) needs a restart"), L("Installed updates take effect after a reboot."))
        case (.reboot, .resolved): return (L("\(host) restarted"), "")
        }
    }
}
