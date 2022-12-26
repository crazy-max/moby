package containerd

import (
	"context"
	"errors"

	imagetype "github.com/docker/docker/v24/api/types/image"
	"github.com/docker/docker/v24/errdefs"
	"github.com/docker/docker/v24/image"
)

// GetImage returns an image corresponding to the image referred to by refOrID.
func (i *ImageService) GetImage(ctx context.Context, refOrID string, options imagetype.GetImageOpts) (retImg *image.Image, retErr error) {
	return nil, errdefs.NotImplemented(errors.New("not implemented"))
}
