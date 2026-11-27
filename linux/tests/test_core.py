import json
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from pulse_monitor import fmt, i18n, updates
from pulse_monitor.alerts import AlertEngine, AlertSettings
from pulse_monitor.client import base_url
from pulse_monitor.config import Preferences, load_token, save_token
from pulse_monitor.levels import (Level, attention_count, container_status, cpu_level, display_name,
                                  sorted_containers)
from pulse_monitor.model import Container, UnsupportedVersion, decode_history, decode_snapshot, parse_time
from pulse_monitor.sse import Event, SSEParser
from pulse_monitor.wording import status_summary

FIXTURES = Path(__file__).with_name("fixtures")


@pytest.fixture(autouse=True)
def english():
    i18n.set_language("en")


@pytest.fixture
def snap():
    return decode_snapshot((FIXTURES / "snapshot.json").read_bytes())


def test_decodes_fixture(snap):
    assert snap.host.name == "macmini-server"
    assert snap.host.threads == 8
    assert snap.fan and snap.fan.rpm == 1993 and snap.fan.speed_fraction == 0
    assert round(snap.mem.used_percent, 1) == 7.8
    assert snap.disks[0].used_percent == pytest.approx(53.88, abs=0.01)
    assert snap.containers and all(c.name for c in snap.containers)
    assert snap.ts.tzinfo is not None


def test_rejects_other_schema():
    with pytest.raises(UnsupportedVersion):
        decode_snapshot(json.dumps({"v": 2}))


def test_history_fixture():
    points = decode_history((FIXTURES / "history.json").read_bytes())
    assert points and points[0].t > 0


def test_parse_time_handles_go_formats():
    assert parse_time("2026-11-27T10:18:42.169123456Z").microsecond == 169123
    assert parse_time("0001-01-01T00:00:00Z").year == 1970
    assert parse_time("garbage").year == 1970


def test_levels_and_status():
    assert cpu_level(10) == Level.GOOD and cpu_level(60) == Level.WARN and cpu_level(90) == Level.CRITICAL
    assert container_status(Container(state="exited", exitCode=0)) == "stopped"
    assert container_status(Container(state="exited", exitCode=137)) == "failing"
    assert container_status(Container(state="running", health="unhealthy")) == "failing"
    assert container_status(Container(state="running", health="healthy")) == "healthy"
    assert display_name(Container(name="perde-test-jellyfin-1", project="perde-test")) == "jellyfin"
    assert display_name(Container(name="portainer")) == "portainer"


def test_sorting_puts_failing_first(snap):
    snap.containers[-1].state = "restarting"
    assert sorted_containers(snap)[0].name == snap.containers[-1].name
    assert attention_count(snap) >= 1


def test_formats_english_and_turkish():
    assert fmt.bytes_(554_000_000_000, "en") == "554 GB"
    assert fmt.bytes_(1_400_000_000_000, "tr") == "1,4 TB"
    assert fmt.rate(7_400, "en") == "7 KB/s"
    assert fmt.rate(3_400_000, "tr") == "3,4 MB/s"
    assert fmt.number(1993, 0, "tr") == "1.993"
    assert fmt.uptime(551_908) == "up 6d 9h"
    assert fmt.short_cpu("Intel Core i7-3615QM") == "i7-3615QM"
    assert fmt.short_os("Ubuntu 24.04.5 LTS") == "Ubuntu 24.04"


def test_alerts_hold_resolve_and_cooldown(snap):
    engine = AlertEngine(AlertSettings(hotC=50, hotHold=30, cooldown=600, offline=False))
    t0 = datetime(2026, 11, 27, tzinfo=timezone.utc)
    assert engine.evaluate(snap, True, t0) == []                       # 54 °C, held 0 s
    fired = engine.evaluate(snap, True, t0 + timedelta(seconds=31))
    assert [(e.kind, e.fired) for e in fired] == [("hot", True)]
    assert engine.evaluate(snap, True, t0 + timedelta(seconds=40)) == []  # one alert per episode
    snap.thermal.packageC = 40
    resolved = engine.evaluate(snap, True, t0 + timedelta(seconds=50))
    assert [(e.kind, e.fired) for e in resolved] == [("hot", False)]
    snap.thermal.packageC = 70
    engine.evaluate(snap, True, t0 + timedelta(seconds=60))
    assert engine.evaluate(snap, True, t0 + timedelta(seconds=100)) == []  # cooldown


