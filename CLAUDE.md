# Pulse — repo rules

Pulse is a live monitor for the home server `macmini-server`. It has two parts:
- a Go agent (`agent/`) running on the server,
- a SwiftUI menu bar app (`app/`) running on the Mac.

The plan is in `docs/PLAN.md` and the API in `docs/API.md`.

## Layout
- `agent/`: Go 1.26+, **standard library only** (no third-party modules).
  - `internal/collect`: procfs/sysfs readers.
  - `internal/docker`: read-only Engine API client.
  - `internal/probe`, `internal/health` (score adapted from Mole, GPL-3.0), `internal/history`, `internal/api`, `internal/agent`.
  - `testdata/macmini`: real `/proc` and `/sys` fixtures from the server.
- `deploy/`: `compose.yaml` (agent and docker-socket-proxy) and `deploy.sh`. `deploy/.env` holds the token and is git-ignored; never print it.
- `app/`: XcodeGen project (`project.yml`). The Swift package `Packages/PulseKit` has three modules:
  - `PulseCore`: models, formatting, alert rules.
  - `PulseClient`: SSE client, token store.
  - `PulseUI`: panel, settings, menu bar renderer, `Localizable.xcstrings`.
- `scripts/`:
  - `release-macos.sh`: Release build, DMG, `--install`.
  - `make-icon.swift`
  - `l10n.py`: regenerates the string catalog from `L("…")` calls and `l10n/tr.json`.

## Commands
| Task | Command |
|---|---|
| Agent tests | `cd agent && go test -race ./... && go vet ./...` |
| Deploy the agent | `./deploy/deploy.sh` (builds on the server through the `macmini` context, then runs `tailscale serve` and verifies) |
| Copy the app token | `./deploy/deploy.sh --copy-token` |
| Swift tests | `cd app/Packages/PulseKit && swift test` |
| Lint | `cd app && swiftlint lint --strict` |
| Build and install the app | `./scripts/release-macos.sh --install` |
| Configure the app | `<token Pulse.app/Contents/MacOS/Pulse --configure <host:9123> --ssh user@host --login` |
| Strings | after adding an `L("…")`, add its Turkish to `app/Packages/PulseKit/l10n/tr.json`, then run `python3 scripts/l10n.py app/Packages/PulseKit/l10n/tr.json` |

## Rules
- The agent never listens on `0.0.0.0` and never goes through Cloudflare. It is reached only through `tailscale serve`, the same way as Portainer.
- The Docker socket stays behind `docker-socket-proxy` with `POST=0`. The agent is read-only and never writes to the fan (`macfanctld` stays in charge).
- Change the schema in `agent/internal/model/snapshot.go`, `PulseCore/Snapshot.swift` and `docs/API.md` together. Bump `v` on breaking changes.
- Keep the panel's SwiftUI view alive only while the panel is open, so idle CPU stays low.
- Commit or push only when Kutluhan explicitly asks, with no AI attribution.
