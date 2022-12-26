//go:build !exclude_graphdriver_overlay2 && linux
// +build !exclude_graphdriver_overlay2,linux

package register

import (
	// register the overlay2 graphdriver
	_ "github.com/docker/docker/v24/daemon/graphdriver/overlay2"
)
