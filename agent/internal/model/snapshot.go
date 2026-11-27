// Package model defines the JSON schema shared by the agent and the macOS app.
// Any change here must be mirrored in app/Packages/PulseCore and docs/API.md.
package model

import "time"

// SchemaVersion is bumped on breaking changes to Snapshot.
const SchemaVersion = 1

type Snapshot struct {
	V          int         `json:"v"`
	TS         time.Time   `json:"ts"`
	Host       Host        `json:"host"`
	Health     Health      `json:"health"`
	CPU        CPU         `json:"cpu"`
	Thermal    Thermal     `json:"thermal"`
	Fan        *Fan        `json:"fan"`
	Mem        Mem         `json:"mem"`
	Disks      []Disk      `json:"disks"`
	Net        Net         `json:"net"`
	Containers []Container `json:"containers"`
	Docker     DockerState `json:"docker"`
	Probes     []Probe     `json:"probes"`
	System     System      `json:"system"`
}

type Host struct {
	Name         string `json:"name"`
	CPUModel     string `json:"cpuModel"`
	Cores        int    `json:"cores"`
	Threads      int    `json:"threads"`
	MemTotal     uint64 `json:"memTotal"`
	OS           string `json:"os"`
	Kernel       string `json:"kernel"`
	UptimeSec    uint64 `json:"uptimeSec"`
	AgentVersion string `json:"agentVersion"`
}

type Health struct {
	Score   int      `json:"score"`
	Label   string   `json:"label"`
	Reasons []string `json:"reasons"`
}

type CPU struct {
	Usage     float64    `json:"usage"`
	PerThread []float64  `json:"perThread"`
	Load      [3]float64 `json:"load"`
	FreqMHz   float64    `json:"freqMHz"`
	IOWait    float64    `json:"ioWait"`
}

type Thermal struct {
	// PackageC is 0 when no usable sensor exists.
	PackageC float64   `json:"packageC"`
	CoresC   []float64 `json:"coresC"`
	CritC    float64   `json:"critC"`
}

type Fan struct {
	Label string `json:"label"`
	RPM   int    `json:"rpm"`
	Min   int    `json:"min"`
	Max   int    `json:"max"`
}

type Mem struct {
	Total     uint64 `json:"total"`
	Used      uint64 `json:"used"`
	Available uint64 `json:"available"`
	Cached    uint64 `json:"cached"`
	SwapTotal uint64 `json:"swapTotal"`
	SwapUsed  uint64 `json:"swapUsed"`
}

type Disk struct {
	Mount    string `json:"mount"`
	Device   string `json:"device"`
	Total    uint64 `json:"total"`
	Used     uint64 `json:"used"`
	Free     uint64 `json:"free"`
	ReadBps  uint64 `json:"readBps"`
	WriteBps uint64 `json:"writeBps"`
}

type Net struct {
	Iface     string `json:"iface"`
	SpeedMbps int    `json:"speedMbps"`
	RxBps     uint64 `json:"rxBps"`
	TxBps     uint64 `json:"txBps"`
	RxTotal   uint64 `json:"rxTotal"`
	TxTotal   uint64 `json:"txTotal"`
}

type Container struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	Project      string    `json:"project"`
	Image        string    `json:"image"`
	State        string    `json:"state"`  // running, exited, restarting, paused, created, dead
	Health       string    `json:"health"` // healthy, unhealthy, starting, none
	StatusText   string    `json:"statusText"`
	CPU          float64   `json:"cpu"` // percent of the whole machine (0-100)
	MemBytes     uint64    `json:"memBytes"`
	MemLimit     uint64    `json:"memLimit"`
	CreatedAt    time.Time `json:"createdAt"`
	ExitCode     int       `json:"exitCode"`
	RestartCount int       `json:"restartCount"`
}

type DockerState struct {
	Available bool   `json:"available"`
	Version   string `json:"version"`
	Error     string `json:"error,omitempty"`
}

type Probe struct {
	Name      string    `json:"name"`
	URL       string    `json:"url"`
	OK        bool      `json:"ok"`
	Status    int       `json:"status"`
	Ms        int       `json:"ms"`
	Error     string    `json:"error,omitempty"`
	CheckedAt time.Time `json:"checkedAt"`
}

type System struct {
	AptUpdates      int  `json:"aptUpdates"`
	SecurityUpdates int  `json:"securityUpdates"`
	RebootRequired  bool `json:"rebootRequired"`
}

// Point is one sample of the history ring buffers.
type Point struct {
	T    int64   `json:"t"` // unix seconds
	CPU  float64 `json:"cpu"`
	Mem  float64 `json:"mem"`  // used percent
	Temp float64 `json:"temp"` // package °C
	Rx   uint64  `json:"rx"`   // bytes/s
	Tx   uint64  `json:"tx"`
	DR   uint64  `json:"dr"` // disk read bytes/s
	DW   uint64  `json:"dw"`
}

type History struct {
	Range  string  `json:"range"`
	Step   int     `json:"step"` // seconds between points
	Points []Point `json:"points"`
}
