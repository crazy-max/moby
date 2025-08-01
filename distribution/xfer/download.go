package xfer

import (
	"context"
	"errors"
	"fmt"
	"io"
	"time"

	"github.com/containerd/log"
	"github.com/docker/distribution"
	"github.com/docker/docker/image"
	"github.com/docker/docker/layer"
	"github.com/docker/docker/pkg/ioutils"
	"github.com/docker/docker/pkg/progress"
	"github.com/moby/go-archive/compression"
)

const maxDownloadAttempts = 5

// LayerDownloadManager figures out which layers need to be downloaded, then
// registers and downloads those, taking into account dependencies between
// layers.
type LayerDownloadManager struct {
	layerStore          layer.Store
	tm                  *transferManager
	waitDuration        time.Duration
	maxDownloadAttempts int
}

// SetConcurrency sets the max concurrent downloads for each pull
func (ldm *LayerDownloadManager) SetConcurrency(concurrency int) {
	ldm.tm.setConcurrency(concurrency)
}

// NewLayerDownloadManager returns a new LayerDownloadManager.
func NewLayerDownloadManager(layerStore layer.Store, concurrencyLimit int, options ...DownloadOption) *LayerDownloadManager {
	manager := LayerDownloadManager{
		layerStore:          layerStore,
		tm:                  newTransferManager(concurrencyLimit),
		waitDuration:        time.Second,
		maxDownloadAttempts: maxDownloadAttempts,
	}
	for _, option := range options {
		option(&manager)
	}
	return &manager
}

// DownloadOption set options for the LayerDownloadManager.
type DownloadOption func(*LayerDownloadManager)

// WithMaxDownloadAttempts configures the maximum number of download
// attempts for a download manager.
func WithMaxDownloadAttempts(maxDownloadAttempts int) DownloadOption {
	return func(dlm *LayerDownloadManager) {
		dlm.maxDownloadAttempts = maxDownloadAttempts
	}
}

type downloadTransfer struct {
	transfer

	layerStore layer.Store
	layer      layer.Layer
	err        error
}

// result returns the layer resulting from the download, if the download
// and registration were successful.
func (d *downloadTransfer) result() (layer.Layer, error) {
	return d.layer, d.err
}

// A DownloadDescriptor references a layer that may need to be downloaded.
type DownloadDescriptor interface {
	// Key returns the key used to deduplicate downloads.
	Key() string
	// ID returns the ID for display purposes.
	ID() string
	// DiffID should return the DiffID for this layer, or an error
	// if it is unknown (for example, if it has not been downloaded
	// before).
	DiffID() (layer.DiffID, error)
	// Download is called to perform the download.
	Download(ctx context.Context, progressOutput progress.Output) (io.ReadCloser, int64, error)
	// Close is called when the download manager is finished with this
	// descriptor and will not call Download again or read from the reader
	// that Download returned.
	Close()
}

// DigestRegisterer can be implemented by a DownloadDescriptor, and provides a
// Registered method which gets called after a downloaded layer is registered.
// This allows the user of the download manager to know the DiffID of each
// registered layer. This method is called if a cast to DigestRegisterer is
// successful.
type DigestRegisterer interface {
	// TODO existing implementations in distribution and builder-next swallow errors
	// when registering the diffID. Consider changing the Registered signature
	// to return the error.

	Registered(diffID layer.DiffID)
}

