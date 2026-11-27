import Foundation

/// Dotted release version ("0.1.0", "v1.2", "1.3.0-beta" → 1.3.0), compared
/// part by part with missing parts read as zero.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        let core = s.split(whereSeparator: { $0 == "-" || $0 == "+" || $0 == " " }).first ?? ""
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}
