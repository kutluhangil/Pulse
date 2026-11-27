// Package history keeps recent samples in memory so the app can draw charts
// the moment its panel opens. Nothing is written to disk.
package history

import (
	"sync"

	"github.com/kutluhangil/pulse/agent/internal/model"
)

const (
	FineSize   = 600  // 10 minutes at 1 s
	CoarseSize = 1440 // 24 hours at 1 min
	coarseStep = 60
)

type ring struct {
	buf  []model.Point
	next int
	full bool
}

func newRing(n int) *ring { return &ring{buf: make([]model.Point, n)} }

func (r *ring) push(p model.Point) {
	r.buf[r.next] = p
	r.next = (r.next + 1) % len(r.buf)
	if r.next == 0 {
		r.full = true
	}
}

func (r *ring) points() []model.Point {
	if !r.full {
		return append([]model.Point(nil), r.buf[:r.next]...)
	}
	out := make([]model.Point, 0, len(r.buf))
	out = append(out, r.buf[r.next:]...)
	return append(out, r.buf[:r.next]...)
}

// Store holds a 1 s ring and a 1 min ring of averaged points.
type Store struct {
	mu      sync.RWMutex
	fine    *ring
	coarse  *ring
	bucket  []model.Point
	bucketT int64
}

func New() *Store { return &Store{fine: newRing(FineSize), coarse: newRing(CoarseSize)} }

func (s *Store) Add(p model.Point) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.fine.push(p)
	minute := p.T - p.T%coarseStep
	if s.bucketT != 0 && minute != s.bucketT && len(s.bucket) > 0 {
		avg := average(s.bucket)
		avg.T = s.bucketT
		s.coarse.push(avg)
		s.bucket = s.bucket[:0]
	}
	s.bucketT = minute
	s.bucket = append(s.bucket, p)
}

func (s *Store) Get(rangeName string) model.History {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if rangeName == "24h" {
		return model.History{Range: "24h", Step: coarseStep, Points: s.coarse.points()}
	}
	return model.History{Range: "10m", Step: 1, Points: s.fine.points()}
}

func average(ps []model.Point) model.Point {
	var a model.Point
	var rx, tx, dr, dw uint64
	for _, p := range ps {
		a.CPU += p.CPU
		a.Mem += p.Mem
		a.Temp += p.Temp
		rx += p.Rx
		tx += p.Tx
		dr += p.DR
		dw += p.DW
	}
	n := float64(len(ps))
	u := uint64(len(ps))
	a.CPU /= n
	a.Mem /= n
	a.Temp /= n
	a.Rx, a.Tx, a.DR, a.DW = rx/u, tx/u, dr/u, dw/u
	return a
}
