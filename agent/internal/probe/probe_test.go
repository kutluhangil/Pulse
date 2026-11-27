package probe

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestParseTargets(t *testing.T) {
	got, err := ParseTargets(" perde=https://perde.example.dev , keys=https://keys.example.dev/health,")
	if err != nil || len(got) != 2 || got[1].Name != "keys" || got[1].URL != "https://keys.example.dev/health" {
		t.Fatalf("got %+v %v", got, err)
	}
	for _, bad := range []string{"noequals", "x=ftp://a", "=https://a", "x=https://"} {
		if _, err := ParseTargets(bad); err == nil {
			t.Errorf("%q accepted", bad)
		}
	}
	if got, _ := ParseTargets(""); len(got) != 0 {
		t.Error("empty spec must give no targets")
	}
}

func TestRun(t *testing.T) {
	up := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) }))
	defer up.Close()
	down := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(502) }))
	defer down.Close()

	c := NewChecker([]Target{{"up", up.URL}, {"down", down.URL}, {"dead", "http://127.0.0.1:1"}})
	res := c.Run(context.Background())
	if !res[0].OK || res[0].Status != 200 {
		t.Errorf("up = %+v", res[0])
	}
	if res[1].OK || res[1].Status != 502 {
		t.Errorf("down = %+v", res[1])
	}
	if res[2].OK || res[2].Error == "" {
		t.Errorf("dead = %+v", res[2])
	}
}