def test_offline_alert_needs_hold():
    engine = AlertEngine(AlertSettings(offlineHold=60))
    t0 = datetime(2026, 11, 27, tzinfo=timezone.utc)
    assert engine.evaluate(None, False, t0) == []
    assert [e.kind for e in engine.evaluate(None, False, t0 + timedelta(seconds=61))] == ["offline"]


def test_alert_settings_tolerate_old_files():
    s = AlertSettings.from_dict({"hotC": 80, "unknown": 1})
    assert s.hotC == 80 and s.offline is True


def test_sse_parser():
    p = SSEParser()
    lines = ["retry: 2000", "", ": ping", "", "event: snapshot", 'data: {"v":1}', "", "data: a", "data: b", ""]
    events = [e for e in (p.feed(x) for x in lines) if e]
    assert events == [Event("snapshot", '{"v":1}'), Event("message", "a\nb")]
    assert p.retry == 2000


def test_base_url():
    assert base_url("macmini-server.taild883a6.ts.net:9123") == "https://macmini-server.taild883a6.ts.net:9123"
    assert base_url(" https://host:9123/ ") == "https://host:9123"
    assert base_url("ftp://host") is None
    assert base_url("") is None


def test_versions_and_release_parsing():
    assert updates.parse_version("v0.1.0") == (0, 1, 0)
    assert updates.parse_version("1.3.0-beta") == (1, 3, 0)
    assert updates.parse_version("nightly") is None
    assert updates.newer((0, 10, 0), (0, 9, 9)) and not updates.newer((0, 1), (0, 1, 0))
    release = updates.parse_release(json.dumps({
        "tag_name": "v0.2.0", "html_url": "https://github.com/kutluhangil/Pulse/releases/tag/v0.2.0",
        "assets": [{"name": "Pulse-0.2.0.dmg", "browser_download_url": "https://x/a.dmg"},
                   {"name": "pulse-monitor_0.2.0_all.deb", "browser_download_url": "https://x/a.deb"}]}))
    assert release.version == "0.2.0" and release.download_url == "https://x/a.deb"
    assert updates.is_newer(release, "0.1.0") and not updates.is_newer(release, "0.2.0")
    with pytest.raises(ValueError):
        updates.parse_release("{}")


def test_summary(snap):
    text = status_summary(snap)
    assert text.startswith("macmini-server · health 98 (Excellent)")
    assert "Containers:" in text


def test_preferences_and_token_round_trip(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    monkeypatch.setattr("pulse_monitor.config._secret", lambda: (None, None))
    prefs = Preferences.load()
    prefs.address = "host.ts.net:9123"
    prefs.alerts.hotC = 77
    prefs.save()
    again = Preferences.load()
    assert again.address == "host.ts.net:9123" and again.alerts.hotC == 77
    assert again.resolved_portainer() == "https://host.ts.net:9443"
    assert save_token("secret-token-value") == "file"
    token_file = tmp_path / "pulse" / "token"
    assert token_file.stat().st_mode & 0o777 == 0o600
    assert load_token() == "secret-token-value"


def test_turkish_catalogue_keeps_placeholders():
    catalogue = json.loads(Path(i18n.__file__).with_name("tr.json").read_text(encoding="utf-8"))
    for key, value in catalogue.items():
        assert sorted(re.findall(r"\{\w+\}", key)) == sorted(re.findall(r"\{\w+\}", value)), key
    i18n.set_language("tr")
    assert i18n._("Overview") == "Genel bakış"
    assert fmt.uptime(551_908) == "6g 9sa açık"


def test_every_ui_string_is_translated():
    catalogue = json.loads(Path(i18n.__file__).with_name("tr.json").read_text(encoding="utf-8"))
    source = "\n".join(p.read_text(encoding="utf-8") for p in Path(i18n.__file__).parent.rglob("*.py"))
    used = set(re.findall(r'_\(\s*"((?:[^"\\]|\\.)*)"\s*\)', source))
    assert sorted(used - set(catalogue)) == []
