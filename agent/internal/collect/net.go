package collect

import (
	"bufio"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/kutluhangil/pulse/agent/internal/model"
)

// defaultRouteIface returns the interface carrying the IPv4 default route.
func defaultRouteIface(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Scan() // header
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) >= 8 && fields[1] == "00000000" && fields[7] == "00000000" {
			return fields[0]
		}
	}
	return ""
}

func readIfaceCounters(path, iface string) (rx, tx uint64, ok bool) {
	f, err := os.Open(path)
	if err != nil {
		return 0, 0, false
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		name, rest, found := strings.Cut(sc.Text(), ":")
		if !found || strings.TrimSpace(name) != iface {
			continue
		}
		fields := strings.Fields(rest)
		if len(fields) < 9 {
			return 0, 0, false
		}
		rx, _ = strconv.ParseUint(fields[0], 10, 64)
		tx, _ = strconv.ParseUint(fields[8], 10, 64)
		return rx, tx, true
	}
	return 0, 0, false
}

type netSampler struct {
	Iface          string // fixed interface; empty means follow the default route
	prevRx, prevTx uint64
	prevIface      string
	prevAt         time.Time
}

func (s *netSampler) Sample(fs HostFS, now time.Time) model.Net {
	iface := s.Iface
	if iface == "" {
		iface = defaultRouteIface(fs.proc("net", "route"))
	}
	out := model.Net{Iface: iface}
	if iface == "" {
		return out
	}
	if v, err := readInt(fs.sys("class", "net", iface, "speed")); err == nil && v > 0 {
		out.SpeedMbps = int(v)
	}
	rx, tx, ok := readIfaceCounters(fs.proc("net", "dev"), iface)
	if !ok {
		return out
	}
	out.RxTotal, out.TxTotal = rx, tx
	if iface == s.prevIface && !s.prevAt.IsZero() {
		secs := now.Sub(s.prevAt).Seconds()
		out.RxBps = rate(s.prevRx, rx, secs)
		out.TxBps = rate(s.prevTx, tx, secs)
	}
	s.prevRx, s.prevTx, s.prevIface, s.prevAt = rx, tx, iface, now
	return out
}
