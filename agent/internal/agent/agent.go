// Package agent runs the sampling loops and fans snapshots out to subscribers.
package agent

import (
	"context"
	"encoding/json"
	"log/slog"
	"sync"
	"time"

	"github.com/kutluhangil/pulse/agent/internal/collect"
	"github.com/kutluhangil/pulse/agent/internal/docker"
	"github.com/kutluhangil/pulse/agent/internal/health"
	"github.com/kutluhangil/pulse/agent/internal/history"
	"github.com/kutluhangil/pulse/agent/internal/model"
	"github.com/kutluhangil/pulse/agent/internal/probe"
)

type Config struct {
	Version      string
	Machine      *collect.Machine
	Docker       *docker.Client // nil disables container monitoring
	Probes       *probe.Checker // nil disables probes
	MachineEvery time.Duration
	DockerEvery  time.Duration
	ProbeEvery   time.Duration
	SystemEvery  time.Duration
	Log          *slog.Logger
}

type Agent struct {
	cfg     Config
	static  collect.StaticHost
	History *history.Store

	mu         sync.RWMutex
	snap       model.Snapshot
	encoded    []byte
	containers []model.Container
	dockerSt   model.DockerState
	probes     []model.Probe
	system     model.System

	subMu sync.Mutex
	subs  map[chan []byte]struct{}
}

func New(cfg Config) *Agent {
	if cfg.MachineEvery == 0 {
		cfg.MachineEvery = time.Second
	}
	if cfg.DockerEvery == 0 {
		cfg.DockerEvery = 5 * time.Second
	}
	if cfg.ProbeEvery == 0 {
		cfg.ProbeEvery = time.Minute
	}
	if cfg.SystemEvery == 0 {
		cfg.SystemEvery = 5 * time.Minute
	}
	if cfg.Log == nil {
		cfg.Log = slog.Default()
	}
	a := &Agent{
		cfg:        cfg,
		static:     collect.ReadStaticHost(cfg.Machine.FS),
		History:    history.New(),
		containers: []model.Container{},
		probes:     []model.Probe{},
		subs:       map[chan []byte]struct{}{},
	}
	a.system = collect.ReadSystem(cfg.Machine.FS)
	if cfg.Docker == nil {
		a.dockerSt = model.DockerState{Available: false}
	}
	return a
}

// Run blocks until ctx is cancelled.
func (a *Agent) Run(ctx context.Context) {
	if a.cfg.Docker != nil {
		go a.every(ctx, a.cfg.DockerEvery, a.pollDocker)
	}
	if a.cfg.Probes != nil && len(a.cfg.Probes.Targets) > 0 {
		go a.every(ctx, a.cfg.ProbeEvery, a.pollProbes)
	}
	go a.every(ctx, a.cfg.SystemEvery, func(context.Context) {
		s := collect.ReadSystem(a.cfg.Machine.FS)
		a.mu.Lock()
		a.system = s
		a.mu.Unlock()
	})
	a.every(ctx, a.cfg.MachineEvery, func(context.Context) { a.tick(time.Now()) })
}

func (a *Agent) every(ctx context.Context, d time.Duration, fn func(context.Context)) {
	fn(ctx)
	t := time.NewTicker(d)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			fn(ctx)
		}
	}
}

func (a *Agent) pollDocker(ctx context.Context) {
	ctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	st := model.DockerState{Available: true}
	list, err := a.cfg.Docker.Containers(ctx)
	if err == nil {
		st.Version, err = a.cfg.Docker.Version(ctx)
	}
	if err != nil {
		a.cfg.Log.Warn("docker poll failed", "err", err)
		st = model.DockerState{Available: false, Error: err.Error()}
		list = []model.Container{}
	}
	a.mu.Lock()
	a.containers, a.dockerSt = list, st
	a.mu.Unlock()
}

func (a *Agent) pollProbes(ctx context.Context) {
	res := a.cfg.Probes.Run(ctx)
	a.mu.Lock()
	a.probes = res
	a.mu.Unlock()
}

// tick takes one machine sample and publishes a fresh snapshot.
func (a *Agent) tick(now time.Time) {
	ms, err := a.cfg.Machine.Sample(now)
	if err != nil {
		a.cfg.Log.Error("machine sample failed", "err", err)
		return
	}
	a.mu.RLock()
	snap := model.Snapshot{
		V:  model.SchemaVersion,
		TS: now.UTC().Truncate(time.Millisecond),
		Host: model.Host{
			Name: a.static.Name, CPUModel: a.static.CPUModel, Cores: a.static.Cores, Threads: a.static.Threads,
			MemTotal: ms.Mem.Total, OS: a.static.OS, Kernel: a.static.Kernel,
			UptimeSec: ms.UptimeSec, AgentVersion: a.cfg.Version,
		},
		CPU: ms.CPU, Thermal: ms.Thermal, Fan: ms.Fan, Mem: ms.Mem, Disks: ms.Disks, Net: ms.Net,
		Containers: a.containers, Docker: a.dockerSt, Probes: a.probes, System: a.system,
	}
	a.mu.RUnlock()
	snap.Health = health.Score(&snap)

	encoded, err := json.Marshal(snap)
	if err != nil {
		a.cfg.Log.Error("encode snapshot", "err", err)
		return
	}
	a.mu.Lock()
	a.snap, a.encoded = snap, encoded
	a.mu.Unlock()

	p := model.Point{T: now.Unix(), CPU: snap.CPU.Usage, Mem: collect.MemUsedPct(snap.Mem),
		Temp: snap.Thermal.PackageC, Rx: snap.Net.RxBps, Tx: snap.Net.TxBps}
	if len(snap.Disks) > 0 {
		p.DR, p.DW = snap.Disks[0].ReadBps, snap.Disks[0].WriteBps
	}
	a.History.Add(p)
	a.broadcast(encoded)
}

// Snapshot returns the latest encoded snapshot (nil before the first tick).
func (a *Agent) Snapshot() []byte {
	a.mu.RLock()
	defer a.mu.RUnlock()
	return a.encoded
}

// Containers returns the latest container list.
func (a *Agent) Containers() []model.Container {
	a.mu.RLock()
	defer a.mu.RUnlock()
	return a.containers
}

func (a *Agent) Docker() *docker.Client { return a.cfg.Docker }

// Subscribe returns a channel receiving every new encoded snapshot. Slow
// readers miss snapshots instead of blocking the loop.
func (a *Agent) Subscribe() (<-chan []byte, func()) {
	ch := make(chan []byte, 2)
	a.subMu.Lock()
	a.subs[ch] = struct{}{}
	a.subMu.Unlock()
	return ch, func() {
		a.subMu.Lock()
		delete(a.subs, ch)
		a.subMu.Unlock()
	}
}

func (a *Agent) broadcast(b []byte) {
	a.subMu.Lock()
	defer a.subMu.Unlock()
	for ch := range a.subs {
		select {
		case ch <- b:
		default:
		}
	}
}

// Once collects everything a single time (two machine samples one second
// apart so rates are real) and returns the snapshot. Used by --once.
func (a *Agent) Once(ctx context.Context) model.Snapshot {
	if a.cfg.Docker != nil {
		a.pollDocker(ctx)
	}
	if a.cfg.Probes != nil {
		a.pollProbes(ctx)
	}
	a.tick(time.Now())
	time.Sleep(time.Second)
	if a.cfg.Docker != nil {
		a.pollDocker(ctx)
	}
	a.tick(time.Now())
	a.mu.RLock()
	defer a.mu.RUnlock()
	return a.snap
}
