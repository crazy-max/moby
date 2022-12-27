//go:build !linux
// +build !linux

package gcplogs // import "github.com/docker/docker/daemon/logger/gcplogs"

func ensureHomeIfStatic() error {
	return nil
}
