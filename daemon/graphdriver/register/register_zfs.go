//go:build (!exclude_graphdriver_zfs && linux) || (!exclude_graphdriver_zfs && freebsd)
// +build !exclude_graphdriver_zfs,linux !exclude_graphdriver_zfs,freebsd

package register

import (
	// register the zfs driver
	_ "github.com/docker/docker/v24/daemon/graphdriver/zfs"
)
