// Package probe checks that public endpoints (Cloudflare Tunnel sites) answer.
package probe

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/kutluhangil/pulse/agent/internal/model"
)

type Target struct {
	Name string
	URL  string
}

// ParseTargets reads "name=https://a,other=https://b". Only http(s) URLs are accepted.
func ParseTargets(spec string) ([]Target, error) {
	var out []Target
	for _, part := range strings.Split(spec, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		name, raw, ok := strings.Cut(part, "=")
		if !ok || strings.TrimSpace(name) == "" {
			return nil, fmt.Errorf("probe %q: want name=url", part)
		}
		u, err := url.Parse(strings.TrimSpace(raw))
		if err != nil || (u.Scheme != "https" && u.Scheme != "http") || u.Host == "" {
			return nil, fmt.Errorf("probe %q: invalid url", part)
		}
		out = append(out, Target{Name: strings.TrimSpace(name), URL: u.String()})
	}
	return out, nil
}

type Checker struct {
	Client  *http.Client
	Targets []Target
}

func NewChecker(targets []Target) *Checker {
	return &Checker{
		Targets: targets,
		Client: &http.Client{
			Timeout: 8 * time.Second,
			CheckRedirect: func(_ *http.Request, via []*http.Request) error {
				if len(via) >= 3 {
					return http.ErrUseLastResponse
				}
				return nil
			},
		},
	}
}

// Run checks every target concurrently. Any 2xx/3xx answer counts as up.
func (c *Checker) Run(ctx context.Context) []model.Probe {
	out := make([]model.Probe, len(c.Targets))
	var wg sync.WaitGroup
	for i, t := range c.Targets {
		wg.Add(1)
		go func() {
			defer wg.Done()
			out[i] = c.check(ctx, t)
		}()
	}
	wg.Wait()
	return out
}

func (c *Checker) check(ctx context.Context, t Target) model.Probe {
	p := model.Probe{Name: t.Name, URL: t.URL, CheckedAt: time.Now().UTC()}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, t.URL, nil)
	if err != nil {
		p.Error = err.Error()
		return p
	}
	req.Header.Set("User-Agent", "pulse-agent (uptime probe)")
	start := time.Now()
	resp, err := c.Client.Do(req)
	p.Ms = int(time.Since(start).Milliseconds())
	if err != nil {
		p.Error = shortErr(err)
		return p
	}
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
	resp.Body.Close()
	p.Status = resp.StatusCode
	p.OK = resp.StatusCode >= 200 && resp.StatusCode < 400
	return p
}

func shortErr(err error) string {
	s := err.Error()
	if i := strings.LastIndex(s, ": "); i >= 0 && i+2 < len(s) {
		s = s[i+2:]
	}
	return s
}
