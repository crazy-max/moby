//go:build !linux && !windows
// +build !linux,!windows

package service

import (
	"github.com/docker/docker/v24/pkg/idtools"
	"github.com/docker/docker/v24/volume/drivers"
)

func setupDefaultDriver(_ *drivers.Store, _ string, _ idtools.Identity) error { return nil }
