import Foundation

/// Client-side copy of the agent's 1 s ring: seeded from /v1/history when the
/// connection opens, then extended with every streamed snapshot.
public struct ChartHistory: Sendable, Equatable {
    public static let capacity = 600 // 10 minutes

    public private(set) var points: [HistoryPoint] = []

    public init() {}

    public mutating func seed(_ history: History) {
        points = Array(history.points.suffix(Self.capacity))
    }

    public mutating func append(_ p: HistoryPoint) {
        if let last = points.last, p.t <= last.t { return }
        points.append(p)
        if points.count > Self.capacity {
            points.removeFirst(points.count - Self.capacity)
        }
    }

    /// The most recent `count` points, for small sparklines.
    public func recent(_ count: Int) -> ArraySlice<HistoryPoint> { points.suffix(count) }
}
