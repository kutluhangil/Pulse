package collect

import (
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/kutluhangil/pulse/agent/internal/model"
)

// Sensors outside this window are treated as broken. The Mac mini's applesmc
// reports -127 °C and 103 °C on unpopulated keys, so it is never used for
// temperatures; coretemp (or k10temp on AMD) is the source of truth.
const (
	minValidC = 1.0
	maxValidC = 125.0
)

var cpuTempDrivers = map[string]bool{"coretemp": true, "k10temp": true, "zenpower": true, "cpu_thermal": true}

func validTemp(c float64) bool { return c >= minValidC && c < maxValidC }

func readThermal(fs HostFS) model.Thermal {
	var out model.Thermal
	hwmons, _ := filepath.Glob(fs.sys("class", "hwmon", "hwmon*"))
	sort.Strings(hwmons)
	for _, dir := range hwmons {
		name, err := readTrim(filepath.Join(dir, "name"))
		if err != nil || !cpuTempDrivers[name] {
			continue
		}
		inputs, _ := filepath.Glob(filepath.Join(dir, "temp*_input"))
		type coreTemp struct {
			idx int
			c   float64
		}
		var cores []coreTemp
		for _, in := range inputs {
			milli, err := readInt(in)
			if err != nil {
				continue
			}
			c := float64(milli) / 1000
			if !validTemp(c) {
				continue
			}
			base := strings.TrimSuffix(in, "_input")
			label, _ := readTrim(base + "_label")
			switch {
			case strings.HasPrefix(label, "Package id"), label == "Tctl", label == "Tdie", label == "":
				if c > out.PackageC {
					out.PackageC = c
				}
				if crit, err := readInt(base + "_crit"); err == nil && crit > 0 {
					out.CritC = float64(crit) / 1000
				}
			case strings.HasPrefix(label, "Core "):
				idx, _ := strconv.Atoi(strings.TrimPrefix(label, "Core "))
				cores = append(cores, coreTemp{idx, c})
				if out.CritC == 0 {
					if crit, err := readInt(base + "_crit"); err == nil && crit > 0 {
						out.CritC = float64(crit) / 1000
					}
				}
			}
		}
		sort.Slice(cores, func(i, j int) bool { return cores[i].idx < cores[j].idx })
		for _, ct := range cores {
			out.CoresC = append(out.CoresC, ct.c)
		}
		if out.PackageC == 0 {
			for _, c := range out.CoresC {
				if c > out.PackageC {
					out.PackageC = c
				}
			}
		}
		break
	}
	if out.CoresC == nil {
		out.CoresC = []float64{}
	}
	return out
}

// readFan reads the first fan from applesmc (Intel Mac minis), falling back to
// any hwmon fan. Returns nil when the machine exposes no fan.
func readFan(fs HostFS) *model.Fan {
	smc := fs.sys("devices", "platform", "applesmc.768")
	if f := fanFrom(smc, "fan1"); f != nil {
		return f
	}
	hwmons, _ := filepath.Glob(fs.sys("class", "hwmon", "hwmon*"))
	sort.Strings(hwmons)
	for _, dir := range hwmons {
		if f := fanFrom(dir, "fan1"); f != nil {
			return f
		}
	}
	return nil
}

func fanFrom(dir, prefix string) *model.Fan {
	rpm, err := readInt(filepath.Join(dir, prefix+"_input"))
	if err != nil {
		return nil
	}
	f := &model.Fan{RPM: int(rpm), Label: "Fan"}
	if v, err := readInt(filepath.Join(dir, prefix+"_min")); err == nil {
		f.Min = int(v)
	}
	if v, err := readInt(filepath.Join(dir, prefix+"_max")); err == nil {
		f.Max = int(v)
	}
	if l, err := readTrim(filepath.Join(dir, prefix+"_label")); err == nil && l != "" {
		f.Label = l
	}
	return f
}
