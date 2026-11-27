// Package collect reads machine metrics straight from procfs and sysfs.
// All paths go through HostFS so the agent can run in a container with the
// host's /proc, /sys and / bind-mounted read-only, and so tests can point at
// recorded fixtures.
package collect

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type HostFS struct {
	Proc string // host /proc
	Sys  string // host /sys
	Root string // host /
}

func DefaultHostFS() HostFS {
	return HostFS{
		Proc: envOr("PULSE_HOST_PROC", "/proc"),
		Sys:  envOr("PULSE_HOST_SYS", "/sys"),
		Root: envOr("PULSE_HOST_ROOT", "/"),
	}
}

func (h HostFS) proc(p ...string) string { return filepath.Join(append([]string{h.Proc}, p...)...) }
func (h HostFS) sys(p ...string) string  { return filepath.Join(append([]string{h.Sys}, p...)...) }
func (h HostFS) root(p ...string) string { return filepath.Join(append([]string{h.Root}, p...)...) }

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func readTrim(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

func readInt(path string) (int64, error) {
	s, err := readTrim(path)
	if err != nil {
		return 0, err
	}
	return strconv.ParseInt(s, 10, 64)
}
