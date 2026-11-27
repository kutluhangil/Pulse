//go:build linux || darwin

package collect

import "syscall"

type fsStat struct{ total, free, avail uint64 }

func statFS(path string) (fsStat, error) {
	var st syscall.Statfs_t
	if err := syscall.Statfs(path, &st); err != nil {
		return fsStat{}, err
	}
	bs := uint64(st.Bsize) //nolint:unconvert // int64 on linux, uint32 on darwin
	return fsStat{total: st.Blocks * bs, free: st.Bfree * bs, avail: st.Bavail * bs}, nil
}