// Download is a blocking function which ensures the requested layers are
// present in the layer store. It uses the string returned by the Key method to
// deduplicate downloads. If a given layer is not already known to present in
// the layer store, and the key is not used by an in-progress download, the
// Download method is called to get the layer tar data. Layers are then
// registered in the appropriate order.  The caller must call the returned
// release function once it is done with the returned RootFS object.
func (ldm *LayerDownloadManager) Download(ctx context.Context, layers []DownloadDescriptor, progressOutput progress.Output) (image.RootFS, func(), error) {
	var (
		topLayer       layer.Layer
		topDownload    *downloadTransfer
		xferWatcher    *watcher
		missingLayer   bool
		transferKey    = ""
		downloadsByKey = make(map[string]*downloadTransfer)
	)

	rootFS := image.RootFS{Type: image.TypeLayers}
	for _, descriptor := range layers {
		key := descriptor.Key()
		transferKey += key

		if !missingLayer {
			missingLayer = true
			diffID, err := descriptor.DiffID()
			if err == nil {
				getRootFS := rootFS
				getRootFS.Append(diffID)
				l, err := ldm.layerStore.Get(getRootFS.ChainID())
				if err == nil {
					// Layer already exists.
					log.G(ctx).Debugf("Layer already exists: %s", descriptor.ID())
					progress.Update(progressOutput, descriptor.ID(), "Already exists")
					if topLayer != nil {
						layer.ReleaseAndLog(ldm.layerStore, topLayer)
					}
					topLayer = l
					missingLayer = false
					rootFS.Append(diffID)
					// Register this repository as a source of this layer.
					if withRegistered, ok := descriptor.(DigestRegisterer); ok { // As layerstore may set the driver
						withRegistered.Registered(diffID)
					}
					continue
				}
			}
		}

		// Does this layer have the same data as a previous layer in
		// the stack? If so, avoid downloading it more than once.
		var topDownloadUncasted transfer
		if existingDownload, ok := downloadsByKey[key]; ok {
			xferFunc := ldm.makeDownloadFuncFromDownload(descriptor, existingDownload, topDownload)
			defer topDownload.transfer.release(xferWatcher)
			topDownloadUncasted, xferWatcher = ldm.tm.transfer(transferKey, xferFunc, progressOutput)
			topDownload = topDownloadUncasted.(*downloadTransfer)
			continue
		}

		// Layer is not known to exist - download and register it.
		progress.Update(progressOutput, descriptor.ID(), "Pulling fs layer")

		var xferFunc doFunc
		if topDownload != nil {
			xferFunc = ldm.makeDownloadFunc(descriptor, "", topDownload)
			defer topDownload.transfer.release(xferWatcher)
		} else {
			xferFunc = ldm.makeDownloadFunc(descriptor, rootFS.ChainID(), nil)
		}
		topDownloadUncasted, xferWatcher = ldm.tm.transfer(transferKey, xferFunc, progressOutput)
		topDownload = topDownloadUncasted.(*downloadTransfer)
		downloadsByKey[key] = topDownload
	}

	if topDownload == nil {
		return rootFS, func() {
			if topLayer != nil {
				layer.ReleaseAndLog(ldm.layerStore, topLayer)
			}
		}, nil
	}

	// Won't be using the list built up so far - will generate it
	// from downloaded layers instead.
	rootFS.DiffIDs = []layer.DiffID{}

	defer func() {
		if topLayer != nil {
			layer.ReleaseAndLog(ldm.layerStore, topLayer)
		}
	}()

	select {
	case <-ctx.Done():
		topDownload.transfer.release(xferWatcher)
		return rootFS, func() {}, ctx.Err()
	case <-topDownload.done():
		break
	}

	l, err := topDownload.result()
	if err != nil {
		topDownload.transfer.release(xferWatcher)
		return rootFS, func() {}, err
	}

	// Must do this exactly len(layers) times, so we don't include the
	// base layer on Windows.
	for range layers {
		if l == nil {
			topDownload.transfer.release(xferWatcher)
			return rootFS, func() {}, errors.New("internal error: too few parent layers")
		}
		rootFS.DiffIDs = append([]layer.DiffID{l.DiffID()}, rootFS.DiffIDs...)
		l = l.Parent()
	}
	return rootFS, func() { topDownload.transfer.release(xferWatcher) }, err
}

