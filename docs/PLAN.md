# Pulse — Ana Plan

> Ev sunucusunu (`macmini-server`) Mac menü çubuğundan canlı izleyen açık kaynak uygulama.
> İki parça: sunucuda küçük bir **Go ajanı**, Mac'te yerel **SwiftUI menü çubuğu uygulaması**.
> Tasarım dili: Mole for Mac'in "Status" paneli (koyu cam, 2 sütun kutucuk, büyük sağlık puanı).
> Repo: https://github.com/kutluhangil/Pulse (public) · Yerel: `/Volumes/ProjectClaude/Pulse`
> Tarih: 2026-11-27

---

## 0. Durum (2026-11-27)

Faz 0–8 uygulandı. Ajan sunucuda canlı (`https://macmini-server.taild883a6.ts.net:9123`), uygulama `/Applications/Pulse.app`'te kurulu ve girişte açılıyor. Plandan sapmalar ve nedenleri:

| Plan | Uygulanan | Neden |
|---|---|---|
| Ajan `gopsutil/v4` kullanır | Yalnız standart kütüphane | `/proc` ve `/sys` ayrıştırması basit; sıfır bağımlılık, gerçek sunucu verisiyle test edilebilir |
| Token Mac'te Anahtar Zinciri'nde | Uygulamanın sandbox klasöründe `0600` dosya (`TokenStore`) | Ad-hoc imzalı sürümlerde imza her güncellemede değişiyor; Anahtar Zinciri her seferinde izin penceresi açıyor. Developer ID gelince Anahtar Zinciri'ne dönülebilir |
| Paket başına ayrı Swift paketleri | Tek `PulseKit` paketi, 3 modül | Aynı ayrım, daha az proje dosyası |
| Liquid Glass panel, 352 pt | Mole Status düzeninde 340 pt, buğulu (NSVisualEffectView + mavi ton) panel | Kutluhan Mole'un birebir ölçülerini ve buğulu zeminini istedi (2026-11-27) |
| "Sıcaklık" kutucuğu başlığı | "Temp" / "Isı" | Kısa başlık kutucuğa sığıyor |
| Bundle ID `com.kutluhangul.pulse` | Aynı | — |

Elle doğrulanması gerekenler: paneli fareyle açıp kapama, bildirim izni penceresi (ilk açılışta bir kez), Mole ile görsel karşılaştırma.

---

## 1. Araştırma özeti (kararların dayanağı)

### 1.1 Sunucu (2026-11-27'de SSH ile salt okunur ölçüldü)
| Konu | Değer | Kaynak (sunucuda) |
|---|---|---|
| CPU | Intel i7-3615QM, 4 çekirdek / 8 iş parçacığı, 1,2–3,3 GHz | `/proc/stat`, `/proc/cpuinfo` |
| Sıcaklık | `coretemp`: Package 57°C, Core 0–3 43–56°C | `/sys/class/hwmon/hwmon*/` (name=`coretemp`) |
| SMC sensörleri | `applesmc`: TA0P, TC0P… bazıları bozuk (-127°C, 103°C) | Kullanılmayacak; yalnız `coretemp` |
| Fan | `applesmc` fan1 "Exhaust" 2000 RPM (min 2000, max 5500), `macfanctld` yönetiyor | `/sys/devices/platform/applesmc.768/fan1_*` |
| RAM | 15,5 GiB, swap `/swap.img` 4 GiB | `/proc/meminfo` |
| Disk | Seagate BarraCuda SSD 233 GB, LVM kök 98 GB (%54) | `statfs`, `/proc/diskstats` |
| Ağ | `enp1s0f0` 1 Gb/s, `tailscale0`, docker köprüleri | `/proc/net/dev`, `/sys/class/net/*/speed` |
| Docker | 29.9.3, API 1.56, cgroup v2 (systemd) — 7 konteyner | Docker Engine API |
| Tailscale serve | Yalnız Portainer (`:9443`) | `tailscale serve status` |
| Açık portlar | 22, 9090, `127.0.0.1:8787`, `127.0.0.1:9443`, Tailscale IP'de 445/8096 | `ss -ltn` |

