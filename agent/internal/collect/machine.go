package collect

import (
	"time"

	"github.com/kutluhangil/pulse/agent/internal/model"
)

// Machine samples every host metric that is cheap enough to read each second.
// Rates (CPU %, bytes/s) are relative to the previous Sample call, so the
// first call returns zeros for them.
type Machine struct {
	FS   HostFS
	cpu  cpuSampler
	disk diskSampler
	net  netSampler
}

type MachineSample struct {
	CPU       model.CPU
	Thermal   model.Thermal
	Fan       *model.Fan
	Mem       model.Mem
	Disks     []model.Disk
	Net       model.Net
	UptimeSec uint64
}

func NewMachine(fs HostFS, netIface string) *Machine {
	return &Machine{FS: fs, net: netSampler{Iface: netIface}}
}

func (m *Machine) Sample(now time.Time) (MachineSample, error) {
	var s MachineSample
	var err error
	if s.CPU, err = m.cpu.Sample(m.FS); err != nil {
		return s, err
	}
	if s.Mem, err = readMem(m.FS.proc("meminfo")); err != nil {
		return s, err
	}
	s.Thermal = readThermal(m.FS)
	s.Fan = readFan(m.FS)
	s.Disks = m.disk.Sample(m.FS, now)
	s.Net = m.net.Sample(m.FS, now)
	s.UptimeSec = readUptime(m.FS)
	return s, nil
}

// MemUsedPct exposes the used-memory percentage for health and history.
func MemUsedPct(m model.Mem) float64 { return memUsedPct(m) }
