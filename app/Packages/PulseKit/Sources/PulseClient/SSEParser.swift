import Foundation

/// Minimal Server-Sent Events parser (WHATWG spec subset: event, data, retry,
/// comments). Feed it lines without their terminators; it returns an event
/// when a blank line completes one.
public struct SSEParser: Sendable {
    public struct Event: Sendable, Equatable {
        public var name: String
        public var data: String
    }

    private var name = ""
    private var data: [String] = []
    public private(set) var retry: Int?

    public init() {}

    public mutating func feed(_ line: String) -> Event? {
        if line.isEmpty {
            defer { name = ""; data = [] }
            guard !data.isEmpty else { return nil }
            return Event(name: name.isEmpty ? "message" : name, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event": name = String(value)
        case "data": data.append(String(value))
        case "retry": retry = Int(value)
        default: break
        }
        return nil
    }
}