### 1.2 Mole (tasarım ve sağlık puanı kaynağı)
- **Mole for Mac** (ekran görüntüsündeki panel) **kapalı kaynak**; `tw93/Mole-App` deposunda yalnız kılavuz var. Arayüz kodu alınamaz → SwiftUI'da biz yeniden çizeceğiz.
- **Mole CLI** (`tw93/Mole`, 76k yıldız) **açık kaynak, GPL-3.0, Go**. `cmd/status/` altında `mo status` metrik toplayıcıları ve **sağlık puanı** (`metrics_health.go`) var; `gopsutil/v4` kullanıyor.
- Sağlık puanı formülü: 100'den ceza düşülür. Ağırlıklar CPU 30, RAM 25, Disk 20, Isı 15, Disk G/Ç 10. Eşikler: CPU %50/%85, RAM %70/%88, Disk %80/%93, Isı 65/85°C, G/Ç 50/150 MB/s. Etiket: ≥85 Excellent, ≥65 Good, ≥45 Fair, altı Poor.
- Mole'un menü çubuğu hataları (issue #1163, #1090): macOS 26.5+/27'de görsel tabanlı status item sıfır genişliğe çöküp kayboluyor. **Ders:** status item'a her zaman yedek bir glif koy, görsel yüklenemezse ona dön.
- **Lisans kararı:** Sağlık puanı mantığını Mole'dan uyarlayacağımız için Pulse **GPL-3.0** olur (QuotaDeck ile aynı). README'de Mole'a teşekkür ve kaynak bağlantısı.

### 1.3 Neden hazır araç değil (Glances/Beszel/Netdata)
Hazır araçlar fan (`applesmc`), sağlık puanı, Cloudflare Tunnel yayın kontrolü ve bu tasarımı vermiyor; üstelik 2012 Mac mini'de gereksiz yük. Kendi ajanımız ~1 sn aralıkla ölçüm yapan, <20 MB RAM, <%1 CPU kullanan tek bir statik Go ikilisi olacak.

---

## 2. Mimari

```
┌──────────────── macmini-server (Ubuntu 24.04, Intel) ────────────────┐
│                                                                      │
│  pulse-agent (Go, distroless, network_mode: host, read-only)         │
│   ├─ /host/proc, /host/sys, /host/root  (salt okunur bağlama)        │
│   ├─ Docker API ── docker-socket-proxy (yalnız GET /containers, info)│
│   ├─ Yayın denetimi: https://perde.kutluhangil.dev/health …          │
│   └─ HTTP 127.0.0.1:9123  ──►  tailscale serve --https=9123          │
│                                                                      │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ HTTPS (ts.net sertifikası), yalnız tailnet
                                │ + Bearer token
┌───────────────────────────────▼──────────────────────────────────────┐
│  Pulse.app (macOS 26, SwiftUI, Liquid Glass)                          │
│   ├─ Menü çubuğu: ● TMP 57° CPU 3% MEM 8% DSK 54%                    │
│   ├─ Panel: sağlık puanı + kutucuklar + konteynerler + yayınlar      │
│   ├─ SSE akışı (1 sn), kopunca üstel geri çekilmeli yeniden bağlanma │
│   └─ Bildirimler, Ayarlar, girişte başlat                            │
└──────────────────────────────────────────────────────────────────────┘
```

**Neden bu yol:**
- **İnternete açılmıyor.** Bu bir yönetim verisi; kural gereği Cloudflare Tunnel'a konmaz. `tailscale serve` (tailnet only) Portainer ile aynı kalıp. Ajan yalnız `127.0.0.1`'e bağlanır; `0.0.0.0` yok.
- **Tailscale IP'ye doğrudan bağlama yok.** Açılışta `tailscale0` geç kalkarsa konteyner portu bağlayamaz; `127.0.0.1` + `tailscale serve` bu sorunu yaşamaz ve HTTPS'i bedava verir.
- **Docker socket doğrudan verilmez.** Socket = root. Araya `docker-socket-proxy` girer, yalnız `CONTAINERS=1`, `INFO=1`, `POST=0`.
- **Bearer token** ikinci katman: tailnet'teki başka bir cihaz da token olmadan okuyamaz. Token Mac'te Anahtar Zinciri'nde, sunucuda git dışı `.env`'de.

