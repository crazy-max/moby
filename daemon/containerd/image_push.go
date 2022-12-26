package containerd

import (
	"context"
	"errors"
	"io"

	"github.com/docker/docker/v24/api/types/registry"
	"github.com/docker/docker/v24/errdefs"
)

// PushImage initiates a push operation on the repository named localName.
func (i *ImageService) PushImage(ctx context.Context, image, tag string, metaHeaders map[string][]string, authConfig *registry.AuthConfig, outStream io.Writer) error {
	return errdefs.NotImplemented(errors.New("not implemented"))
}
