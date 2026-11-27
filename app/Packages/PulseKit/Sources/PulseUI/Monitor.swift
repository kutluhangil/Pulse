import AppKit
import Observation
import PulseClient
import PulseCore

/// Owns the live connection: streams snapshots, keeps chart history, measures
/// latency, detects stale data, reconnects with exponential backoff and feeds
/// the alert engine.
@MainActor @Observable
public final class Monitor {
    public enum Connection: Equatable {
        case notConfigured
        case connecting
        case live
        case offline(reason: String)
        case unauthorized
    }

    public private(set) var snapshot: Snapshot?
    public private(set) var connection: Connection = .notConfigured
    public private(set) var history = ChartHistory()
    public private(set) var lastUpdate: Date?
    public private(set) var latencyMs: Double?

    public private(set) var config: ServerConfig?
    public var alertSettings: AlertSettings {
        didSet { engine.settings = alertSettings }
    }
    /// Called on the main actor for every alert transition.
    public var onAlerts: (([AlertEvent]) -> Void)?

    @ObservationIgnored public private(set) var client: AgentClient?

    @ObservationIgnored private var engine: AlertEngine
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    static let staleAfter: TimeInterval = 12

    public init(config: ServerConfig?, alertSettings: AlertSettings = AlertSettings()) {
        self.config = config
        self.client = config.map(AgentClient.init)
        self.alertSettings = alertSettings
        self.engine = AlertEngine(settings: alertSettings)
    }

    public func start() {
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconnect() }
            }
        }
        reconnect()
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                self.checkStale()
                if tick % 2 == 0 { await self.measureLatency() }
                tick += 1
            }
        }
    }

    public func update(config: ServerConfig?) {
        self.config = config
        client = config.map(AgentClient.init)
        snapshot = nil
        history = ChartHistory()
        latencyMs = nil
        reconnect()
    }

    public func reconnect() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in await self?.runStream() }
    }

    /// True when the snapshot on screen is older than the stale threshold.
    public var isStale: Bool {
        guard let lastUpdate else { return true }
        return Date().timeIntervalSince(lastUpdate) > Self.staleAfter
    }

    private func runStream() async {
        var backoff: Double = 1
        while !Task.isCancelled {
            guard let config, let client, config.baseURL != nil, !config.token.isEmpty else {
                connection = .notConfigured
                return
            }
            if connection != .live { connection = .connecting }
            do {
                if let h = try? await client.history() { history.seed(h) }
                for try await snap in client.stream() {
                    backoff = 1
                    receive(snap)
                }
            } catch is CancellationError {
                return
            } catch AgentError.unauthorized {
                connection = .unauthorized
                backoff = 30
            } catch {
                if Task.isCancelled { return }
                connection = .offline(reason: Self.describe(error))
            }
            evaluateAlerts()
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 30)
        }
    }

    private func receive(_ snap: Snapshot) {
        snapshot = snap
        lastUpdate = Date()
        connection = .live
        history.append(HistoryPoint(snap))
        evaluateAlerts()
    }

    private func checkStale() {
        if connection == .live, isStale {
            connection = .offline(reason: L("No data for a while"))
            reconnect()
        }
        evaluateAlerts()
    }

    private func measureLatency() async {
        guard connection == .live, let client else { return }
        latencyMs = try? await client.latency()
    }

    private func evaluateAlerts() {
        let events = engine.evaluate(snapshot, connected: connection == .live && !isStale, now: Date())
        if !events.isEmpty { onAlerts?(events) }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case AgentError.invalidAddress: return L("Invalid server address")
        case AgentError.unsupportedVersion(let v): return L("Agent schema v\(v) is not supported, update Pulse")
        case AgentError.http(let code): return L("Server answered HTTP \(code)")
        case AgentError.streamEnded: return L("Connection closed")
        case let e as URLError:
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost: return L("Network unavailable")
            case .cannotFindHost, .dnsLookupFailed: return L("Server not found (is Tailscale on?)")
            case .cannotConnectToHost: return L("Agent is not running")
            case .timedOut: return L("Timed out")
            case .serverCertificateUntrusted, .secureConnectionFailed: return L("TLS error")
            default: return e.localizedDescription
            }
        default: return error.localizedDescription
        }
    }
}