---

## 3. Ekranda neler görünecek (Mole panelinin Pulse karşılığı)

Panel genişliği ~360 pt, koyu cam arka plan, kutucuklar 16 pt köşe yarıçaplı daha koyu yüzeyler, rakamlar `monospacedDigit`, renk dili: yeşil (iyi) · amber (dikkat) · kırmızı (kritik) · mavi (nötr grafik).

```
┌──────────────────────────────────────────────┐
│ ☀ 92  Excellent                    ● Canlı   │  ← sağlık puanı + bağlantı durumu
│ [i7-3615QM] [16 GB] [Ubuntu 24.04] [up 6g 8s]│  ← çipler
├─────────────────────┬────────────────────────┤
│ ⚙ CPU        57°C   │ 🌡 Sıcaklık    Normal   │
│ 3 %                 │ 57 °C                   │
│ ▃▂▂▁▁▁▂▁ (8 thread) │ ~~~~~~ (10 dk çizgi)    │
│ idle · load 0.03    │ çekirdek maks 56°C      │
├─────────────────────┼────────────────────────┤
│ ▦ MEM       Normal  │ ⛁ Boş alan     98 GB    │
│ 8 %                 │ 44 GB                   │
│ ▁▁▁▁▁▁ (alan graf.) │ ████░░░░                │
│ 1,2 GB / 15,5 GB    │ 50 GB kullanıldı · %54  │
│ swap 0 / 4 GB       │ R 0,1 · W 0,4 MB/s      │
├─────────────────────┼────────────────────────┤
│ 🌐 Ağ    [Ethernet] │ ✣ Fan        Hız %0     │
│ 12 KB/s ↓           │ 2.000 RPM               │
│ ~~~~/\~~~~          │ macfanctld yönetiyor    │
│ ↑ 8 KB/s  · 4 ms    │ min 2000 · maks 5500    │
├─────────────────────┴────────────────────────┤
│ ☁ Yayınlar   perde ● 120 ms  perde-keys ● 95 │  ← AirPods satırının yerine
├──────────────────────────────────────────────┤
│ Konteynerler          Bellek   % CPU         │  ← Top Processes yerine
│ ● perde-site-site-1   12 MB    0,1   ···     │
│ ● jellyfin-1          310 MB   2,4   ···     │
│ ● samba-1             40 MB    0,0   ···     │
│ ● key-proxy-1         18 MB    0,0   ···     │
│ ● portainer           25 MB    0,1   ···     │
│ 7 çalışıyor · 0 durdu                  Tümü  │
├──────────────────────────────────────────────┤
│ ⌘ SSH   ⚓ Portainer   ◎ Cockpit       ⚙     │  ← hızlı eylemler
│   7            3              0              │
│ Konteyner   Güncelleme    Uyarı              │  ← Cleaned/Uninstalled/Optimized yerine
└──────────────────────────────────────────────┘
```

