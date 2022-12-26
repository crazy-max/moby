//go:build !linux && !windows
// +build !linux,!windows

package daemon

func configsSupported() bool {
	return false
}
