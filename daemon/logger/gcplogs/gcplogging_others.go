//go:build !linux
// +build !linux

package gcplogs

func ensureHomeIfIAmStatic() error {
	return nil
}
