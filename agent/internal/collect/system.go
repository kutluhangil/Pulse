package collect

import (
	"bufio"
	"os"
	"regexp"
	"strconv"
	"strings"

	"github.com/kutluhangil/pulse/agent/internal/model"
)

// StaticHost holds facts that do not change while the agent runs.
type StaticHost struct {
	Name     string
	CPUModel string
	Cores    int
	Threads  int
	OS       string
	Kernel   string
}

func ReadStaticHost(fs HostFS) StaticHost {
	var h StaticHost
	h.Name, _ = readTrim(fs.proc("sys", "kernel", "hostname"))
	if h.Name == "" {
		h.Name, _ = os.Hostname()
	}
	h.Kernel, _ = readTrim(fs.proc("sys", "kernel", "osrelease"))
	h.CPUModel, h.Cores, _ = cpuInfo(fs.proc("cpuinfo"))
	if _, threads, err := readCPUTimes(fs.proc("stat")); err == nil {
		h.Threads = len(threads)
	}
	if h.Cores == 0 {
		h.Cores = h.Threads
	}
	h.OS = osPrettyName(fs.root("etc", "os-release"))
	if h.OS == "" {
		h.OS = osPrettyName(fs.root("usr", "lib", "os-release"))
	}
	return h
}

func osPrettyName(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if v, ok := strings.CutPrefix(sc.Text(), "PRETTY_NAME="); ok {
			return strings.Trim(v, `"'`)
		}
	}
	return ""
}

func readUptime(fs HostFS) uint64 {
	s, err := readTrim(fs.proc("uptime"))
	if err != nil {
		return 0
	}
	first, _, _ := strings.Cut(s, " ")
	v, _ := strconv.ParseFloat(first, 64)
	return uint64(v)
}

var (
	aptTotalRe    = regexp.MustCompile(`(\d+) updates? can be applied`)
	aptSecurityRe = regexp.MustCompile(`(\d+) of these updates (?:is a|are) (?:standard )?security updates?`)
)

// ReadSystem reads Ubuntu's update-notifier summary and the reboot flag.
// Both are plain files maintained by the host; missing files mean "nothing pending".
func ReadSystem(fs HostFS) model.System {
	var s model.System
	if b, err := os.ReadFile(fs.root("var", "lib", "update-notifier", "updates-available")); err == nil {
		txt := string(b)
		if m := aptTotalRe.FindStringSubmatch(txt); m != nil {
			s.AptUpdates, _ = strconv.Atoi(m[1])
		}
		if m := aptSecurityRe.FindStringSubmatch(txt); m != nil {
			s.SecurityUpdates, _ = strconv.Atoi(m[1])
		}
	}
	if _, err := os.Stat(fs.root("run", "reboot-required")); err == nil {
		s.RebootRequired = true
	}
	return s
}
