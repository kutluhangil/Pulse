import Foundation

/// Number formatting for tiles. Every function takes a locale so output is
/// testable; the UI passes `.current` (Turkish users get "27,34 GB", "1.000").
public enum Format {
    public struct Value: Equatable, Sendable {
        public let number: String
        public let unit: String
        public var text: String { unit.isEmpty ? number : "\(number) \(unit)" }
    }

    /// Bytes with decimal units (like Finder and Mole): 554 GB, 1,4 TB.
    public static func bytes(_ b: UInt64, locale: Locale = .current) -> Value {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = Double(b)
        var i = 0
        while v >= 1000, i < units.count - 1 {
            v /= 1000
            i += 1
        }
        return Value(number: number(v, locale: locale, digits: i >= 3 && v < 100 ? 1 : 0), unit: units[i])
    }

    /// Transfer rate, whole kilobytes like Mole: 0 KB/s, 12 KB/s, 3,4 MB/s.
    public static func rate(_ bps: UInt64, locale: Locale = .current) -> Value {
        let kb = Double(bps) / 1000
        if kb < 1000 {
            return Value(number: number(kb, locale: locale, digits: 0), unit: "KB/s")
        }
        let mb = kb / 1000
        return Value(number: number(mb, locale: locale, digits: mb < 100 ? 1 : 0), unit: "MB/s")
    }

    public static func percent(_ p: Double, locale: Locale = .current) -> String {
        number(p, locale: locale, digits: 0)
    }

    public static func rpm(_ r: Int, locale: Locale = .current) -> String {
        number(Double(r), locale: locale, digits: 0, grouping: true)
    }

    public static func cpuPercentPrecise(_ p: Double, locale: Locale = .current) -> String {
        number(p, locale: locale, digits: 1)
    }

    /// "6d 9h", "3h 12m", "4m" — compact uptime for chips.
    public static func uptime(_ secs: UInt64) -> (days: Int, hours: Int, minutes: Int) {
        let d = Int(secs / 86_400), h = Int(secs % 86_400 / 3_600), m = Int(secs % 3_600 / 60)
        return (d, h, m)
    }

    /// Marketing size of RAM: 16670760960 -> "16 GB" (rounded to binary GiB).
    public static func ramSize(_ b: UInt64) -> String {
        "\(Int((Double(b) / 1_073_741_824).rounded())) GB"
    }

    public static func number(_ v: Double, locale: Locale, digits: Int, grouping: Bool = true) -> String {
        v.formatted(.number.locale(locale).precision(.fractionLength(digits)).grouping(grouping ? .automatic : .never))
    }
}
