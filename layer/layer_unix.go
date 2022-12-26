//go:build linux || freebsd || darwin || openbsd
// +build linux freebsd darwin openbsd

package layer

import "github.com/docker/docker/v24/pkg/stringid"

func (ls *layerStore) mountID(name string) string {
	return stringid.GenerateRandomID()
}
