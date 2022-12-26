//go:build !linux
// +build !linux

package vfs

import (
	"github.com/docker/docker/v24/pkg/chrootarchive"
	"github.com/docker/docker/v24/pkg/idtools"
)

func dirCopy(srcDir, dstDir string) error {
	return chrootarchive.NewArchiver(idtools.IdentityMapping{}).CopyWithTar(srcDir, dstDir)
}
