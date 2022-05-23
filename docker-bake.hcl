variable "APT_MIRROR" {
  default = "deb.debian.org"
}
variable "GO_VERSION" {
  default = "1.18.2"
}
variable "DOCKER_DEBUG" {
  default = ""
}
variable "DOCKER_STRIP" {
  default = ""
}
variable "DOCKER_LINKMODE" {
  default = "static"
}
variable "DOCKER_LDFLAGS" {
  default = ""
}
variable "DOCKER_BUILDMODE" {
  default = ""
}
variable "DOCKER_BUILDTAGS" {
  default = "apparmor seccomp"
}

# Docker version such as 17.04.0-dev. Automatically generated through Git ref.
variable "VERSION" {
  default = ""
}

# The platform name, such as "Docker Engine - Community".
variable "PLATFORM" {
  default = ""
}

# The product name, used to set version.ProductName, which is used to set
# BuildKit's ExportedProduct variable in order to show useful error messages
# to users when a certain version of the product doesn't support a BuildKit feature.
variable "PRODUCT" {
  default = ""
}

# Sets the version.DefaultProductLicense string, such as "Community Engine".
# This field can contain a summary of the product license of the daemon if a
# commercial license has been applied to the daemon.
variable "DEFAULT_PRODUCT_LICENSE" {
  default = ""
}

# The name of the packager (e.g. "Docker, Inc."). This used to set CompanyName
# in the manifest.
variable "PACKAGER_NAME" {
  default = ""
}

target "_common" {
  args = {
    BUILDKIT_CONTEXT_KEEP_GIT_DIR = 1 # https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/syntax.md#built-in-build-args
    APT_MIRROR = APT_MIRROR
    GO_VERSION = GO_VERSION
    DOCKER_DEBUG = DOCKER_DEBUG
    DOCKER_STRIP = DOCKER_STRIP
    DOCKER_LINKMODE = DOCKER_LINKMODE
    DOCKER_LDFLAGS = DOCKER_LDFLAGS
    DOCKER_BUILDMODE = DOCKER_BUILDMODE
    DOCKER_BUILDTAGS = DOCKER_BUILDTAGS
    VERSION = VERSION
    PLATFORM = PLATFORM
    PRODUCT = PRODUCT
    DEFAULT_PRODUCT_LICENSE = DEFAULT_PRODUCT_LICENSE
    PACKAGER_NAME = PACKAGER_NAME
  }
}

target "_platforms" {
  platforms = [
    "linux/amd64",
    "linux/arm/v5",
    "linux/arm/v6",
    "linux/arm/v7",
    "linux/arm64",
    "linux/ppc64le",
    "linux/s390x",
    "windows/amd64",
    "windows/arm64"
  ]
}

group "default" {
  targets = ["binary"]
}

#
# binaries targets build dockerd, docker-proxy and docker-init
#

variable "BINARY_OUTPUT" {
  default = "./bundles/binary"
}

target "binary" {
  inherits = ["_common"]
  target = "binary"
  output = [BINARY_OUTPUT]
}

target "binary-cross" {
  inherits = ["binary", "_platforms"]
}

#
# all targets build binaries and extra tools as well (containerd, runc, ...)
#

variable "ALL_OUTPUT" {
  default = "./bundles/all"
}

target "all" {
  inherits = ["_common"]
  target = "all"
  output = [ALL_OUTPUT]
}

target "all-cross" {
  inherits = ["all", "_platforms"]
}

#
# dev
#

variable "DEV_IMAGE" {
  default = "docker-dev"
}
variable "SYSTEMD" {
  default = "false"
}

target "dev" {
  inherits = ["_common"]
  target = "dev"
  args = {
    SYSTEMD = SYSTEMD
  }
  tags = [DEV_IMAGE]
  output = ["type=docker"]
}
