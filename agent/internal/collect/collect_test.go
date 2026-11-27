package collect

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// fixture is a snapshot of macmini-server (Mac mini 2012, i7-3615QM,
// Ubuntu 24.04) recorded on 2026-11-27.
func fixture() HostFS {
	base, _ := filepath.Abs("../../testdata/macmini")
	return HostFS{Proc: filepath.Join(base, "proc"), Sys: filepath.Join(base, "sys"), Root: filepath.Join(base, "root")}
}

func TestStaticHost(t *testing.T) {
	h := ReadStaticHost(fixture())
	if h.CPUModel != "Intel Core i7-3615QM" {
		t.Errorf("cpu model = %q", h.CPUModel)
	}
	if h.Cores != 4 || h.Threads != 8 {
		t.Errorf("cores/threads = %d/%d, want 4/8", h.Cores, h.Threads)
	}
	if h.Name != "macmini-server" {
		t.Errorf("hostname = %q", h.Name)
	}
	if h.OS != "Ubuntu 24.04.5 LTS" {
		t.Errorf("os = %q", h.OS)
	}
	if h.Kernel == "" {
		t.Error("kernel empty")
	}
}

func TestCPUTimes(t *testing.T) {
	total, threads, err := readCPUTimes(fixture().proc("stat"))
	if err != nil {
		t.Fatal(err)
	}
	if len(threads) != 8 {
		t.Fatalf("threads = %d", len(threads))
	}
	// cpu  1482636 4874 421368 438597866 33188 0 23246 0 0 0
	if want := uint64(1482636 + 4874 + 421368 + 438597866 + 33188 + 0 + 23246 + 0); total.total != want {
		t.Errorf("total = %d, want %d", total.total, want)
	}
	if want := uint64(438597866 + 33188); total.idle != want {
		t.Errorf("idle = %d, want %d", total.idle, want)
	}
}

func TestUsageBetween(t *testing.T) {
	prev := cpuTimes{total: 1000, idle: 900, iowait: 10}
	cur := cpuTimes{total: 1100, idle: 950, iowait: 20}
	u, io := usageBetween(prev, cur)
	if u != 50 || io != 10 {
		t.Errorf("usage=%v iowait=%v, want 50/10", u, io)
	}
	if u, _ := usageBetween(cur, prev); u != 0 {
		t.Errorf("counter reset should give 0, got %v", u)
	}
}

func TestMem(t *testing.T) {
	m, err := readMem(fixture().proc("meminfo"))
	if err != nil {
		t.Fatal(err)
	}
	if m.Total < 15<<30 || m.Total > 17<<30 {
		t.Errorf("total = %d", m.Total)
	}
	if m.Used != m.Total-m.Available {
		t.Error("used must be total-available")
	}
	if m.SwapTotal < 4<<30-1<<20 || m.SwapTotal > 4<<30 { // 4 GiB swap file minus its header page
		t.Errorf("swap total = %d", m.SwapTotal)
	}
	if p := memUsedPct(m); p <= 0 || p >= 100 {
		t.Errorf("used pct = %v", p)
	}
}

func TestThermalFiltersAndOrders(t *testing.T) {
	th := readThermal(fixture())
	if th.PackageC < 30 || th.PackageC > 100 {
		t.Errorf("package = %v", th.PackageC)
	}
	if len(th.CoresC) != 4 {
		t.Fatalf("cores = %v", th.CoresC)
	}
	if th.CritC != 105 {
		t.Errorf("crit = %v", th.CritC)
	}
}

func TestThermalRejectsBrokenSensors(t *testing.T) {
	dir := t.TempDir()
	hw := filepath.Join(dir, "class", "hwmon", "hwmon0")
	must(t, os.MkdirAll(hw, 0o755))
	write(t, filepath.Join(hw, "name"), "coretemp")
	write(t, filepath.Join(hw, "temp1_label"), "Package id 0")
	write(t, filepath.Join(hw, "temp1_input"), "-127000")
	write(t, filepath.Join(hw, "temp2_label"), "Core 0")
	write(t, filepath.Join(hw, "temp2_input"), "48000")
	write(t, filepath.Join(hw, "temp3_label"), "Core 1")
	write(t, filepath.Join(hw, "temp3_input"), "130000")
	th := readThermal(HostFS{Sys: dir})
	if len(th.CoresC) != 1 || th.CoresC[0] != 48 {
		t.Errorf("cores = %v, want [48]", th.CoresC)
	}
	if th.PackageC != 48 {
		t.Errorf("package should fall back to hottest core, got %v", th.PackageC)
	}
}

func TestFan(t *testing.T) {
	f := readFan(fixture())
	if f == nil {
		t.Fatal("fan missing")
	}
	if f.Label != "Exhaust" || f.Min != 2000 || f.Max != 5500 || f.RPM < 1000 {
		t.Errorf("fan = %+v", f)
	}
	if readFan(HostFS{Sys: t.TempDir()}) != nil {
		t.Error("no fan should return nil")
	}
}

func TestNet(t *testing.T) {
	fs := fixture()
	if got := defaultRouteIface(fs.proc("net", "route")); got != "enp1s0f0" {
		t.Errorf("default iface = %q", got)
	}
	s := netSampler{}
	t0 := time.Unix(1000, 0)
	first := s.Sample(fs, t0)
	if first.SpeedMbps != 1000 || first.RxTotal == 0 {
		t.Errorf("first = %+v", first)
	}
	if first.RxBps != 0 {
		t.Error("first sample must not report a rate")
	}
	// Same counters one second later: rate is zero, not negative.
	second := s.Sample(fs, t0.Add(time.Second))
	if second.RxBps != 0 || second.TxBps != 0 {
		t.Errorf("second = %+v", second)
	}
}

func TestDisk(t *testing.T) {
	fs := fixture()
	disks := physicalDisks(fs)
	if !disks["sda"] || disks["dm-0"] || disks["loop0"] {
		t.Errorf("physical disks = %v", disks)
	}
	io, err := readDiskIO(fs.proc("diskstats"), disks)
	if err != nil || io.readBytes == 0 {
		t.Errorf("io = %+v err=%v", io, err)
	}
	if rate(100, 50, 1) != 0 {
		t.Error("counter reset must give 0")
	}
	if rate(0, 2048, 2) != 1024 {
		t.Error("rate math")
	}
}

func TestSystem(t *testing.T) {
	s := ReadSystem(fixture())
	if s.AptUpdates != 9 || s.SecurityUpdates != 2 {
		t.Errorf("apt = %d/%d, want 9/2", s.AptUpdates, s.SecurityUpdates)
	}
	if s.RebootRequired {
		t.Error("reboot flag should be false")
	}
}

func TestMachineSample(t *testing.T) {
	m := NewMachine(fixture(), "")
	s, err := m.Sample(time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if len(s.CPU.PerThread) != 8 || s.UptimeSec == 0 || s.Net.Iface != "enp1s0f0" {
		t.Errorf("sample = %+v", s)
	}
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func write(t *testing.T, path, s string) {
	t.Helper()
	must(t, os.WriteFile(path, []byte(s), 0o644))
}
