//go:build linux || windows
// +build linux windows

package service

import (
	"github.com/docker/docker/v24/pkg/idtools"
	"github.com/docker/docker/v24/volume"
	"github.com/docker/docker/v24/volume/drivers"
	"github.com/docker/docker/v24/volume/local"
	"github.com/pkg/errors"
)

func setupDefaultDriver(store *drivers.Store, root string, rootIDs idtools.Identity) error {
	d, err := local.New(root, rootIDs)
	if err != nil {
		return errors.Wrap(err, "error setting up default driver")
	}
	if !store.Register(d, volume.DefaultDriverName) {
		return errors.New("local volume driver could not be registered")
	}
	return nil
}
