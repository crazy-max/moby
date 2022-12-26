package libnetwork

import (
	"github.com/docker/docker/v24/libnetwork/drivers/bridge"
	"github.com/docker/docker/v24/libnetwork/drivers/host"
	"github.com/docker/docker/v24/libnetwork/drivers/ipvlan"
	"github.com/docker/docker/v24/libnetwork/drivers/macvlan"
	"github.com/docker/docker/v24/libnetwork/drivers/null"
	"github.com/docker/docker/v24/libnetwork/drivers/overlay"
	"github.com/docker/docker/v24/libnetwork/drivers/remote"
)

func getInitializers() []initializer {
	in := []initializer{
		{bridge.Init, "bridge"},
		{host.Init, "host"},
		{ipvlan.Init, "ipvlan"},
		{macvlan.Init, "macvlan"},
		{null.Init, "null"},
		{overlay.Init, "overlay"},
		{remote.Init, "remote"},
	}
	return in
}
