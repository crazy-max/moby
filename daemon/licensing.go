package daemon

import (
	"github.com/docker/docker/v24/api/types"
	"github.com/docker/docker/v24/dockerversion"
)

func (daemon *Daemon) fillLicense(v *types.Info) {
	v.ProductLicense = dockerversion.DefaultProductLicense
}