// makeDownloadFunc returns a function that performs the layer download and
// registration. If parentDownload is non-nil, it waits for that download to
// complete before the registration step, and registers the downloaded data
// on top of parentDownload's resulting layer. Otherwise, it registers the
// layer on top of the ChainID given by parentLayer.
func (ldm *LayerDownloadManager) makeDownloadFunc(descriptor DownloadDescriptor, parentLayer layer.ChainID, parentDownload *downloadTransfer) doFunc {
	return func(progressChan chan<- progress.Progress, start <-chan struct{}, inactive chan<- struct{}) transfer {
		d := &downloadTransfer{
			transfer:   newTransfer(),
			layerStore: ldm.layerStore,
		}

		go func() {
			defer func() {
				close(progressChan)
			}()

			progressOutput := progress.ChanOutput(progressChan)

			select {
			case <-start:
			default:
				progress.Update(progressOutput, descriptor.ID(), "Waiting")
				<-start
			}

			if parentDownload != nil {
				// Did the parent download already fail or get
				// cancelled?
				select {
				case <-parentDownload.done():
					_, err := parentDownload.result()
					if err != nil {
						d.err = err
						return
					}
				default:
				}
			}

			var (
				downloadReader io.ReadCloser
				size           int64
				err            error
				attempt        = 1
			)

			defer descriptor.Close()

			for {
				downloadReader, size, err = descriptor.Download(d.transfer.context(), progressOutput)
				if err == nil {
					break
				}

				// If an error was returned because the context
				// was cancelled, we shouldn't retry.
				select {
				case <-d.transfer.context().Done():
					d.err = err
					return
				default:
				}

				if _, isDNR := err.(DoNotRetry); isDNR || attempt >= ldm.maxDownloadAttempts {
					log.G(context.TODO()).Errorf("Download failed after %d attempts: %v", attempt, err)
					d.err = err
					return
				}

				log.G(context.TODO()).Infof("Download failed, retrying (%d/%d): %v", attempt, ldm.maxDownloadAttempts, err)
				delay := attempt * 5
				ticker := time.NewTicker(ldm.waitDuration)
				attempt++

			selectLoop:
				for {
					progress.Updatef(progressOutput, descriptor.ID(), "Retrying in %d second%s", delay, (map[bool]string{true: "s"})[delay != 1])
					select {
					case <-ticker.C:
						delay--
						if delay == 0 {
							ticker.Stop()
							break selectLoop
						}
					case <-d.transfer.context().Done():
						ticker.Stop()
						d.err = errors.New("download cancelled during retry delay")
						return
					}
				}
			}

			close(inactive)

			if parentDownload != nil {
				select {
				case <-d.transfer.context().Done():
					d.err = errors.New("layer registration cancelled")
					downloadReader.Close()
					return
				case <-parentDownload.done():
				}

				l, err := parentDownload.result()
				if err != nil {
					d.err = err
					downloadReader.Close()
					return
				}
				parentLayer = l.ChainID()
			}

			reader := progress.NewProgressReader(ioutils.NewCancelReadCloser(d.transfer.context(), downloadReader), progressOutput, size, descriptor.ID(), "Extracting")
			defer reader.Close()

			inflatedLayerData, err := compression.DecompressStream(reader)
			if err != nil {
				d.err = fmt.Errorf("could not get decompression stream: %v", err)
				return
			}
			defer inflatedLayerData.Close()

			var src distribution.Descriptor
			if fs, ok := descriptor.(distribution.Describable); ok {
				src = fs.Descriptor()
			}
			if ds, ok := d.layerStore.(layer.DescribableStore); ok {
				d.layer, err = ds.RegisterWithDescriptor(inflatedLayerData, parentLayer, src)
			} else {
				d.layer, err = d.layerStore.Register(inflatedLayerData, parentLayer)
			}
			if err != nil {
				select {
				case <-d.transfer.context().Done():
					d.err = errors.New("layer registration cancelled")
				default:
					d.err = fmt.Errorf("failed to register layer: %v", err)
				}
				return
			}

			progress.Update(progressOutput, descriptor.ID(), "Pull complete")

			if withRegistered, ok := descriptor.(DigestRegisterer); ok {
				withRegistered.Registered(d.layer.DiffID())
			}

			// Doesn't actually need to be its own goroutine, but
			// done like this so we can defer close(c).
			go func() {
				<-d.transfer.released()
				if d.layer != nil {
					layer.ReleaseAndLog(d.layerStore, d.layer)
				}
			}()
		}()

		return d
	}
}

// makeDownloadFuncFromDownload returns a function that performs the layer
// registration when the layer data is coming from an existing download. It
// waits for sourceDownload and parentDownload to complete, and then
// reregisters the data from sourceDownload's top layer on top of
// parentDownload. This function does not log progress output because it would
// interfere with the progress reporting for sourceDownload, which has the same
// Key.
func (ldm *LayerDownloadManager) makeDownloadFuncFromDownload(descriptor DownloadDescriptor, sourceDownload *downloadTransfer, parentDownload *downloadTransfer) doFunc {
	return func(progressChan chan<- progress.Progress, start <-chan struct{}, inactive chan<- struct{}) transfer {
		d := &downloadTransfer{
			transfer:   newTransfer(),
			layerStore: ldm.layerStore,
		}

		go func() {
			defer func() {
				close(progressChan)
			}()

			<-start

			close(inactive)

			select {
			case <-d.transfer.context().Done():
				d.err = errors.New("layer registration cancelled")
				return
			case <-parentDownload.done():
			}

			l, err := parentDownload.result()
			if err != nil {
				d.err = err
				return
			}
			parentLayer := l.ChainID()

			// sourceDownload should have already finished if
			// parentDownload finished, but wait for it explicitly
			// to be sure.
			select {
			case <-d.transfer.context().Done():
				d.err = errors.New("layer registration cancelled")
				return
			case <-sourceDownload.done():
			}

			l, err = sourceDownload.result()
			if err != nil {
				d.err = err
				return
			}

			layerReader, err := l.TarStream()
			if err != nil {
				d.err = err
				return
			}
			defer layerReader.Close()

			var src distribution.Descriptor
			if fs, ok := l.(distribution.Describable); ok {
				src = fs.Descriptor()
			}
			if ds, ok := d.layerStore.(layer.DescribableStore); ok {
				d.layer, err = ds.RegisterWithDescriptor(layerReader, parentLayer, src)
			} else {
				d.layer, err = d.layerStore.Register(layerReader, parentLayer)
			}
			if err != nil {
				d.err = fmt.Errorf("failed to register layer: %v", err)
				return
			}

			if withRegistered, ok := descriptor.(DigestRegisterer); ok {
				withRegistered.Registered(d.layer.DiffID())
			}

			// Doesn't actually need to be its own goroutine, but
			// done like this so we can defer close(c).
			go func() {
				<-d.transfer.released()
				if d.layer != nil {
					layer.ReleaseAndLog(d.layerStore, d.layer)
				}
			}()
		}()

		return d
	}
}
