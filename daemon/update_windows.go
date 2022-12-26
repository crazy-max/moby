package daemon

import (
	"github.com/docker/docker/v24/api/types/container"
	libcontainerdtypes "github.com/docker/docker/v24/libcontainerd/types"
)

func toContainerdResources(resources container.Resources) *libcontainerdtypes.Resources {
	// We don't support update, so do nothing
	return nil
}
