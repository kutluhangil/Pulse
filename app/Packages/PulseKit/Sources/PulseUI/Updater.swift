import Foundation
import Observation
import PulseClient
import PulseCore

/// Looks for a newer Pulse on GitHub: on demand, and once a day while
/// "Check for updates automatically" is on. Installing stays manual (open
/// the DMG); an ad-hoc signed app cannot verify a self-update anyway.
@MainActor @Observable
public final class Updater {
    public enum Status: Equatable, Sendable {
        case idle, checking, upToDate
        case available(ReleaseInfo)
        case failed(String)
    }

    public private(set) var status: Status = .idle
    public let current: AppVersion?
    /// Called once per new version found by the automatic check.
    @ObservationIgnored public var onNewVersion: ((ReleaseInfo) -> Void)?

    @ObservationIgnored private let prefs: Preferences
    @ObservationIgnored private var loop: Task<Void, Never>?

    static let interval: TimeInterval = 24 * 3600

    public init(currentVersion: String, prefs: Preferences) {
        current = AppVersion(currentVersion)
        self.prefs = prefs
    }

    public var available: ReleaseInfo? {
        if case .available(let r) = status { return r }
        return nil
    }

    public func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if prefs.autoCheckUpdates, Date().timeIntervalSince(prefs.lastUpdateCheck ?? .distantPast) >= Self.interval {
                    await check()
                }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    @discardableResult
    public func check() async -> Status {
        status = .checking
        do {
            let release = try await UpdateChecker.latest()
            prefs.lastUpdateCheck = Date()
            if let current, release.version > current {
                status = .available(release)
                if prefs.notifiedUpdateTag != release.tag {
                    prefs.notifiedUpdateTag = release.tag
                    onNewVersion?(release)
                }
            } else {
                status = .upToDate
            }
        } catch UpdateError.noRelease {
            prefs.lastUpdateCheck = Date()
            status = .upToDate
        } catch {
            status = .failed(L("Could not reach GitHub"))
        }
        return status
    }
}
