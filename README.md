<div align="center">

<img src="docs/media/hero.svg" alt="Pulse — a Mac menu bar panel showing a home server's live health, metrics and containers" width="100%">

<br>

![macOS](https://img.shields.io/badge/macOS-26%2B%20%C2%B7%20SwiftUI-5c9efa?style=for-the-badge&labelColor=080c0a&logo=apple&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-GTK%204%20%C2%B7%20libadwaita-5cd18c?style=for-the-badge&labelColor=080c0a&logo=linux&logoColor=white)
![Agent](https://img.shields.io/badge/agent-Go%20%C2%B7%20stdlib%20only-f5cc80?style=for-the-badge&labelColor=080c0a&logo=go&logoColor=white)
![Release](https://img.shields.io/github/v/release/kutluhangil/Pulse?style=for-the-badge&labelColor=080c0a&color=5c9efa)
![License](https://img.shields.io/badge/license-GPL--3.0-5cd18c?style=for-the-badge&labelColor=080c0a)

*A free monitor for the server in your cupboard: health score, CPU, temperature, memory, disk, network, fan,*<br>
*every Docker container and your public sites, live once a second, in the Mac menu bar and the Linux tray.*

<br>

<a href="https://pulse.kutluhangil.dev/#tour"><img src="docs/showcase/tour-mac.png" width="92%" alt="Pulse on macOS: the animated server in the menu bar and the frosted blue panel with health 98, live tiles, sites and containers"></a>

<sub>Click the picture to open the live tour on <a href="https://pulse.kutluhangil.dev">pulse.kutluhangil.dev</a>: the panel, the tools menu, settings and the Linux window, all clickable.</sub>

</div>

<img src="docs/media/divider.svg" width="100%" alt="">

## Is the server all right?

I run my projects on a 2012 Mac mini with Ubuntu Server in a cupboard. It has no screen, and checking it meant SSH, `htop`, `docker ps` and opening each public site by hand. Pulse answers the question with a glance at the menu bar: a coloured dot and `TMP 49°C CPU 1% MEM 8%`. One click opens a compact frosted panel laid out like Mole's Status popover, tinted blue, with a single health score and the reasons behind it.

It has three small parts. A Go agent runs in Docker on the server and reads `/proc`, `/sys` and the Docker API. It sends a snapshot every second over Server-Sent Events. A native SwiftUI app on the Mac and a GTK 4 / libadwaita app on Linux draw the snapshots, keep ten minutes of chart history, and send a notification when something needs you.

> **Nothing is exposed to the internet.** The agent listens on `127.0.0.1` only. `tailscale serve` publishes it with HTTPS inside your tailnet, so it is not on the LAN and not on Cloudflare. Docker is reached through a proxy that only allows reads, and the agent never touches the fan controller.

<img src="docs/media/divider.svg" width="100%" alt="">

## Features

| | |
|---|---|
| **Health score** | 0–100 with reasons ("Security updates pending"). Resource penalties are adapted from Mole; container, site, swap and reboot penalties are added on top |
| **Menu bar** | Up to three metrics (`TMP / CPU / MEM / DSK / NET / CTR`) as stacked columns or a single line. Values turn amber or red past the thresholds |
| **Animated icon** | A little server that hops and blinks its LEDs, a running cat, or a scrolling heartbeat. All three are drawn in code, run faster as CPU load rises, and stop when the data goes stale or Reduce Motion is on |
| **Tools menu** | Right-click (or swap the clicks): open the panel, settings, SSH, Portainer, Cockpit, container logs, sites, copy a status summary, reconnect, pause notifications |
| **Settings** | General, Server, Menu Bar, Alerts and About tabs: language, launch at login, the global `⌃⌥⌘P` shortcut, menu bar content and layout, alert thresholds and event switches |
| **CPU** | Total usage, one bar per thread, load average |
| **Temperature** | `coretemp` package and per-core readings. Broken SMC sensors (-127 °C, 103 °C) are filtered out |
| **Memory** | Used = total − available, the same as `free`; swap and cache in the tooltip |
| **Disk** | Free space, usage bar, read/write rate across physical disks only |
| **Network** | Download and upload rate on the default-route interface, link speed, Mac→server latency |
| **Fan** | RPM and speed above idle from `applesmc`. Display only: `macfanctld` stays in charge |
| **Containers** | State, health, CPU share and memory for each container (as `docker stats` counts it). Failing containers sort first. Read-only log tail window |
| **Sites** | Each public URL is checked every minute and shows its response time. Two failed checks in a row raise an alert |
| **Updates** | Pending apt and security updates, and the reboot-required flag, from Ubuntu's update-notifier |
| **Notifications** | Overheating, memory, disk, failing container, site down, server unreachable, restart needed. Each has a hold time, fires once per episode, and sends a "recovered" message |
| **Quick actions** | Open SSH, Portainer or Cockpit, open container logs, copy a container name |
| **Linux app** | Native GNOME window (GTK 4, libadwaita): Overview, Containers and Sites pages, preferences, log viewer. Tray icon with the same animated characters and a full menu on Ubuntu and KDE (StatusNotifierItem + dbusmenu) |
| **Check for updates** | Both apps ask GitHub for the latest release once a day (and on demand), then offer the DMG or the `.deb`. Nothing installs by itself |
| **Languages** | English and Turkish (213 strings on macOS, 199 on Linux), switchable in Settings; numbers follow your locale |
| **Light on resources** | The agent uses about 8 MB RAM and under 1 % CPU on an Ivy Bridge i7. The panel's SwiftUI tree exists only while the panel is open |

<img src="docs/media/divider.svg" width="100%" alt="">

## On Linux

<p align="center">
  <img src="docs/design/linux/linux-overview-dark.png" width="30%" alt="Pulse for Linux, Overview page in the dark style: score ring, resources with graphs">
  <img src="docs/design/linux/linux-containers-light.png" width="30%" alt="Containers page grouped by compose project">
  <img src="docs/design/linux/linux-prefs-tray-dark.png" width="30%" alt="Preferences, Tray page">
</p>

Pulse for Linux follows the GNOME guidelines instead of copying the Mac panel: a libadwaita window with a view switcher, boxed lists with live graphs, a preferences dialog and toasts, in the light and dark styles. It is plain Python on the GTK that Ubuntu already ships, so one `.deb` serves amd64 and arm64. The token goes to the desktop keyring (libsecret), or to a `0600` file where no keyring runs.

```bash
sudo apt install ./pulse-monitor_0.1.0_all.deb
pulse-monitor --configure macmini-server.tailnet.ts.net:9123 < token.txt   # or paste both in Preferences
```

The tray icon needs a StatusNotifierItem host: KDE Plasma has one, Ubuntu turns on its AppIndicator extension by default, and on plain GNOME the [AppIndicator extension](https://extensions.gnome.org/extension/615/appindicator-support/) adds it. Without one, Pulse is a normal window that still sends notifications.

<img src="docs/media/divider.svg" width="100%" alt="">

## How it works

```mermaid
flowchart LR
  subgraph server["macmini-server · Ubuntu"]
    proc["/proc · /sys<br/>coretemp · applesmc"] --> agent["pulse-agent<br/>Go · 1 s loop"]
    proxy["docker-socket-proxy<br/>GET only"] -->|every 5 s| agent
    sites["public sites"] -.->|every 60 s| agent
    agent --> api["127.0.0.1:9123<br/>JSON · SSE · logs"]
  end
  api --> ts["tailscale serve<br/>HTTPS · tailnet only"]
  ts -->|Bearer token| app["Pulse.app<br/>SwiftUI menu bar"]
  ts -->|Bearer token| gtk["pulse-monitor<br/>GTK 4 · tray"]
  app --> notes["notifications"]
  gtk --> notes
```

| Endpoint | What it returns |
|---|---|
| `GET /health` | `ok`, no token needed |
| `GET /v1/snapshot` | the latest snapshot as JSON |
| `GET /v1/stream` | one Server-Sent Event per second, plus a ping every 15 s |
| `GET /v1/history?range=10m\|24h` | in-memory chart history: 1 s points or 1 min averages |
| `GET /v1/containers/{id}/logs?tail=N` | the last lines of a container's logs |

The full schema, the score formula and every setting are in [`docs/API.md`](docs/API.md).

### Security, by rule

| Rule | How |
|---|---|
| No public exposure | The agent binds only `127.0.0.1`. `tailscale serve` provides HTTPS inside the tailnet. No `0.0.0.0`, no tunnel, no port forwarding |
| Docker socket is not handed out | `tecnativa/docker-socket-proxy` with `CONTAINERS=1 VERSION=1 POST=0`, bound to loopback |
| Token on every data request | Bearer token of at least 24 characters, compared in constant time. Without one the agent refuses to start |
| Locked-down containers | `read_only`, `cap_drop: ALL`, `no-new-privileges`, distroless nonroot image, 64 MB memory limit, host mounts read-only |
| No third-party Go code | The agent uses only the standard library; `govulncheck` and `staticcheck` run in CI |
| Token on the Mac | Kept in the app's sandbox container with `0600` permissions; never in logs or on the command line |

<img src="docs/media/divider.svg" width="100%" alt="">

## Install

Downloads are on the [releases page](https://github.com/kutluhangil/Pulse/releases/latest) and on [pulse.kutluhangil.dev](https://pulse.kutluhangil.dev/#download): `Pulse-<version>.dmg` for macOS, `pulse-monitor_<version>_all.deb` for Linux, and the agent image `ghcr.io/kutluhangil/pulse-agent`.

**1. Agent on the server** (from the Mac, with a Docker context pointing at the server):

```bash
./deploy/deploy.sh             # creates deploy/.env with a fresh token, builds on the server,
                               # starts agent + proxy, runs `tailscale serve`, verifies 401 and 200
./deploy/deploy.sh --copy-token  # copies the token to the clipboard (never printed)
```

Edit `deploy/.env` to set the sites to check: `PULSE_PROBES=name=https://…,name=https://…`.

**2. App on the Mac** (or open the DMG and drag Pulse to Applications):

```bash
./scripts/release-macos.sh --install   # tests, Release build, DMG in dist/, installs to /Applications
pbpaste | /Applications/Pulse.app/Contents/MacOS/Pulse --configure server.tailnet.ts.net:9123 --ssh user@server --login
```

You can also open Pulse and paste the address and token in Settings. Builds are ad-hoc signed, so on another Mac the first launch needs right-click → Open.

**3. App on Linux:** see [On Linux](#on-linux).

<img src="docs/media/divider.svg" width="100%" alt="">

## Türkçe özet

Pulse, evdeki Ubuntu sunucusunu Mac'in menü çubuğundan ve Linux'un tepsisinden canlı izler: sağlık puanı, işlemci, sıcaklık, bellek, disk, ağ, fan, Docker konteynerleri ve yayındaki siteler saniyede bir güncellenir. Sunucuda yalnız standart kütüphaneyle yazılmış küçük bir Go ajanı Docker'da çalışır. Mac'te SwiftUI ile yazılmış, Mole'un Status paneliyle aynı düzende, mavi tonlu buğulu bir panel açılır. Ajan internete açılmaz: yalnız `127.0.0.1`'i dinler, `tailscale serve` ile yalnız senin Tailscale ağından erişilir ve her istek bir token ister. Docker'a yalnız okuma izni veren bir aracı (socket proxy) üzerinden bağlanır, fana dokunmaz. Konteyner bozulursa, sunucu ısınırsa, site düşerse ya da sunucuya ulaşılamazsa bildirim gelir; düzelince de haber verir. Menü çubuğunda zıplayan bir sunucu, koşan bir kedi ya da kayan bir nabız çizgisi seçilebilir; sağ tık araç menüsünü, ayarlar da Genel, Sunucu, Menü çubuğu, Uyarılar ve Hakkında sekmelerini açar. Linux sürümü GNOME'un kendi tasarım diliyle (GTK 4, libadwaita) yazıldı, tek `.deb` paketiyle kurulur. İki uygulama da günde bir kez GitHub'da yeni sürüm arar. Tanıtım sitesi ve tıklanabilir canlı tur: [pulse.kutluhangil.dev](https://pulse.kutluhangil.dev).

<img src="docs/media/divider.svg" width="100%" alt="">

## Development

```bash
cd agent && go test -race ./... && go vet ./...     # 30 Go tests against real /proc and /sys fixtures
cd agent && go run ./cmd/pulse-agent --once        # one snapshot of this machine (Linux; DOCKER_HOST=off skips Docker)
cd app/Packages/PulseKit && swift test             # 28 Swift tests: schema, formatting, alerts, SSE, updates, menu bar
docker buildx build -f linux/packaging/Dockerfile --target deb --output dist/linux .   # 20 pytest tests + the .deb (Ubuntu 24.04)
cd site && npm test && npx playwright test         # site: unit and end-to-end tests
./scripts/site-deploy.sh                           # build, test and publish the site (Cloudflare Tunnel)
cd app && xcodegen generate && swiftlint lint --strict
python3 scripts/l10n.py app/Packages/PulseKit/l10n/tr.json   # rebuild the string catalog after adding L("…")
swift scripts/make-icon.swift                      # all icons from docs/design/logo.png
```

Agent environment: `PULSE_LISTEN`, `PULSE_TOKEN`, `PULSE_NO_AUTH` (loopback only), `PULSE_HOST_PROC`, `PULSE_HOST_SYS`, `PULSE_HOST_ROOT`, `DOCKER_HOST`, `PULSE_PROBES`, `PULSE_NET_IFACE`.

```
agent/                 Go agent (stdlib only)
  internal/collect/    procfs and sysfs readers: CPU, memory, disk, network, thermal, fan, apt
  internal/docker/     read-only Engine API client, log demux
  internal/health/     health score (adapted from Mole)
  internal/api/        HTTP, SSE, auth
  testdata/macmini/    recorded /proc and /sys of the real server
deploy/                compose.yaml (agent + socket proxy), deploy.sh
app/                   XcodeGen project, menu bar app shell
  Packages/PulseKit/   PulseCore (models, alerts) · PulseClient (SSE) · PulseUI (panel, settings)
linux/                 Pulse for Linux (Python, GTK 4, libadwaita)
  pulse_monitor/       model, alerts, client, monitor · ui/ (window, preferences) · tray/ (SNI, dbusmenu, sprites)
  packaging/           Dockerfile (tests, .deb, screenshots), build-deb.sh
site/                  pulse.kutluhangil.dev (Astro): scroll story, live tour, downloads
docs/                  PLAN.md, API.md, design/, showcase/
scripts/               release-macos.sh, site-deploy.sh, make-icon.swift, l10n.py
```

<br>

<a href="https://github.com/kutluhangil"><img src="docs/media/signature.svg" width="100%" alt="Built by kutluhangil"></a>

<sub>GPL-3.0. The health score's resource penalties are adapted from <a href="https://github.com/tw93/Mole">Mole</a> by tw93 (GPL-3.0), and the panel layout is inspired by Mole for Mac's Status view. The banner's values and container names are examples. The panel screenshot is the real server.</sub>
