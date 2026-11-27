package collect

import (
	"bufio"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/kutluhangil/pulse/agent/internal/model"
)

const diskSectorBytes = 512 // /proc/diskstats always counts 512-byte sectors

type ioCounters struct{ readBytes, writeBytes uint64 }

// physicalDisks lists block devices backed by hardware (they have a "device"
// link); loop, dm and ram devices are skipped so I/O is not double counted.
func physicalDisks(fs HostFS) map[string]bool {
	out := map[string]bool{}
	entries, err := os.ReadDir(fs.sys("block"))
	if err != nil {
		return out
	}
	for _, e := range entries {
		if _, err := os.Stat(fs.sys("block", e.Name(), "device")); err == nil {
			out[e.Name()] = true
		}
	}
	return out
}

func readDiskIO(path string, disks map[string]bool) (ioCounters, error) {
	var c ioCounters
	f, err := os.Open(path)
	if err != nil {
		return c, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) < 10 || !disks[fields[2]] {
			continue
		}
		r, _ := strconv.ParseUint(fields[5], 10, 64)
		w, _ := strconv.ParseUint(fields[9], 10, 64)
		c.readBytes += r * diskSectorBytes
		c.writeBytes += w * diskSectorBytes
	}
	return c, sc.Err()
}

// rootDevice finds the device mounted at "/" in the host's mount table.
func rootDevice(fs HostFS) string {
	for _, p := range []string{fs.proc("1", "mounts"), fs.proc("mounts")} {
		f, err := os.Open(p)
		if err != nil {
			continue
		}
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			fields := strings.Fields(sc.Text())
			if len(fields) >= 2 && fields[1] == "/" && fields[0] != "overlay" && fields[0] != "rootfs" {
				f.Close()
				return strings.TrimPrefix(fields[0], "/dev/mapper/")
			}
		}
		f.Close()
	}
	return ""
}

type diskSampler struct {
	disks  map[string]bool
	prev   ioCounters
	prevAt time.Time
}

func (s *diskSampler) Sample(fs HostFS, now time.Time) []model.Disk {
	if s.disks == nil {
		s.disks = physicalDisks(fs)
	}
	d := model.Disk{Mount: "/", Device: rootDevice(fs)}
	if st, err := statFS(fs.Root); err == nil {
		d.Total, d.Free = st.total, st.avail
		d.Used = st.total - st.free
	}
	if io, err := readDiskIO(fs.proc("diskstats"), s.disks); err == nil {
		if !s.prevAt.IsZero() {
			secs := now.Sub(s.prevAt).Seconds()
			d.ReadBps = rate(s.prev.readBytes, io.readBytes, secs)
			d.WriteBps = rate(s.prev.writeBytes, io.writeBytes, secs)
		}
		s.prev, s.prevAt = io, now
	}
	return []model.Disk{d}
}

// rate returns bytes per second between two monotonically increasing counters.
// A counter reset (reboot, wrap) yields 0 rather than a huge spike.
func rate(prev, cur uint64, secs float64) uint64 {
	if secs <= 0 || cur < prev {
		return 0
	}
	return uint64(float64(cur-prev) / secs)
}
