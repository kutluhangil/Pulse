import Foundation
import Testing
@testable import PulseCore

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func liveSnapshot() throws -> Snapshot {
    try PulseJSON.decoder().decode(Snapshot.self, from: fixture("snapshot"))
}

@Suite struct DecodingTests {
    @Test func decodesRealAgentSnapshot() throws {
        let s = try liveSnapshot()
        #expect(s.v == Snapshot.supportedVersion)
        #expect(s.host.cpuModel == "Intel Core i7-3615QM")
        #expect(s.host.threads == 8 && s.cpu.perThread.count == 8)
        #expect(s.fan?.label == "Exhaust")
        #expect(s.containers.count >= 7)
        #expect(s.probes.allSatisfy { $0.checked })
        #expect(s.net.iface == "enp1s0f0")
    }

    @Test func decodesHistory() throws {
        let h = try PulseJSON.decoder().decode(History.self, from: fixture("history"))
        #expect(h.step == 1 && !h.points.isEmpty)
    }

    @Test func parsesGoTimestamps() throws {
        let nano = try #require(PulseJSON.parseDate("2026-11-27T10:17:29.165574467Z"))
        #expect(abs(nano.timeIntervalSince1970 - 1_795_774_649.165) < 0.001)
        #expect(PulseJSON.parseDate("2026-11-27T10:17:29Z") != nil)
        #expect(PulseJSON.parseDate("2026-11-27T10:17:29.5+03:00") != nil)
        let zero = try #require(PulseJSON.parseDate("0001-01-01T00:00:00Z"))
        #expect(zero.timeIntervalSince1970 < 0)
    }
}

@Suite struct FormatTests {
    let tr = Locale(identifier: "tr_TR")
    let en = Locale(identifier: "en_US")

    @Test func bytes() {
        #expect(Format.bytes(554_000_000_000, locale: tr).text == "554 GB")
        #expect(Format.bytes(1_400_000_000_000, locale: tr).text == "1,4 TB")
        #expect(Format.bytes(27_340_000_000, locale: en).text == "27.3 GB")
        #expect(Format.bytes(12_000_000, locale: en).text == "12 MB")
        #expect(Format.bytes(0, locale: en).text == "0 B")
    }

    @Test func rates() {
        #expect(Format.rate(0, locale: en).text == "0 KB/s")
        #expect(Format.rate(7_400, locale: en).text == "7 KB/s")
        #expect(Format.rate(54_484, locale: en).text == "54 KB/s")
        #expect(Format.rate(3_400_000, locale: tr).text == "3,4 MB/s")
    }

    @Test func rpmAndRam() {
        #expect(Format.rpm(2000, locale: tr) == "2.000")
        #expect(Format.ramSize(16_670_760_960) == "16 GB")
        let u = Format.uptime(551_908)
        #expect(u.days == 6 && u.hours == 9 && u.minutes == 18)
    }
}

@Suite struct LevelTests {
    @Test func thresholds() {
        #expect(Level.cpu(49) == .good && Level.cpu(50) == .warn && Level.cpu(85) == .critical)
        #expect(Level.temperature(58) == .good && Level.temperature(70) == .warn && Level.temperature(90) == .critical)
        #expect(Level.memory(83) == .warn && Level.disk(54) == .good && Level.health(98) == .good)
        #expect(Activity.cpu(3) == .idle && Activity.cpu(24) == .normal)
    }

    @Test func fanSpeedIsClamped() {
        let f = Snapshot.Fan(label: "Exhaust", rpm: 1995, min: 2000, max: 5500)
        #expect(f.speedFraction == 0)
        #expect(Snapshot.Fan(label: "", rpm: 3750, min: 2000, max: 5500).speedFraction == 0.5)
    }

    @Test func containerStatusAndNames() throws {
        var s = try liveSnapshot()
        let jelly = try #require(s.containers.first { $0.name == "perde-test-jellyfin-1" })
        #expect(displayName(jelly) == "jellyfin")
        #expect(ContainerStatus(jelly) == .healthy)

        var crashed = jelly
        crashed.name = "crash-1"; crashed.project = ""; crashed.state = "exited"; crashed.exitCode = 137
        var job = crashed
        job.name = "job"; job.exitCode = 0
        s.containers.append(contentsOf: [crashed, job])
        #expect(ContainerStatus(crashed) == .failing && ContainerStatus(job) == .stopped)
        #expect(s.sortedContainers.first?.name == "crash-1")
        #expect(displayName(crashed) == "crash")
        #expect(s.attentionCount == 1)
    }
}

