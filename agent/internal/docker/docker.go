// Package docker is a minimal read-only Docker Engine API client.
// In production it talks to a docker-socket-proxy that only allows GET
// requests on /containers and /version, never to the raw socket.
package docker

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/kutluhangil/pulse/agent/internal/model"
)

type Client struct {
	base string
	http *http.Client

	mu   sync.Mutex
	prev map[string]cpuSample // container id -> previous CPU counters
	tty  map[string]bool
}

type cpuSample struct{ total, system uint64 }

// New accepts DOCKER_HOST style addresses: unix:///var/run/docker.sock or tcp://127.0.0.1:2375.
func New(host string) (*Client, error) {
	u, err := url.Parse(host)
	if err != nil {
		return nil, fmt.Errorf("docker host %q: %w", host, err)
	}
	tr := &http.Transport{MaxIdleConns: 4, IdleConnTimeout: 30 * time.Second}
	base := ""
	switch u.Scheme {
	case "unix":
		sock := u.Path
		tr.DialContext = func(ctx context.Context, _, _ string) (net.Conn, error) {
			var d net.Dialer
			return d.DialContext(ctx, "unix", sock)
		}
		base = "http://docker"
	case "tcp", "http":
		base = "http://" + u.Host
	default:
		return nil, fmt.Errorf("docker host %q: unsupported scheme", host)
	}
	return &Client{
		base: base,
		http: &http.Client{Transport: tr, Timeout: 10 * time.Second},
		prev: map[string]cpuSample{},
		tty:  map[string]bool{},
	}, nil
}

func (c *Client) get(ctx context.Context, path string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.base+path, nil)
	if err != nil {
		return err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("docker %s: %s %s", path, resp.Status, strings.TrimSpace(string(b)))
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 8<<20)).Decode(out)
}

func (c *Client) Version(ctx context.Context) (string, error) {
	var v struct{ Version string }
	err := c.get(ctx, "/version", &v)
	return v.Version, err
}

type apiContainer struct {
	ID      string            `json:"Id"`
	Names   []string          `json:"Names"`
	Image   string            `json:"Image"`
	State   string            `json:"State"`
	Status  string            `json:"Status"`
	Created int64             `json:"Created"`
	Labels  map[string]string `json:"Labels"`
}

type apiInspect struct {
	RestartCount int `json:"RestartCount"`
	State        struct {
		ExitCode int `json:"ExitCode"`
		Health   *struct {
			Status string `json:"Status"`
		} `json:"Health"`
	} `json:"State"`
	Config struct {
		Tty bool `json:"Tty"`
	} `json:"Config"`
}

type apiStats struct {
	CPUStats struct {
		CPUUsage struct {
			TotalUsage uint64 `json:"total_usage"`
		} `json:"cpu_usage"`
		SystemUsage uint64 `json:"system_cpu_usage"`
	} `json:"cpu_stats"`
	MemoryStats struct {
		Usage uint64            `json:"usage"`
		Limit uint64            `json:"limit"`
		Stats map[string]uint64 `json:"stats"`
	} `json:"memory_stats"`
}

