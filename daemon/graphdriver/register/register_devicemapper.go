//go:build !exclude_graphdriver_devicemapper && !static_build && linux
// +build !exclude_graphdriver_devicemapper,!static_build,linux

package register

import (
	// register the devmapper graphdriver
	_ "github.com/docker/docker/v24/daemon/graphdriver/devmapper"
)
