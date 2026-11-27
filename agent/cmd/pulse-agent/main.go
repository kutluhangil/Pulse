// Command pulse-agent publishes live server metrics for the Pulse macOS app.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/kutluhangil/pulse/agent/internal/agent"
	"github.com/kutluhangil/pulse/agent/internal/api"
	"github.com/kutluhangil/pulse/agent/internal/collect"
	"github.com/kutluhangil/pulse/agent/internal/docker"
	"github.com/kutluhangil/pulse/agent/internal/probe"
)

var version = "dev" // set with -ldflags "-X main.version=..."

const minTokenLen = 24

func main() {
	once := flag.Bool("once", false, "collect one snapshot, print it as JSON and exit")
	healthcheck := flag.Bool("healthcheck", false, "probe the running agent's /health and exit 0 or 1")
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()

	listen := envOr("PULSE_LISTEN", "127.0.0.1:9123")
	switch {
	case *showVersion:
		fmt.Println(version)
		return
	case *healthcheck:
		os.Exit(runHealthcheck(listen))
	}

	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))
	cfg, err := buildConfig(log)
	if err != nil {
		log.Error("config", "err", err)
		os.Exit(2)
	}
	a := agent.New(cfg)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if *once {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(a.Once(ctx)); err != nil {
			log.Error("encode", "err", err)
			os.Exit(1)
		}
		return
	}

	token := os.Getenv("PULSE_TOKEN")
	if err := checkAuth(listen, token, os.Getenv("PULSE_NO_AUTH") == "1"); err != nil {
		log.Error("auth", "err", err)
		os.Exit(2)
	}

	go a.Run(ctx)
	srv := api.NewHTTPServer(listen, (&api.Server{Agent: a, Token: token, Log: log}).Handler())
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()
	log.Info("pulse-agent listening", "addr", listen, "version", version, "auth", token != "")
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Error("listen", "err", err)
		os.Exit(1)
	}
}

func buildConfig(log *slog.Logger) (agent.Config, error) {
	cfg := agent.Config{
		Version: version,
		Machine: collect.NewMachine(collect.DefaultHostFS(), os.Getenv("PULSE_NET_IFACE")),
		Log:     log,
	}
	if dh := envOr("DOCKER_HOST", "unix:///var/run/docker.sock"); dh != "off" {
		dc, err := docker.New(dh)
		if err != nil {
			return cfg, err
		}
		cfg.Docker = dc
	}
	targets, err := probe.ParseTargets(os.Getenv("PULSE_PROBES"))
	if err != nil {
		return cfg, err
	}
	if len(targets) > 0 {
		cfg.Probes = probe.NewChecker(targets)
	}
	return cfg, nil
}

// checkAuth refuses to serve without a strong token unless explicitly
// disabled on a loopback-only address.
func checkAuth(listen, token string, noAuth bool) error {
	if noAuth {
		host, _, err := net.SplitHostPort(listen)
		if err != nil {
			return err
		}
		if ip := net.ParseIP(host); host != "localhost" && (ip == nil || !ip.IsLoopback()) {
			return fmt.Errorf("PULSE_NO_AUTH=1 is only allowed on a loopback address, not %q", listen)
		}
		return nil
	}
	if len(strings.TrimSpace(token)) < minTokenLen {
		return fmt.Errorf("PULSE_TOKEN must be at least %d characters (generate one with: openssl rand -hex 32)", minTokenLen)
	}
	return nil
}

func runHealthcheck(listen string) int {
	host, port, err := net.SplitHostPort(listen)
	if err != nil {
		return 1
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = "127.0.0.1"
	}
	c := http.Client{Timeout: 3 * time.Second}
	resp, err := c.Get("http://" + net.JoinHostPort(host, port) + "/health")
	if err != nil {
		return 1
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
