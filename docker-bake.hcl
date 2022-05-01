variable "APT_MIRROR" {
  default = "deb.debian.org"
}
variable "GO_VERSION" {
  default = "1.18.1"
}
variable "GO_DEBUG" {
  default = ""
}
variable "GO_STRIP" {
  default = "1"
}
variable "GO_LINKMODE" {
  default = "static"
}
variable "GO_LDFLAGS" {
  default = ""
}
variable "GO_BUILDMODE" {
  default = ""
}
variable "GO_BUILDTAGS" {
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
    GO_DEBUG = GO_DEBUG
    GO_STRIP = GO_STRIP
    GO_LINKMODE = GO_LINKMODE
    GO_LDFLAGS = GO_LDFLAGS
    GO_BUILDMODE = GO_BUILDMODE
    GO_BUILDTAGS = GO_BUILDTAGS
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
  default = "./build/binary"
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
# bundle targets build binaries and extra tools as well (containerd, runc, ...)
#

variable "BUNDLE_OUTPUT" {
  default = "./build/bundle"
}

target "bundle" {
  inherits = ["_common"]
  target = "bundle"
  output = [BUNDLE_OUTPUT]
}

target "bundle-cross" {
  inherits = ["bundle", "_platforms"]
}
