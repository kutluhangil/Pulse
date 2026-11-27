package health

import (
	"slices"
	"testing"
	"time"

	"github.com/kutluhangil/pulse/agent/internal/model"
)

func idle() *model.Snapshot {
	return &model.Snapshot{
		CPU:     model.CPU{Usage: 3},
		Mem:     model.Mem{Total: 16 << 30, Used: 1 << 30, SwapTotal: 4 << 30},
		Disks:   []model.Disk{{Total: 100 << 30, Used: 50 << 30, Free: 46 << 30}},
		Thermal: model.Thermal{PackageC: 50},
		Docker:  model.DockerState{Available: true},
	}
}

func TestIdleServerIsPerfect(t *testing.T) {
	h := Score(idle())
	if h.Score != 100 || h.Label != "Excellent" || len(h.Reasons) != 0 {
		t.Errorf("got %+v", h)
	}
}

func TestPenaltyIsMonotonic(t *testing.T) {
	last := 0.0
	for v := 0.0; v <= 100; v += 0.5 {
		p := penalty(v, cpuNormal, cpuHigh, cpuWeight)
		if p < last {
			t.Fatalf("penalty dropped at %v: %v < %v", v, p, last)
		}
		last = p
	}
	if got := penalty(100, cpuNormal, cpuHigh, cpuWeight); got != cpuWeight {
		t.Errorf("full load penalty = %v, want %v", got, cpuWeight)
	}
	if got := penalty(cpuHigh, cpuNormal, cpuHigh, cpuWeight); got != cpuWeight/2 {
		t.Errorf("penalty at high threshold = %v", got)
	}
}

func TestHotAndBusy(t *testing.T) {
	s := idle()
	s.CPU.Usage = 100
	s.Thermal.PackageC = 90
	h := Score(s)
	// 100 - 30 (cpu) - 15 (thermal) = 55
	if h.Score != 55 || h.Label != "Fair" {
		t.Errorf("got %+v", h)
	}
	if !slices.Contains(h.Reasons, ReasonCPU) || !slices.Contains(h.Reasons, ReasonHot) {
		t.Errorf("reasons %v", h.Reasons)
	}
}

func TestContainersAndProbes(t *testing.T) {
	s := idle()
	s.Containers = []model.Container{
		{Name: "ok", State: "running", Health: "healthy"},
		{Name: "job", State: "exited", ExitCode: 0},
		{Name: "sick", State: "running", Health: "unhealthy"},
		{Name: "crash", State: "exited", ExitCode: 137},
		{Name: "loop", State: "restarting"},
		{Name: "dead", State: "dead"},
	}
	s.Probes = []model.Probe{{Name: "site", OK: false, CheckedAt: time.Now()}, {Name: "never", OK: false}}
	h := Score(s)
	// 4 failing containers capped at 30, one probe 10.
	if h.Score != 60 {
		t.Errorf("score = %d, want 60 (%v)", h.Score, h.Reasons)
	}
}

func TestSystemFlags(t *testing.T) {
	s := idle()
	s.System = model.System{RebootRequired: true, SecurityUpdates: 2}
	s.Mem.SwapUsed = 3 << 30
	h := Score(s)
	if h.Score != 90 {
		t.Errorf("score = %d, want 90 (%v)", h.Score, h.Reasons)
	}
}

func TestDiskFull(t *testing.T) {
	s := idle()
	s.Disks[0] = model.Disk{Total: 100 << 30, Used: 95 << 30, Free: 5 << 30}
	h := Score(s)
	// 95% -> 20 * (95-80)/20 = 15
	if h.Score != 85 || !slices.Contains(h.Reasons, ReasonDisk) {
		t.Errorf("got %+v", h)
	}
}

func TestLabels(t *testing.T) {
	for score, want := range map[int]string{100: "Excellent", 85: "Excellent", 84: "Good", 65: "Good", 50: "Fair", 44: "Needs Attention", 0: "Needs Attention"} {
		if got := Label(score); got != want {
			t.Errorf("Label(%d) = %q, want %q", score, got, want)
		}
	}
}
