package libnetwork

import (
	windriver "github.com/docker/docker/v24/libnetwork/drivers/windows"
	"github.com/docker/docker/v24/libnetwork/options"
	"github.com/docker/docker/v24/libnetwork/types"
)

const libnGWNetwork = "nat"

func getPlatformOption() EndpointOption {

	epOption := options.Generic{
		windriver.DisableICC: true,
		windriver.DisableDNS: true,
	}
	return EndpointOptionGeneric(epOption)
}

func (c *controller) createGWNetwork() (Network, error) {
	return nil, types.NotImplementedErrorf("default gateway functionality is not implemented in windows")
}
