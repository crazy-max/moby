// Package local provides the default implementation for volumes. It
// is used to mount data volume containers and directories local to
// the host server.
package local

import (
	"os"
	"syscall"
	"time"

	"github.com/docker/docker/v24/errdefs"
	"github.com/pkg/errors"
)

type optsConfig struct{}

func (r *Root) validateOpts(opts map[string]string) error {
	if len(opts) == 0 {
		return nil
	}
	return errdefs.InvalidParameter(errors.New("options are not supported on this platform"))
}

func (v *localVolume) setOpts(opts map[string]string) error {
	// Windows does not support any options currently
	return nil
}

func (v *localVolume) needsMount() bool {
	return false
}

func (v *localVolume) mount() error {
	return nil
}
func (v *localVolume) unmount() error {
	return nil
}

func unmount(_ string) {}

func (v *localVolume) postMount() error {
	return nil
}

func (v *localVolume) CreatedAt() (time.Time, error) {
	fileInfo, err := os.Stat(v.path)
	if err != nil {
		return time.Time{}, err
	}
	ft := fileInfo.Sys().(*syscall.Win32FileAttributeData).CreationTime
	return time.Unix(0, ft.Nanoseconds()), nil
}
