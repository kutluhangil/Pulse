// Package health turns a snapshot into a 0-100 score.
//
// The resource part (weights, thresholds, piecewise penalties) is adapted from
// Mole's `mo status` health score by tw93 (https://github.com/tw93/Mole,
// cmd/status/metrics_health.go, GPL-3.0). Laptop-only signals (battery,
// uptime) are dropped; server signals (containers, public probes, swap,
// pending reboot) are added.
package health

import "github.com/kutluhangil/pulse/agent/internal/model"

const (
	cpuWeight     = 30.0
	memWeight     = 25.0
	diskWeight    = 20.0
	thermalWeight = 15.0
	ioWeight      = 10.0

	cpuNormal, cpuHigh         = 50.0, 85.0
	memNormal, memHigh         = 70.0, 88.0
	diskWarn, diskCrit         = 80.0, 93.0
	thermalNormal, thermalHigh = 65.0, 85.0
	ioNormalMBs, ioHighMBs     = 50.0, 150.0

	containerPenalty    = 10.0
	containerPenaltyMax = 30.0
	probePenalty        = 10.0
	swapPenalty         = 5.0
	rebootPenalty       = 3.0
	securityPenalty     = 2.0

	excellentAt, goodAt, fairAt = 85, 65, 45
)

// Reason codes; the app localizes them.
const (
	ReasonCPU        = "cpu_high"
	ReasonMem        = "mem_high"
	ReasonSwap       = "swap_high"
	ReasonDisk       = "disk_full"
	ReasonHot        = "overheating"
	ReasonIO         = "disk_io_heavy"
	ReasonContainer  = "container_down"
	ReasonProbe      = "site_down"
	ReasonReboot     = "reboot_required"
	ReasonSecurity   = "security_updates"
	ReasonDockerDown = "docker_unreachable"
)

// penalty grows linearly to weight/2 between normal and high, then keeps
// growing to the full weight at 100 so the score never rises as load worsens.
func penalty(v, normal, high, weight float64) float64 {
	switch {
	case v <= normal:
		return 0
	case v <= high:
		return (weight / 2) * (v - normal) / (high - normal)
	default:
		return weight * (v - normal) / (100 - normal)
	}
}

func Score(s *model.Snapshot) model.Health {
	score := 100.0
	reasons := []string{}
	add := func(code string) { reasons = append(reasons, code) }

	score -= penalty(s.CPU.Usage, cpuNormal, cpuHigh, cpuWeight)
	if s.CPU.Usage > cpuHigh {
		add(ReasonCPU)
	}

	memPct := pct(s.Mem.Used, s.Mem.Total)
	score -= penalty(memPct, memNormal, memHigh, memWeight)
	if memPct > memHigh {
		add(ReasonMem)
	}
	if s.Mem.SwapTotal > 0 && pct(s.Mem.SwapUsed, s.Mem.SwapTotal) > 50 {
		score -= swapPenalty
		add(ReasonSwap)
	}

	if len(s.Disks) > 0 {
		d := s.Disks[0]
		diskPct := pct(d.Used, d.Used+d.Free) // matches df: reserved blocks excluded
		score -= penalty(diskPct, diskWarn, diskCrit, diskWeight)
		if diskPct > 90 || (d.Total > 0 && d.Free < 10<<30) {
			add(ReasonDisk)
		}
		mbs := float64(d.ReadBps+d.WriteBps) / (1 << 20)
		switch {
		case mbs > ioHighMBs:
			score -= ioWeight
			add(ReasonIO)
		case mbs > ioNormalMBs:
			score -= ioWeight * (mbs - ioNormalMBs) / (ioHighMBs - ioNormalMBs)
		}
	}

	if t := s.Thermal.PackageC; t > thermalNormal {
		if t > thermalHigh {
			score -= thermalWeight
			add(ReasonHot)
		} else {
			score -= thermalWeight * (t - thermalNormal) / (thermalHigh - thermalNormal)
		}
	}

	if !s.Docker.Available && s.Docker.Error != "" {
		score -= containerPenalty
		add(ReasonDockerDown)
	}
	bad := 0.0
	for _, c := range s.Containers {
		if ContainerFailing(c) {
			bad += containerPenalty
		}
	}
	if bad > 0 {
		score -= min(bad, containerPenaltyMax)
		add(ReasonContainer)
	}

	for _, p := range s.Probes {
		if !p.OK && !p.CheckedAt.IsZero() {
			score -= probePenalty
			add(ReasonProbe)
			break
		}
	}

	if s.System.RebootRequired {
		score -= rebootPenalty
		add(ReasonReboot)
	}
	if s.System.SecurityUpdates > 0 {
		score -= securityPenalty
		add(ReasonSecurity)
	}

	score = max(0, min(100, score))
	return model.Health{Score: int(score), Label: Label(int(score)), Reasons: reasons}
}

// ContainerFailing is true for containers that need attention: unhealthy,
// restarting, dead, or exited with a non-zero code. A clean exit (code 0,
// e.g. a one-shot job) is not a failure.
func ContainerFailing(c model.Container) bool {
	switch c.State {
	case "restarting", "dead":
		return true
	case "exited":
		return c.ExitCode != 0
	}
	return c.Health == "unhealthy"
}

func Label(score int) string {
	switch {
	case score >= excellentAt:
		return "Excellent"
	case score >= goodAt:
		return "Good"
	case score >= fairAt:
		return "Fair"
	}
	return "Needs Attention"
}

func pct(part, total uint64) float64 {
	if total == 0 {
		return 0
	}
	return float64(part) / float64(total) * 100
}
