//go:build !exclude_graphdriver_fuseoverlayfs && linux
// +build !exclude_graphdriver_fuseoverlayfs,linux

package register

import (
	// register the fuse-overlayfs graphdriver
	_ "github.com/docker/docker/v24/daemon/graphdriver/fuse-overlayfs"
)
