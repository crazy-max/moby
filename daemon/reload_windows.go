package daemon

import "github.com/docker/docker/v24/daemon/config"

// reloadPlatform updates configuration with platform specific options
// and updates the passed attributes
func (daemon *Daemon) reloadPlatform(config *config.Config, attributes map[string]string) error {
	return nil
}
