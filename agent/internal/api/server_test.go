package api

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/kutluhangil/pulse/agent/internal/agent"
	"github.com/kutluhangil/pulse/agent/internal/collect"
	"github.com/kutluhangil/pulse/agent/internal/model"
)

const token = "test-token-0123456789abcdef"

func newServer(t *testing.T) (*httptest.Server, context.CancelFunc) {
	t.Helper()
	base, _ := filepath.Abs("../../testdata/macmini")
	fs := collect.HostFS{Proc: filepath.Join(base, "proc"), Sys: filepath.Join(base, "sys"), Root: filepath.Join(base, "root")}
	a := agent.New(agent.Config{
		Version:      "test",
		Machine:      collect.NewMachine(fs, ""),
		MachineEvery: 50 * time.Millisecond,
		Log:          slog.New(slog.NewTextHandler(io.Discard, nil)),
	})
	ctx, cancel := context.WithCancel(context.Background())
	go a.Run(ctx)
	srv := httptest.NewServer((&Server{Agent: a, Token: token, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}).Handler())
	t.Cleanup(func() { cancel(); srv.Close() })
	// wait for the first tick
	for range 50 {
		if a.Snapshot() != nil {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	return srv, cancel
}

func get(t *testing.T, url, tok string) *http.Response {
	t.Helper()
	req, _ := http.NewRequest(http.MethodGet, url, nil)
	if tok != "" {
		req.Header.Set("Authorization", "Bearer "+tok)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func TestHealthIsPublic(t *testing.T) {
	srv, _ := newServer(t)
	resp := get(t, srv.URL+"/health", "")
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Errorf("status %d", resp.StatusCode)
	}
}

func TestAuthRequired(t *testing.T) {
	srv, _ := newServer(t)
	for _, tok := range []string{"", "wrong-token-wrong-token-xx"} {
		resp := get(t, srv.URL+"/v1/snapshot", tok)
		resp.Body.Close()
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("token %q: status %d", tok, resp.StatusCode)
		}
	}
}

func TestSnapshot(t *testing.T) {
	srv, _ := newServer(t)
	resp := get(t, srv.URL+"/v1/snapshot", token)
	defer resp.Body.Close()
	if resp.StatusCode != 200 || resp.Header.Get("Cache-Control") != "no-store" {
		t.Fatalf("status %d headers %v", resp.StatusCode, resp.Header)
	}
	var s model.Snapshot
	if err := json.NewDecoder(resp.Body).Decode(&s); err != nil {
		t.Fatal(err)
	}
	if s.V != model.SchemaVersion || s.Host.Threads != 8 || s.Health.Score == 0 || s.Fan == nil {
		t.Errorf("snapshot = %+v", s)
	}
	if s.Containers == nil || s.Probes == nil {
		t.Error("lists must encode as [] not null")
	}
}

func TestStream(t *testing.T) {
	srv, _ := newServer(t)
	resp := get(t, srv.URL+"/v1/stream", token)
	defer resp.Body.Close()
	if ct := resp.Header.Get("Content-Type"); ct != "text/event-stream" {
		t.Fatalf("content-type %q", ct)
	}
	sc := bufio.NewScanner(resp.Body)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	events := 0
	deadline := time.After(3 * time.Second)
	for events < 2 {
		select {
		case <-deadline:
			t.Fatalf("only %d events", events)
		default:
		}
		if !sc.Scan() {
			t.Fatal("stream closed", sc.Err())
		}
		if data, ok := strings.CutPrefix(sc.Text(), "data: "); ok {
			var s model.Snapshot
			if err := json.Unmarshal([]byte(data), &s); err != nil {
				t.Fatal(err)
			}
			events++
		}
	}
}

func TestHistoryAndLogs(t *testing.T) {
	srv, _ := newServer(t)
	resp := get(t, srv.URL+"/v1/history?range=10m", token)
	var h model.History
	_ = json.NewDecoder(resp.Body).Decode(&h)
	resp.Body.Close()
	if h.Range != "10m" || len(h.Points) == 0 {
		t.Errorf("history = %+v", h)
	}
	resp = get(t, srv.URL+"/v1/containers/aaaaaaaaaaaa/logs", token)
	resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("logs without docker: %d", resp.StatusCode)
	}
}
