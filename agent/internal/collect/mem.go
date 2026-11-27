package collect

import (
	"bufio"
	"os"
	"strconv"
	"strings"

	"github.com/kutluhangil/pulse/agent/internal/model"
)

// readMem parses /proc/meminfo. "Used" follows the free(1) definition:
// total - available, so page cache does not count as used memory.
func readMem(path string) (model.Mem, error) {
	var m model.Mem
	f, err := os.Open(path)
	if err != nil {
		return m, err
	}
	defer f.Close()

	kv := map[string]uint64{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		key, rest, ok := strings.Cut(sc.Text(), ":")
		if !ok {
			continue
		}
		fields := strings.Fields(rest)
		if len(fields) == 0 {
			continue
		}
		v, err := strconv.ParseUint(fields[0], 10, 64)
		if err != nil {
			continue
		}
		if len(fields) > 1 && fields[1] == "kB" {
			v *= 1024
		}
		kv[key] = v
	}
	if err := sc.Err(); err != nil {
		return m, err
	}

	m.Total = kv["MemTotal"]
	m.Available = kv["MemAvailable"]
	m.Cached = kv["Cached"] + kv["Buffers"] + kv["SReclaimable"]
	if m.Total > m.Available {
		m.Used = m.Total - m.Available
	}
	m.SwapTotal = kv["SwapTotal"]
	if m.SwapTotal > kv["SwapFree"] {
		m.SwapUsed = m.SwapTotal - kv["SwapFree"]
	}
	return m, nil
}

func memUsedPct(m model.Mem) float64 {
	if m.Total == 0 {
		return 0
	}
	return float64(m.Used) / float64(m.Total) * 100
}
