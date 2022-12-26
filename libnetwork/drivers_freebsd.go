package libnetwork

import (
	"github.com/docker/docker/v24/libnetwork/drivers/null"
	"github.com/docker/docker/v24/libnetwork/drivers/remote"
)

func getInitializers() []initializer {
	return []initializer{
		{null.Init, "null"},
		{remote.Init, "remote"},
	}
}