### 3.1 Kutucuk ayrıntıları
| Kutucuk | Büyük değer | Grafik | Alt satır | Sağ üst çip |
|---|---|---|---|---|
| **CPU** | toplam % | 8 iş parçacığı için ayrı çubuk (Mole'daki gibi; düşük yeşil→yüksek kırmızı) | `idle/normal/busy · load 1/5/15` | Package sıcaklığı |
| **Sıcaklık** (Mole'daki GPU yerine; sunucunun GPU'su kullanılmıyor) | Package °C | son 10 dk çizgi grafik | en sıcak çekirdek, Tjmax 105°C | Normal / Sıcak / Kritik |
| **MEM** | kullanılan % (`MemAvailable`'a göre, önbellek hariç) | alan grafiği | `kullanılan / toplam`, swap | Normal / High |
| **Boş alan** | boş GB | doluluk çubuğu | `x GB kullanıldı · %y`, okuma/yazma MB/s | toplam boyut |
| **Ağ** | indirme hızı (`enp1s0f0`) | indirme+yükleme çizgileri | yükleme, Mac→sunucu gecikmesi (Low/High Lag) | arayüz türü + 1 Gb |
| **Fan** | RPM | — | "macfanctld yönetiyor", min/maks | Hız % = (rpm-min)/(max-min) |

> **Fan kontrolü YOK.** Mole'daki Auto/Cool/Max düğmeleri Pulse'ta bilgi göstergesine dönüşür. `macfanctld` asla devre dışı bırakılmamalı (sunucu kuralı); ajan fana yazmaz.

### 3.2 Konteyner satırı
- Durum noktası: yeşil `healthy`/çalışıyor, amber `starting`/healthcheck yok, kırmızı `unhealthy`/`exited`/`restarting`.
- Ad (compose proje öneki kısaltılır, üzerine gelince tam ad), bellek, % CPU (8 iş parçacığına göre), çalışma süresi ipucunda.
- `···` menüsü: **Son 100 satır günlük** (ayrı pencere, salt okunur), adı kopyala, Portainer'da aç.
- Sıralama: önce sorunlular, sonra % CPU.

### 3.3 Yayınlar satırı
Ajan her 60 sn'de ayarlı herkese açık adreslere istek atar (`https://perde.kutluhangil.dev`, `https://perde-keys.kutluhangil.dev/health`): durum kodu + süre. Kırmızı = Cloudflare Tunnel veya servis düştü. Bu, "yayınım ayakta mı" sorusunun tek bakışlık cevabı.

### 3.4 Alt şerit
- Hızlı eylemler: **SSH** (Terminal'de `ssh kutluhan@macmini-server`), **Portainer**, **Cockpit** (tarayıcıda Tailscale adresleri), **Ayarlar**.
- Sayaçlar: çalışan konteyner, bekleyen apt güncellemesi (`/var/lib/update-notifier/updates-available`), aktif uyarı sayısı. `/var/run/reboot-required` varsa "Yeniden başlatma gerekli" rozeti. Aylık `sudo apt upgrade` hatırlatması buradan da görünür.

### 3.5 Menü çubuğu
- Varsayılan: sağlık rengiyle nokta + `TMP 57° CPU 3% MEM 8%` (ekran görüntüsündeki iki satırlı küçük etiket stili: üstte başlık, altta değer).
- Ayarlardan seçilebilir alanlar: TMP, CPU, MEM, DSK, NET, konteyner sayısı; ya da yalnız simge.
- Bağlantı yoksa: gri simge + `—`. Son veri 60 sn'den eskiyse panelde "Son veri 2 dk önce" bandı.
- Mole dersi: status item her zaman yedek SF Symbol ile başlar, çizim başarısız olursa ona döner.

---

## 4. Toplanacak veriler (ajan şeması)

`GET /v1/snapshot` ve `GET /v1/stream` (SSE, `event: snapshot`, 1 sn) aynı gövdeyi döner:

```json
{
  "v": 1,
  "ts": "2026-11-27T12:12:41Z",
  "host": { "name": "macmini-server", "cpuModel": "Intel Core i7-3615QM", "threads": 8,
            "memTotal": 16612000000, "os": "Ubuntu 24.04.5 LTS", "kernel": "6.8.0-151-generic",
            "uptimeSec": 548000, "agentVersion": "0.1.0" },
  "health": { "score": 92, "label": "Excellent", "reasons": ["Disk %54"] },
  "cpu": { "usage": 3.1, "perThread": [2.0,5.1,1.0,0,3.2,1.1,0,0], "load": [0.03,0.05,0.00], "freqMHz": 1600 },
  "thermal": { "packageC": 57, "coresC": [56,53,49,43], "maxC": 105 },
  "fan": { "rpm": 2000, "min": 2000, "max": 5500, "label": "Exhaust" },
  "mem": { "total": 16612000000, "used": 1290000000, "available": 15100000000, "cached": 11800000000,
           "swapTotal": 4294967296, "swapUsed": 524288 },
  "disk": [ { "mount": "/", "total": 105000000000, "used": 53700000000, "free": 47200000000,
              "readBps": 102400, "writeBps": 409600 } ],
  "net": { "iface": "enp1s0f0", "speedMbps": 1000, "rxBps": 12288, "txBps": 8192,
           "rxTotal": 0, "txTotal": 0 },
  "containers": [ { "id": "ab12…", "name": "perde-site-site-1", "project": "perde-site",
                    "image": "nginxinc/nginx-unprivileged:1.30.1", "state": "running",
                    "health": "healthy", "cpu": 0.1, "memBytes": 12000000, "memLimit": 134217728,
                    "startedAt": "…", "restartCount": 0 } ],
  "probes": [ { "name": "perde", "url": "https://perde.kutluhangil.dev", "ok": true,
                "status": 200, "ms": 120, "checkedAt": "…" } ],
  "system": { "aptUpdates": 3, "securityUpdates": 0, "rebootRequired": false }
}
```

Ek uç noktalar:
- `GET /health` → `200 ok` (tokensız; yalnız canlılık).
- `GET /v1/history?range=10m|24h` → panel açılınca grafikleri doldurmak için halka tampon (10 dk × 1 sn, 24 sa × 1 dk; bellekte, disk yok).
- `GET /v1/containers/{id}/logs?tail=100` → salt okunur günlük.
- Konteyner istatistikleri Docker `stats?stream=false` ile 5 sn'de bir toplanır (her saniye sorgu yükü olmasın); sistem metrikleri 1 sn.

**Sağlık puanı (Mole uyarlaması + sunucuya özel):**
- Mole ağırlıkları ve eşikleri (§1.2) aynen.
- Ek cezalar: her `unhealthy`/beklenmedik `exited` konteyner −10 (en fazla −30), düşen yayın −10, swap kullanımı >%50 −5, yeniden başlatma gerekli −3, güvenlik güncellemesi bekliyor −2.
- `reasons` listesi panelde puanın üzerine gelince görünür ("Neden 78? jellyfin unhealthy, disk %86").

---

## 5. Klasör yapısı

```
Pulse/
├── README.md               ← readme-tema standardı (hero SVG, EN + TR özet)
├── LICENSE                 ← GPL-3.0
├── CLAUDE.md               ← repo kuralları (ajan + uygulama komutları)
├── .gitignore
├── agent/                  ← Go ajanı
│   ├── cmd/pulse-agent/main.go
│   ├── internal/collect/   ← cpu, mem, disk, net, thermal, fan, docker, system, probe
│   ├── internal/health/    ← sağlık puanı (Mole uyarlaması)
│   ├── internal/history/   ← halka tampon
│   ├── internal/api/       ← HTTP, SSE, auth, rate limit
│   ├── testdata/           ← sunucudan alınmış /proc, /sys örnekleri
│   ├── Dockerfile          ← çok aşamalı, distroless static nonroot
│   └── go.mod
├── deploy/
│   ├── compose.yaml        ← pulse-agent + docker-socket-proxy
│   ├── .env.example        ← PULSE_TOKEN, PULSE_PROBES
│   └── deploy.sh           ← Mac'ten tek komutla kur/güncelle + tailscale serve
├── app/                    ← macOS uygulaması
│   ├── project.yml         ← XcodeGen (Lunula kalıbı, com.kutluhangul.pulse)
│   ├── App/Sources/        ← PulseApp, StatusItemController, PanelWindow
│   └── Packages/
│       ├── PulseCore/      ← modeller, Codable şema, biçimlendirme, eşikler
│       ├── PulseClient/    ← SSE istemcisi, yeniden bağlanma, Keychain
│       └── PulseUI/        ← kutucuklar, grafikler, tasarım belirteçleri
├── scripts/
│   └── release-macos.sh    ← derle, ad-hoc imzala, DMG
└── docs/
    ├── PLAN.md             ← bu dosya
    ├── API.md              ← şema ve uç noktalar
    └── design/             ← referans görüntüler, ekran görüntüleri
```

---

## 6. Güvenlik

| Risk | Önlem |
|---|---|
| Ajan internete açılır | `127.0.0.1:9123` + `tailscale serve` (tailnet only). Cloudflare/funnel/`0.0.0.0` yok. |
| Docker socket = root | `tecnativa/docker-socket-proxy` (sürüm sabit), yalnız `CONTAINERS=1 INFO=1`, `POST=0`; proxy de yalnız `127.0.0.1`. |
| Tailnet'teki başka cihaz | Bearer token (32 bayt rastgele), sabit zamanlı karşılaştırma; Mac'te Keychain. |
| Konteyner kaçışı | `read_only: true`, `cap_drop: [ALL]`, `no-new-privileges`, nonroot kullanıcı, `mem_limit: 64m`, `cpus: 0.25`, host bağlamaları `:ro`. |
| Günlüklerde sır | Günlük uç noktası yalnız tail; uygulama günlükleri diske yazmaz. Token asla çıktıya yazılmaz. |
| Bağımlılık | Go: yalnız `gopsutil/v4` + stdlib. Swift: harici paket yok. Dependabot + `govulncheck` CI'da. |

---

## 7. Fazlar

Her faz sonunda: testler yeşil, kısa doğrulama raporu. **Commit/push yalnız Kutluhan "commit at / push et" deyince.**

### Faz 0 — İskelet (yarım gün)
- `brew install go` (Mac'te yok), repo düzeni (§5), `LICENSE` GPL-3.0, `.gitignore`, `CLAUDE.md`, README taslağı.
- `agent/go.mod` (Go 1.26, `gopsutil/v4`), `app/project.yml` (macOS 26, Swift 6, Hardened Runtime).
- **Kabul:** `go build ./...` ve `xcodegen && xcodebuild build` boş iskeletle geçer.

### Faz 1 — Ajan: toplayıcılar
- CPU (iş parçacığı başına, load, frekans), RAM/swap, disk (statfs + diskstats hız), ağ (varsayılan rota arayüzü otomatik bulunur), coretemp, applesmc fan, sistem (uptime, OS, apt, reboot-required).
- `HOST_PROC`/`HOST_SYS`/`HOST_ROOT` ile konteyner içinden host okunur.
- Sunucudan alınmış gerçek `/proc` ve `/sys` örnekleriyle tablo testleri; bozuk sensör (-127, 103) süzme testi.
- **Kabul:** `go test ./...` yeşil; `pulse-agent --once` sunucuda doğru JSON basar (SSH ile elle değil, deploy betiğiyle).

### Faz 2 — Ajan: Docker, yayın denetimi, sağlık, API
- Docker Engine API (socket proxy üzerinden): liste, `stats`, health, restart sayısı, günlük tail.
- Yayın denetimi (ayarlı URL'ler, 60 sn, 5 sn zaman aşımı).
- Sağlık puanı + `reasons`; Mole eşik testleri.
- HTTP: `/health`, `/v1/snapshot`, `/v1/stream` (SSE, keep-alive), `/v1/history`, logs; token, istek sınırı, zaman aşımı.
- `Dockerfile` (distroless), `deploy/compose.yaml`, `deploy/deploy.sh` (`docker --context macmini compose up -d --build` + `ssh … tailscale serve --bg --https=9123 http://127.0.0.1:9123`).
- **Kabul:** Mac'ten `curl -H "Authorization: Bearer …" https://macmini-server.taild883a6.ts.net:9123/v1/snapshot` gerçek veri döner; tokensız 401; ev ağından ve internetten erişilemez; ajan <20 MB RAM, <%1 CPU (`docker stats`).

### Faz 3 — Mac: çekirdek ve menü çubuğu
- `PulseCore` modelleri (şemayla birebir, `v` alanıyla sürüm kontrolü), `PulseClient` SSE (URLSession bytes, satır ayrıştırma, üstel geri çekilme 1→30 sn, uyku/uyanma ve ağ değişiminde yeniden bağlanma — `NWPathMonitor`).
- `NSStatusItem` + yedek glif, iki satırlı metrik etiketi, sağlık rengi; tıklayınca panel (`NSPanel`, odak kaybında kapanır).
- Ayarlar ilk açılış: sunucu adresi + token (Keychain), "Bağlantıyı sına".
- **Kabul:** menü çubuğunda canlı TMP/CPU/MEM; sunucu ajanı durdurulunca 5 sn içinde gri, açılınca kendiliğinden döner. Birim testleri (şema çözme, biçimlendirme, yeniden bağlanma durum makinesi).

### Faz 4 — Mac: panel tasarımı
- Başlık (puan, etiket, çipler, bağlantı noktası), 6 kutucuk (§3.1), Swift Charts ile çizgi/alan grafikleri, iş parçacığı çubukları.
- Liquid Glass panel zemini (`glassEffect`), koyu kutucuk yüzeyleri, tasarım belirteçleri `PulseUI/Tokens.swift`'te.
- Açık/koyu görünüm, "Saydamlığı azalt" ve "Hareketi azalt" desteği.
- **Kabul:** ekran görüntüsü `docs/design/`'a; Mole referansıyla yan yana göz kontrolü (Kutluhan onayı).

### Faz 5 — Konteynerler, yayınlar, alt şerit
- Konteyner tablosu (§3.2), günlük penceresi, yayınlar satırı, hızlı eylemler (SSH/Portainer/Cockpit), sayaçlar, reboot rozeti.
- **Kabul:** 7 konteyner doğru durum/bellek/CPU; bir test konteynerini durdurunca kırmızıya döner ve puan düşer (Kutluhan'ın onayıyla, perde-test-samba gibi kritik olmayan biriyle).

### Faz 6 — Bildirimler ve ayarlar
- Kurallar (histerezis + 10 dk bekleme): sıcaklık >85°C 30 sn, RAM >%90 60 sn, disk >%85, konteyner unhealthy/exited, yayın düştü (2 ardışık hata), sunucuya 60 sn ulaşılamıyor; düzelince "düzeldi" bildirimi.
- Ayarlar penceresi: bağlantı, menü çubuğu alanları, eşikler, bildirim aç/kapa, yayın listesi (ajan `.env`'inden okunur, uygulamada salt görüntü), girişte başlat (`SMAppService`).
- **Kabul:** her kural birim testli; gerçek bildirim bir kez elle tetiklenip görülür.

### Faz 7 — Cilalama ve kalite
- TR/EN String Catalog, VoiceOver etiketleri, klavye (⌘, ayarlar, Esc kapat).
- Performans: Mac uygulaması boşta <%0,5 CPU, <60 MB RAM; panel kapalıyken grafik çizimi yok.
- `swiftlint`/`golangci-lint`, `govulncheck`, testler.
- **Kabul:** tüm testler ve lint yeşil; 24 saat kesintisiz çalışma sonrası bellek sızıntısı yok.

### Faz 8 — Yayın (açık kaynak)
- README (readme-tema: animasyonlu hero SVG, EN detay + TR özet, kurulum: "kendi sunucuna kur" adımları; IP/ad sabit kodlanmaz).
- GitHub Actions: Go test + lint, Swift build/test, `ghcr.io/kutluhangil/pulse-agent` çok mimarili imaj (amd64 + arm64), etiketle sürüm.
- `scripts/release-macos.sh`: Release derleme, ad-hoc imza (Developer ID yok — `macos-adhoc-imza` dersi), DMG, GitHub Release.
- Kayıtlar: `~/.config/agents/macmini-server.md`'ye satır, beyinde proje notu, `Aktif.md`.
- **Kabul:** temiz bir Mac'te DMG kurulup yalnız adres + token girilerek çalışır.

### Sonra (v2 adayları)
- iPhone/iPad uygulaması + widget (aynı API, `PulseCore` paylaşılır).
- Konteyner yeniden başlatma (açık onay ile; proxy'de yalnız `POST /containers/{id}/restart`).
- Kalıcı geçmiş (7 gün, SQLite) ve "dün gece ne oldu" grafiği.
- Birden fazla sunucu.
- PriceSpawn gece işlerinin (cron) son çalışma sonucu kutucuğu.

---

## 8. Varsayılan kararlar (Kutluhan değiştirebilir)
1. **Lisans GPL-3.0** — Mole'un sağlık puanı mantığı uyarlandığı için zorunlu. MIT istenirse puanı sıfırdan, farklı formülle yazarız.
2. **Fan yalnız gösterilir**, kontrol edilmez (`macfanctld` kuralı).
3. **v1 salt okunur** — konteyner başlat/durdur yok.
4. **Erişim yalnız Tailscale** — internetten (Cloudflare) erişim yok; Mac her zaman tailnet'te.
5. **Port 9123**, adres `https://macmini-server.taild883a6.ts.net:9123`.
6. **Bundle ID** `com.kutluhangul.pulse`, minimum macOS 26.
