package docker

import (
	"context"
	"encoding/binary"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func fakeEngine(t *testing.T, total *uint64) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("GET /version", func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprint(w, `{"Version":"29.9.3"}`)
	})
	mux.HandleFunc("GET /containers/json", func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprint(w, `[
		 {"Id":"aaaaaaaaaaaa1111","Names":["/web-1"],"Image":"nginx","State":"running","Status":"Up 2 hours (healthy)","Created":1700000000,"Labels":{"com.docker.compose.project":"web"}},
		 {"Id":"bbbbbbbbbbbb2222","Names":["/job-1"],"Image":"busybox","State":"exited","Status":"Exited (1) 3 minutes ago","Created":1700000000,"Labels":{}}
		]`)
	})
	mux.HandleFunc("GET /containers/{id}/json", func(w http.ResponseWriter, r *http.Request) {
		if r.PathValue("id") == "bbbbbbbbbbbb2222" {
			fmt.Fprint(w, `{"RestartCount":3,"State":{"ExitCode":1},"Config":{"Tty":false}}`)
			return
		}
		fmt.Fprint(w, `{"RestartCount":0,"State":{"ExitCode":0,"Health":{"Status":"healthy"}},"Config":{"Tty":false}}`)
	})
	mux.HandleFunc("GET /containers/{id}/stats", func(w http.ResponseWriter, _ *http.Request) {
		// Each call: the container used 0.05 s of CPU while the 8-thread system
		// accumulated 8 s (1 s wall clock per thread).
		*total += 50_000_000
		calls := *total / 50_000_000
		fmt.Fprintf(w, `{"cpu_stats":{"cpu_usage":{"total_usage":%d},"system_cpu_usage":%d},
		  "memory_stats":{"usage":20000000,"limit":134217728,"stats":{"inactive_file":5000000}}}`,
			*total, calls*8_000_000_000)
	})
	mux.HandleFunc("GET /containers/{id}/logs", func(w http.ResponseWriter, _ *http.Request) {
		w.Write(frame(1, "hello\n"))
		w.Write(frame(2, "oops\n"))
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv
}

func frame(stream byte, s string) []byte {
	h := make([]byte, 8)
	h[0] = stream
	binary.BigEndian.PutUint32(h[4:], uint32(len(s)))
	return append(h, s...)
}

func TestContainers(t *testing.T) {
	var total uint64
	srv := fakeEngine(t, &total)
	c, err := New("tcp://" + strings.TrimPrefix(srv.URL, "http://"))
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	if v, err := c.Version(ctx); err != nil || v != "29.9.3" {
		t.Fatalf("version %q %v", v, err)
	}
	first, err := c.Containers(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(first) != 2 || first[0].Name != "job-1" || first[1].Name != "web-1" {
		t.Fatalf("containers = %+v", first)
	}
	job, web := first[0], first[1]
	if job.State != "exited" || job.ExitCode != 1 || job.RestartCount != 3 || job.Health != "none" {
		t.Errorf("job = %+v", job)
	}
	if web.Project != "web" || web.Health != "healthy" || web.MemBytes != 15_000_000 || web.CPU != 0 {
		t.Errorf("web first = %+v", web)
	}
	second, _ := c.Containers(ctx)
	// 0.05 s CPU over 8 s of system time = 0.625 %
	if got := second[1].CPU; got < 0.6 || got > 0.65 {
		t.Errorf("web cpu = %v, want ~0.625", got)
	}
}

func TestLogs(t *testing.T) {
	var total uint64
	srv := fakeEngine(t, &total)
	c, _ := New("tcp://" + strings.TrimPrefix(srv.URL, "http://"))
	if _, err := c.Logs(context.Background(), "../etc", 10); err != ErrBadID {
		t.Errorf("bad id accepted: %v", err)
	}
	out, err := c.Logs(context.Background(), "aaaaaaaaaaaa1111", 10)
	if err != nil || out != "hello\noops\n" {
		t.Errorf("logs = %q %v", out, err)
	}
}

func TestHelpers(t *testing.T) {
	cases := map[string]string{
		"Up 1 hour (healthy)":      "healthy",
		"Up 5 seconds (unhealthy)": "unhealthy",
		"Up 2s (health: starting)": "starting",
		"Exited (0) 2 days ago":    "none",
	}
	for in, want := range cases {
		if got := healthFromStatus(in); got != want {
			t.Errorf("%q -> %q, want %q", in, got, want)
		}
	}
	if cpuPercent(cpuSample{10, 100}, cpuSample{5, 200}) != 0 {
		t.Error("reset must give 0")
	}
	if demux([]byte("plain text log line")) != "plain text log line" {
		t.Error("non-multiplexed input must pass through")
	}
	if _, err := New("ftp://x"); err == nil {
		t.Error("ftp scheme accepted")
	}
}
