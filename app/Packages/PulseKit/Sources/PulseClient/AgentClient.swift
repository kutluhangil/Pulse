import Foundation
import PulseCore

public enum AgentError: Error, Equatable, Sendable {
    case invalidAddress
    case unauthorized
    case http(Int)
    case unsupportedVersion(Int)
    case streamEnded
}

public struct ServerConfig: Codable, Sendable, Equatable {
    public var address: String
    public var token: String

    public init(address: String, token: String) {
        self.address = address
        self.token = token
    }

    /// Accepts "macmini-server.tailnet.ts.net:9123" or a full https URL.
    public var baseURL: URL? {
        var raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        if !raw.contains("://") { raw = "https://" + raw }
        guard let url = URL(string: raw), let scheme = url.scheme, ["https", "http"].contains(scheme), url.host() != nil else {
            return nil
        }
        return url
    }
}

/// HTTP client for one Pulse agent.
public final class AgentClient: Sendable {
    public let config: ServerConfig
    private let session: URLSession

    public init(config: ServerConfig) {
        self.config = config
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30 // stream heartbeats arrive every 15 s
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.waitsForConnectivity = false
        c.httpAdditionalHeaders = ["User-Agent": "Pulse-macOS"]
        session = URLSession(configuration: c)
    }

    deinit { session.invalidateAndCancel() }

    private func request(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval = 10) throws -> URLRequest {
        guard let base = config.baseURL else { throw AgentError.invalidAddress }
        var url = base.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AgentError.http(0) }
        switch http.statusCode {
        case 200: return
        case 401: throw AgentError.unauthorized
        default: throw AgentError.http(http.statusCode)
        }
    }

    public func snapshot() async throws -> Snapshot {
        let (data, resp) = try await session.data(for: request("v1/snapshot"))
        try Self.check(resp)
        return try Self.decode(data)
    }

    public func history(range: String = "10m") async throws -> History {
        let (data, resp) = try await session.data(for: request("v1/history", query: [.init(name: "range", value: range)]))
        try Self.check(resp)
        return try PulseJSON.decoder().decode(History.self, from: data)
    }

    public func logs(containerID: String, tail: Int = 100) async throws -> String {
        let (data, resp) = try await session.data(for: request("v1/containers/\(containerID)/logs",
                                                               query: [.init(name: "tail", value: String(tail))]))
        try Self.check(resp)
        return String(decoding: data, as: UTF8.self)
    }

    /// Round-trip time of the unauthenticated health endpoint, in milliseconds.
    public func latency() async throws -> Double {
        var req = try request("health", timeout: 5)
        req.setValue(nil, forHTTPHeaderField: "Authorization")
        let start = ContinuousClock.now
        let (_, resp) = try await session.data(for: req)
        try Self.check(resp)
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    /// Live snapshots until the connection drops; the caller reconnects.
    public func stream() -> AsyncThrowingStream<Snapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = try request("v1/stream", timeout: 30)
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, resp) = try await session.bytes(for: req)
                    try Self.check(resp)
                    var parser = SSEParser()
                    for try await line in bytes.linesKeepingEmpty() {
                        guard let event = parser.feed(line), event.name == "snapshot" else { continue }
                        continuation.yield(try Self.decode(Data(event.data.utf8)))
                    }
                    continuation.finish(throwing: AgentError.streamEnded)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func decode(_ data: Data) throws -> Snapshot {
        struct Version: Decodable { let v: Int }
        let v = try JSONDecoder().decode(Version.self, from: data).v
        guard v == Snapshot.supportedVersion else { throw AgentError.unsupportedVersion(v) }
        return try PulseJSON.decoder().decode(Snapshot.self, from: data)
    }
}

extension URLSession.AsyncBytes {
    /// `lines` drops empty lines, but SSE needs them to delimit events.
    func linesKeepingEmpty() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var buffer = [UInt8]()
                    buffer.reserveCapacity(64 * 1024)
                    for try await byte in self {
                        if byte == UInt8(ascii: "\n") {
                            if buffer.last == UInt8(ascii: "\r") { buffer.removeLast() }
                            continuation.yield(String(decoding: buffer, as: UTF8.self))
                            buffer.removeAll(keepingCapacity: true)
                        } else {
                            buffer.append(byte)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