@Suite struct ChartHistoryTests {
    @Test func appendsInOrderAndCaps() {
        var h = ChartHistory()
        for t in 0..<(ChartHistory.capacity + 10) {
            h.append(HistoryPoint(t: Int64(t), cpu: 1, mem: 1, temp: 1, rx: 0, tx: 0, dr: 0, dw: 0))
        }
        h.append(HistoryPoint(t: 5, cpu: 9, mem: 0, temp: 0, rx: 0, tx: 0, dr: 0, dw: 0)) // stale, ignored
        #expect(h.points.count == ChartHistory.capacity)
        #expect(h.points.first?.t == 10 && h.points.last?.t == Int64(ChartHistory.capacity + 9))
        #expect(h.recent(30).count == 30)
    }
}

@Suite struct AlertEngineTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func hotNeedsToPersist() throws {
        var s = try liveSnapshot()
        var e = AlertEngine()
        s.thermal.packageC = 90
        #expect(e.evaluate(s, connected: true, now: t0).isEmpty)
        #expect(e.evaluate(s, connected: true, now: t0 + 10).isEmpty)
        let fired = e.evaluate(s, connected: true, now: t0 + 31)
        #expect(fired.map(\.kind) == [.hot] && fired[0].phase == .fired && fired[0].value == 90)
        #expect(e.evaluate(s, connected: true, now: t0 + 40).isEmpty) // one alert per episode
        s.thermal.packageC = 60
        let resolved = e.evaluate(s, connected: true, now: t0 + 50)
        #expect(resolved.map(\.phase) == [.resolved])
        // Cooldown: hot again soon after does not re-alert.
        s.thermal.packageC = 90
        _ = e.evaluate(s, connected: true, now: t0 + 60)
        #expect(e.evaluate(s, connected: true, now: t0 + 95).isEmpty)
        #expect(e.evaluate(s, connected: true, now: t0 + 700).map(\.kind) == [.hot])
    }

    @Test func offlineAfterHold() throws {
        var e = AlertEngine()
        #expect(e.evaluate(nil, connected: false, now: t0).isEmpty)
        #expect(e.evaluate(nil, connected: false, now: t0 + 61).map(\.kind) == [.offline])
        let s = try liveSnapshot()
        #expect(e.evaluate(s, connected: true, now: t0 + 70).map(\.phase) == [.resolved])
    }

    @Test func containerFailureAndRemoval() throws {
        var s = try liveSnapshot()
        var e = AlertEngine()
        _ = e.evaluate(s, connected: true, now: t0)
        s.containers[0].health = "unhealthy"
        let name = s.containers[0].name
        let fired = e.evaluate(s, connected: true, now: t0 + 1)
        #expect(fired == [AlertEvent(key: "container:" + name, kind: .container, phase: .fired, subject: name, value: 0)])
        s.containers.remove(at: 0)
        #expect(e.evaluate(s, connected: true, now: t0 + 2).map(\.phase) == [.resolved])
    }

    @Test func probeNeedsTwoFailedChecks() throws {
        var s = try liveSnapshot()
        var e = AlertEngine()
        s.probes[0].ok = false
        s.probes[0].checkedAt = t0
        #expect(e.evaluate(s, connected: true, now: t0).isEmpty)
        #expect(e.evaluate(s, connected: true, now: t0 + 1).isEmpty) // same check repeated
        s.probes[0].checkedAt = t0 + 60
        #expect(e.evaluate(s, connected: true, now: t0 + 61).map(\.kind) == [.probe])
    }

    @Test func disabledDoesNothing() throws {
        var settings = AlertSettings()
        settings.enabled = false
        var e = AlertEngine(settings: settings)
        #expect(e.evaluate(nil, connected: false, now: t0 + 1000).isEmpty)
    }
}

@Suite struct AlertSettingsTests {
    @Test func oldSettingsDecodeWithDefaults() throws {
        let old = #"{"enabled":true,"hotC":80,"hotHold":30,"memoryPct":90,"memoryHold":60,"diskPct":85,"#
            + #""offlineHold":60,"containers":true,"probes":false,"reboot":true,"cooldown":600}"#
        let s = try JSONDecoder().decode(AlertSettings.self, from: Data(old.utf8))
        #expect(s.hotC == 80 && s.probes == false && s.offline == true)
    }

    @Test func offlineAlertCanBeDisabled() {
        var settings = AlertSettings()
        settings.offline = false
        var e = AlertEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(e.evaluate(nil, connected: false, now: t0).isEmpty)
        #expect(e.evaluate(nil, connected: false, now: t0 + 120).isEmpty)
    }
}
