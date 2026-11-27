# Pulse agent API (v1)

The agent serves plain HTTP on `127.0.0.1:9123`. `tailscale serve` puts HTTPS in front of it, reachable only from your tailnet:
`https://<server>.<tailnet>.ts.net:9123`.

Every `/v1/*` request needs `Authorization: Bearer <PULSE_TOKEN>`. A missing or wrong token gets `401`.

| Method | Path | Auth | Response |
|---|---|---|---|
| GET | `/health` | no | `200 ok` (liveness only, no data) |
| GET | `/v1/snapshot` | yes | latest `Snapshot` as JSON; `503` before the first sample |
| GET | `/v1/stream` | yes | Server-Sent Events: `event: snapshot` once per second, `: ping` every 15 s, `retry: 2000` |
| GET | `/v1/history?range=10m\|24h` | yes | `History`: 600 points at 1 s, or 1440 points at 1 min (in memory, lost on restart) |
| GET | `/v1/containers/{id}/logs?tail=N` | yes | last N lines of stdout and stderr (default 100, max 500) as `text/plain`, with timestamps |

At most 16 streams can be open at once (`429` after that). Responses carry `Cache-Control: no-store`.

## Snapshot

The Go source of truth is `agent/internal/model/snapshot.go`, and the Swift mirror is `app/Packages/PulseKit/Sources/PulseCore/Snapshot.swift`. The schema version is in `v`. A breaking change bumps it, and the app rejects versions it does not know.

```jsonc
{
  "v": 1,
  "ts": "2026-11-27T10:18:42.169Z",
  "host": { "name": "macmini-server", "cpuModel": "Intel Core i7-3615QM", "cores": 4, "threads": 8,
            "memTotal": 16670760960, "os": "Ubuntu 24.04.5 LTS", "kernel": "6.8.0-151-generic",
            "uptimeSec": 551908, "agentVersion": "v0.1.0" },
  "health": { "score": 98, "label": "Excellent", "reasons": ["security_updates"] },
  "cpu": { "usage": 3.1, "perThread": [2.0, 5.1, 1.0, 0, 3.2, 1.1, 0, 0], "load": [0.03, 0.05, 0.0],
           "freqMHz": 1198, "ioWait": 0.1 },
  "thermal": { "packageC": 58, "coresC": [52, 58, 53, 49], "critC": 105 },   // packageC 0 = no sensor
  "fan": { "label": "Exhaust", "rpm": 2000, "min": 2000, "max": 5500 },       // null when there is no fan
  "mem": { "total": 0, "used": 0, "available": 0, "cached": 0, "swapTotal": 0, "swapUsed": 0 },  // used = total - available
  "disks": [ { "mount": "/", "device": "ubuntu--vg-ubuntu--lv", "total": 0, "used": 0, "free": 0,
               "readBps": 0, "writeBps": 0 } ],
  "net": { "iface": "enp1s0f0", "speedMbps": 1000, "rxBps": 0, "txBps": 0, "rxTotal": 0, "txTotal": 0 },
  "containers": [ { "id": "…", "name": "perde-site-site-1", "project": "perde-site", "image": "…",
                    "state": "running", "health": "healthy", "statusText": "Up 2 hours (healthy)",
                    "cpu": 0.1, "memBytes": 7000000, "memLimit": 134217728,
                    "createdAt": "…", "exitCode": 0, "restartCount": 0 } ],
  "docker": { "available": true, "version": "29.9.3" },
  "probes": [ { "name": "perde", "url": "https://perde.kutluhangil.dev", "ok": true, "status": 200,
                "ms": 143, "checkedAt": "…" } ],
  "system": { "aptUpdates": 9, "securityUpdates": 2, "rebootRequired": false }
}
```

Notes:
- **Rates** (`usage`, `*Bps`) are measured since the previous sample (1 s apart). The agent's first sample reports 0.
- **Container `cpu`** is a share of the whole machine (0 to 100), not of one core. Containers are polled every 5 s.
- **Disk `used` and `free`** match `df`: blocks reserved for root count in neither.
- **Probes** run every 60 s. A `checkedAt` of `0001-01-01T00:00:00Z` means the probe has not run yet.
- **Health reasons** are codes the app turns into words: `cpu_high`, `mem_high`, `swap_high`, `disk_full`, `overheating`, `disk_io_heavy`, `container_down`, `site_down`, `reboot_required`, `security_updates`, `docker_unreachable`.

## Health score

The score starts at 100 and each item below subtracts a penalty. It is clamped to 0–100.

**Resource penalties** are adapted from Mole by tw93 (GPL-3.0). Up to the "high" threshold a penalty grows linearly to half its maximum. Above it, the penalty keeps growing until it reaches the full maximum at 100 %, so the score never rises while load gets worse.

| Signal | Maximum penalty | Normal / high threshold |
|---|---|---|
| CPU | 30 | 50 % / 85 % |
| Memory | 25 | 70 % / 88 % |
| Disk | 20 | 80 % / 93 % |
| Temperature | 15 | 65 °C / 85 °C |
| Disk I/O | 10 | 50 MB/s / 150 MB/s |

**Server penalties** are added on top:

| Signal | Penalty |
|---|---|
| Each failing container (unhealthy, restarting, dead, or exited with a non-zero code) | −10, at most −30 in total |
| A probe is down | −10 |
| Docker is unreachable | −10 |
| Swap more than 50 % used | −5 |
| Reboot required | −3 |
| Security updates pending | −2 |

**Labels:** 85 and above is Excellent, 65 and above is Good, 45 and above is Fair. Anything lower is Needs Attention.

## Configuration (environment)

| Variable | Default | Meaning |
|---|---|---|
| `PULSE_LISTEN` | `127.0.0.1:9123` | listen address |
| `PULSE_TOKEN` | required | bearer token of at least 24 characters (`openssl rand -hex 32`) |
| `PULSE_NO_AUTH` | unset | `1` disables auth; only allowed on a loopback address |
| `PULSE_HOST_PROC`, `PULSE_HOST_SYS`, `PULSE_HOST_ROOT` | `/proc`, `/sys`, `/` | host mounts when running in a container |
| `DOCKER_HOST` | `unix:///var/run/docker.sock` | `tcp://127.0.0.1:2375` points at the read-only socket proxy; `off` disables container monitoring |
| `PULSE_PROBES` | empty | comma-separated list in the form `name=https://url,name=https://url` |
| `PULSE_NET_IFACE` | default route | network interface to report |

Command-line flags: `--once` prints one snapshot and exits, `--healthcheck` checks the agent for Docker's HEALTHCHECK, and `--version` prints the version.