// Containers lists all containers with live CPU/memory for running ones.
// CPU percent is relative to the whole machine (0-100), measured between calls.
func (c *Client) Containers(ctx context.Context) ([]model.Container, error) {
	var list []apiContainer
	if err := c.get(ctx, "/containers/json?all=1", &list); err != nil {
		return nil, err
	}

	out := make([]model.Container, len(list))
	seen := make(map[string]bool, len(list))
	var wg sync.WaitGroup
	for i, ac := range list {
		seen[ac.ID] = true
		out[i] = model.Container{
			ID:         ac.ID,
			Name:       containerName(ac.Names),
			Project:    ac.Labels["com.docker.compose.project"],
			Image:      ac.Image,
			State:      ac.State,
			Health:     healthFromStatus(ac.Status),
			StatusText: ac.Status,
			CreatedAt:  time.Unix(ac.Created, 0).UTC(),
		}
		wg.Add(1)
		go func(dst *model.Container, running bool) {
			defer wg.Done()
			c.enrich(ctx, dst, running)
		}(&out[i], ac.State == "running")
	}
	wg.Wait()

	c.mu.Lock()
	for id := range c.prev {
		if !seen[id] {
			delete(c.prev, id)
			delete(c.tty, id)
		}
	}
	c.mu.Unlock()

	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

func (c *Client) enrich(ctx context.Context, dst *model.Container, running bool) {
	var ins apiInspect
	if err := c.get(ctx, "/containers/"+dst.ID+"/json", &ins); err == nil {
		dst.RestartCount = ins.RestartCount
		dst.ExitCode = ins.State.ExitCode
		if ins.State.Health != nil && ins.State.Health.Status != "" {
			dst.Health = ins.State.Health.Status
		}
		c.mu.Lock()
		c.tty[dst.ID] = ins.Config.Tty
		c.mu.Unlock()
	}
	if !running {
		return
	}
	var st apiStats
	if err := c.get(ctx, "/containers/"+dst.ID+"/stats?stream=false&one-shot=true", &st); err != nil {
		return
	}
	dst.MemBytes = containerMem(st)
	dst.MemLimit = st.MemoryStats.Limit
	cur := cpuSample{total: st.CPUStats.CPUUsage.TotalUsage, system: st.CPUStats.SystemUsage}
	c.mu.Lock()
	prev, ok := c.prev[dst.ID]
	c.prev[dst.ID] = cur
	c.mu.Unlock()
	if ok {
		dst.CPU = cpuPercent(prev, cur)
	}
}

// containerMem mirrors `docker stats`: usage minus reclaimable file cache.
func containerMem(st apiStats) uint64 {
	used := st.MemoryStats.Usage
	cache := st.MemoryStats.Stats["inactive_file"] // cgroup v2
	if cache == 0 {
		cache = st.MemoryStats.Stats["total_inactive_file"] // cgroup v1
	}
	if cache < used {
		used -= cache
	}
	return used
}

// cpuPercent: system_cpu_usage already sums every CPU, so the ratio is a share
// of the whole machine.
func cpuPercent(prev, cur cpuSample) float64 {
	if cur.total < prev.total || cur.system <= prev.system {
		return 0
	}
	p := float64(cur.total-prev.total) / float64(cur.system-prev.system) * 100
	if p > 100 {
		p = 100
	}
	return p
}

func containerName(names []string) string {
	if len(names) == 0 {
		return ""
	}
	return strings.TrimPrefix(names[0], "/")
}

func healthFromStatus(status string) string {
	switch {
	case strings.Contains(status, "(unhealthy)"):
		return "unhealthy"
	case strings.Contains(status, "(healthy)"):
		return "healthy"
	case strings.Contains(status, "(health: starting)"):
		return "starting"
	}
	return "none"
}

var idRe = regexp.MustCompile(`^[a-f0-9]{12,64}$`)

var ErrBadID = errors.New("invalid container id")

const maxLogTail = 500

// Logs returns the last tail lines (stdout and stderr) of a container as text.
func (c *Client) Logs(ctx context.Context, id string, tail int) (string, error) {
	if !idRe.MatchString(id) {
		return "", ErrBadID
	}
	if tail <= 0 || tail > maxLogTail {
		tail = 100
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		fmt.Sprintf("%s/containers/%s/logs?stdout=1&stderr=1&timestamps=1&tail=%d", c.base, id, tail), nil)
	if err != nil {
		return "", err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("docker logs: %s", resp.Status)
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return "", err
	}
	c.mu.Lock()
	tty := c.tty[id]
	c.mu.Unlock()
	if tty {
		return string(raw), nil
	}
	return demux(raw), nil
}

// demux strips Docker's 8-byte stream headers from non-TTY log output.
func demux(b []byte) string {
	var sb strings.Builder
	for len(b) >= 8 {
		if b[0] > 2 || b[1] != 0 || b[2] != 0 || b[3] != 0 {
			sb.Write(b) // not multiplexed after all
			return sb.String()
		}
		n := int(binary.BigEndian.Uint32(b[4:8]))
		b = b[8:]
		if n > len(b) {
			n = len(b)
		}
		sb.Write(b[:n])
		b = b[n:]
	}
	return sb.String()
}
