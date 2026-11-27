package collect

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/kutluhangil/pulse/agent/internal/model"
)

// cpuTimes holds the jiffy counters of one /proc/stat "cpu" line.
type cpuTimes struct {
	total, idle, iowait uint64
}

func readCPUTimes(path string) (total cpuTimes, perThread []cpuTimes, err error) {
	f, err := os.Open(path)
	if err != nil {
		return total, nil, err
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 64*1024), 1024*1024) // the intr line is long
	for sc.Scan() {
		line := sc.Text()
		if !strings.HasPrefix(line, "cpu") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 5 {
			continue
		}
		var t cpuTimes
		for i, raw := range fields[1:] {
			v, perr := strconv.ParseUint(raw, 10, 64)
			if perr != nil {
				return total, nil, fmt.Errorf("parse %s: %w", fields[0], perr)
			}
			// guest and guest_nice (fields 9, 10) are already counted in user/nice.
			if i >= 8 {
				break
			}
			t.total += v
			switch i {
			case 3:
				t.idle += v
			case 4:
				t.idle += v
				t.iowait = v
			}
		}
		if fields[0] == "cpu" {
			total = t
		} else {
			perThread = append(perThread, t)
		}
	}
	return total, perThread, sc.Err()
}

func usageBetween(prev, cur cpuTimes) (usage, iowait float64) {
	dt := float64(cur.total - prev.total)
	if cur.total <= prev.total || dt == 0 {
		return 0, 0
	}
	busy := dt - float64(cur.idle-prev.idle)
	return clampPct(busy / dt * 100), clampPct(float64(cur.iowait-prev.iowait) / dt * 100)
}

func clampPct(v float64) float64 {
	switch {
	case v < 0:
		return 0
	case v > 100:
		return 100
	}
	return v
}

func readLoad(path string) ([3]float64, error) {
	var load [3]float64
	s, err := readTrim(path)
	if err != nil {
		return load, err
	}
	f := strings.Fields(s)
	if len(f) < 3 {
		return load, fmt.Errorf("loadavg: unexpected %q", s)
	}
	for i := range 3 {
		load[i], _ = strconv.ParseFloat(f[i], 64)
	}
	return load, nil
}

// cpuInfo returns the model name, physical core count and the mean current frequency.
func cpuInfo(path string) (modelName string, cores int, meanMHz float64) {
	f, err := os.Open(path)
	if err != nil {
		return "", 0, 0
	}
	defer f.Close()

	var mhzSum float64
	var mhzN int
	coreIDs := map[string]struct{}{}
	physID := ""
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		key, val, ok := strings.Cut(sc.Text(), ":")
		if !ok {
			continue
		}
		key, val = strings.TrimSpace(key), strings.TrimSpace(val)
		switch key {
		case "model name":
			if modelName == "" {
				modelName = cleanCPUModel(val)
			}
		case "cpu MHz":
			if v, err := strconv.ParseFloat(val, 64); err == nil {
				mhzSum += v
				mhzN++
			}
		case "physical id":
			physID = val
		case "core id":
			coreIDs[physID+"/"+val] = struct{}{}
		}
	}
	if mhzN > 0 {
		meanMHz = mhzSum / float64(mhzN)
	}
	return modelName, len(coreIDs), meanMHz
}

// cleanCPUModel turns "Intel(R) Core(TM) i7-3615QM CPU @ 2.30GHz" into "Intel Core i7-3615QM".
func cleanCPUModel(s string) string {
	for _, junk := range []string{"(R)", "(TM)", "(tm)", " CPU"} {
		s = strings.ReplaceAll(s, junk, "")
	}
	if i := strings.Index(s, " @ "); i > 0 {
		s = s[:i]
	}
	return strings.Join(strings.Fields(s), " ")
}

// cpuSampler keeps the previous counters so each Sample returns usage since the last call.
type cpuSampler struct {
	prevTotal  cpuTimes
	prevThread []cpuTimes
	primed     bool
}

func (s *cpuSampler) Sample(fs HostFS) (model.CPU, error) {
	var out model.CPU
	total, threads, err := readCPUTimes(fs.proc("stat"))
	if err != nil {
		return out, err
	}
	out.PerThread = make([]float64, len(threads))
	if s.primed && len(threads) == len(s.prevThread) {
		out.Usage, out.IOWait = usageBetween(s.prevTotal, total)
		for i := range threads {
			out.PerThread[i], _ = usageBetween(s.prevThread[i], threads[i])
		}
	}
	s.prevTotal, s.prevThread, s.primed = total, threads, true

	out.Load, _ = readLoad(fs.proc("loadavg"))
	_, _, out.FreqMHz = cpuInfo(fs.proc("cpuinfo"))
	return out, nil
}
