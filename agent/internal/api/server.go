// Package api serves snapshots over HTTP: JSON, Server-Sent Events and logs.
package api

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/kutluhangil/pulse/agent/internal/agent"
	"github.com/kutluhangil/pulse/agent/internal/docker"
)

const (
	maxStreams     = 16
	heartbeatEvery = 15 * time.Second
)

type Server struct {
	Agent   *agent.Agent
	Token   string // empty disables auth (loopback development only)
	Log     *slog.Logger
	streams atomic.Int32
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		fmt.Fprint(w, "ok")
	})
	mux.Handle("GET /v1/snapshot", s.auth(http.HandlerFunc(s.snapshot)))
	mux.Handle("GET /v1/stream", s.auth(http.HandlerFunc(s.stream)))
	mux.Handle("GET /v1/history", s.auth(http.HandlerFunc(s.history)))
	mux.Handle("GET /v1/containers/{id}/logs", s.auth(http.HandlerFunc(s.logs)))
	return headers(mux)
}

func headers(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Cache-Control", "no-store")
		h.Set("Referrer-Policy", "no-referrer")
		next.ServeHTTP(w, r)
	})
}

func (s *Server) auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.Token != "" {
			got, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
			if !ok || subtle.ConstantTimeCompare([]byte(got), []byte(s.Token)) != 1 {
				w.Header().Set("WWW-Authenticate", `Bearer realm="pulse"`)
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) snapshot(w http.ResponseWriter, _ *http.Request) {
	b := s.Agent.Snapshot()
	if b == nil {
		http.Error(w, "warming up", http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write(b)
}

func (s *Server) stream(w http.ResponseWriter, r *http.Request) {
	if s.streams.Add(1) > maxStreams {
		s.streams.Add(-1)
		http.Error(w, "too many streams", http.StatusTooManyRequests)
		return
	}
	defer s.streams.Add(-1)

	rc := http.NewResponseController(w)
	_ = rc.SetWriteDeadline(time.Time{}) // long-lived response
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")

	ch, unsubscribe := s.Agent.Subscribe()
	defer unsubscribe()

	send := func(b []byte) error {
		if _, err := fmt.Fprintf(w, "event: snapshot\ndata: %s\n\n", b); err != nil {
			return err
		}
		return rc.Flush()
	}
	fmt.Fprint(w, "retry: 2000\n\n")
	if b := s.Agent.Snapshot(); b != nil {
		if send(b) != nil {
			return
		}
	} else if rc.Flush() != nil {
		return
	}

	hb := time.NewTicker(heartbeatEvery)
	defer hb.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case b := <-ch:
			if send(b) != nil {
				return
			}
		case <-hb.C:
			if _, err := fmt.Fprint(w, ": ping\n\n"); err != nil || rc.Flush() != nil {
				return
			}
		}
	}
}

func (s *Server) history(w http.ResponseWriter, r *http.Request) {
	rng := r.URL.Query().Get("range")
	if rng != "24h" {
		rng = "10m"
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(s.Agent.History.Get(rng))
}

func (s *Server) logs(w http.ResponseWriter, r *http.Request) {
	dc := s.Agent.Docker()
	if dc == nil {
		http.Error(w, "docker monitoring disabled", http.StatusNotFound)
		return
	}
	id := r.PathValue("id")
	known := false
	for _, c := range s.Agent.Containers() {
		if c.ID == id || (len(id) >= 12 && strings.HasPrefix(c.ID, id)) {
			id, known = c.ID, true
			break
		}
	}
	if !known {
		http.Error(w, "unknown container", http.StatusNotFound)
		return
	}
	tail, _ := strconv.Atoi(r.URL.Query().Get("tail"))
	out, err := dc.Logs(r.Context(), id, tail)
	if err != nil {
		status := http.StatusBadGateway
		if errors.Is(err, docker.ErrBadID) {
			status = http.StatusBadRequest
		}
		s.Log.Warn("container logs", "err", err)
		http.Error(w, "logs unavailable", status)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	fmt.Fprint(w, out)
}

// NewHTTPServer wraps the handler with conservative timeouts.
func NewHTTPServer(addr string, h http.Handler) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           h,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}
}
