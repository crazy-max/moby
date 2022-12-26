package daemon

import (
	"github.com/docker/docker/v24/api/types"
	"github.com/docker/docker/v24/container"
)

// Windows network stats are obtained directly through HCS, hence this is a no-op.
func (daemon *Daemon) getNetworkStats(c *container.Container) (map[string]types.NetworkStats, error) {
	return make(map[string]types.NetworkStats), nil
}
