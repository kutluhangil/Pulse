package history

import (
	"testing"

	"github.com/kutluhangil/pulse/agent/internal/model"
)

func TestFineRingWrapsInOrder(t *testing.T) {
	s := New()
	for i := range FineSize + 5 {
		s.Add(model.Point{T: int64(1_000_000 + i), CPU: float64(i)})
	}
	h := s.Get("10m")
	if len(h.Points) != FineSize || h.Step != 1 {
		t.Fatalf("len=%d step=%d", len(h.Points), h.Step)
	}
	if h.Points[0].CPU != 5 || h.Points[FineSize-1].CPU != FineSize+4 {
		t.Errorf("order: first=%v last=%v", h.Points[0].CPU, h.Points[FineSize-1].CPU)
	}
}

func TestCoarseAveragesPerMinute(t *testing.T) {
	s := New()
	start := int64(1_000_020) // minute boundary at 1_000_020 - 1_000_020%60 = 1_000_020
	for i := range 130 {
		s.Add(model.Point{T: start + int64(i), CPU: float64(i % 60), Rx: 100})
	}
	h := s.Get("24h")
	if h.Step != 60 || len(h.Points) != 2 {
		t.Fatalf("points=%d", len(h.Points))
	}
	if h.Points[0].Rx != 100 || h.Points[0].T%60 != 0 {
		t.Errorf("point = %+v", h.Points[0])
	}
}
