package libcontainerd

import (
	"context"

	"github.com/containerd/containerd"
	"github.com/docker/docker/v24/libcontainerd/local"
	"github.com/docker/docker/v24/libcontainerd/remote"
	libcontainerdtypes "github.com/docker/docker/v24/libcontainerd/types"
	"github.com/docker/docker/v24/pkg/system"
)

// NewClient creates a new libcontainerd client from a containerd client
func NewClient(ctx context.Context, cli *containerd.Client, stateDir, ns string, b libcontainerdtypes.Backend) (libcontainerdtypes.Client, error) {
	if !system.ContainerdRuntimeSupported() {
		return local.NewClient(ctx, cli, stateDir, ns, b)
	}
	return remote.NewClient(ctx, cli, stateDir, ns, b)
}
