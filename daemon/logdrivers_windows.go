package daemon

import (
	// Importing packages here only to make sure their init gets called and
	// therefore they register themselves to the logdriver factory.
	_ "github.com/docker/docker/v24/daemon/logger/awslogs"
	_ "github.com/docker/docker/v24/daemon/logger/etwlogs"
	_ "github.com/docker/docker/v24/daemon/logger/fluentd"
	_ "github.com/docker/docker/v24/daemon/logger/gcplogs"
	_ "github.com/docker/docker/v24/daemon/logger/gelf"
	_ "github.com/docker/docker/v24/daemon/logger/jsonfilelog"
	_ "github.com/docker/docker/v24/daemon/logger/logentries"
	_ "github.com/docker/docker/v24/daemon/logger/loggerutils/cache"
	_ "github.com/docker/docker/v24/daemon/logger/splunk"
	_ "github.com/docker/docker/v24/daemon/logger/syslog"
)
