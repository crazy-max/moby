package image

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"testing"

	"github.com/moby/moby/client/pkg/versions"
	"github.com/moby/moby/v2/internal/testutil/request"
	"gotest.tools/v3/assert"
	"gotest.tools/v3/skip"
)

func TestImageListIdentity(t *testing.T) {
	skip.If(t, versions.LessThan(testEnv.DaemonAPIVersion(), "1.54"), "requires API version 1.54 or newer")

	ctx := setupTest(t)

	withoutIdentity := imageListRaw(t, ctx, "/v1.54/images/json")
	for _, img := range withoutIdentity {
		_, has := img["Identity"]
		assert.Check(t, !has, "Identity should not be present unless identity=1 is requested")
	}

	withIdentity := imageListRaw(t, ctx, "/v1.54/images/json?identity=1")
	foundIdentity := false
	for _, img := range withIdentity {
		_, hasTopLevel := img["Identity"]
		assert.Check(t, !hasTopLevel, "Identity should be present on manifests, not at the image summary level")

		manifests, hasManifests := img["Manifests"]
		if !hasManifests || manifests == nil {
			continue
		}
		mfstList, isArray := manifests.([]any)
		assert.Check(t, isArray, "Manifests should be a JSON array when present")
		if !isArray {
			continue
		}
		for _, m := range mfstList {
			mfst, ok := m.(map[string]any)
			if !ok {
				continue
			}
			identity, has := mfst["Identity"]
			if !has || identity == nil {
				continue
			}
			foundIdentity = true
			_, isObject := identity.(map[string]any)
			assert.Check(t, isObject, "Manifest Identity should be a JSON object when present")
			break
		}
	}
	if !foundIdentity {
		t.Skip("no manifests with identity metadata were available in this environment")
	}
}

func TestImageInspectIdentity(t *testing.T) {
	skip.If(t, versions.LessThan(testEnv.DaemonAPIVersion(), "1.53"), "requires API version 1.53 or newer")

	ctx := setupTest(t)

	images := imageListRaw(t, ctx, "/v1.53/images/json")
	if len(images) == 0 {
		t.Skip("no images available to validate inspect identity response")
	}

	foundIdentity := false
	for _, img := range images {
		id, _ := img["Id"].(string)
		if id == "" {
			continue
		}

		imagePath := url.PathEscape(id)
		current := imageInspectRaw(t, ctx, fmt.Sprintf("/v1.53/images/%s/json", imagePath))
		identity, hasCurrent := current["Identity"]
		if !hasCurrent {
			continue
		}

		foundIdentity = true
		assert.Check(t, identity != nil)
		_, isObject := identity.(map[string]any)
		assert.Check(t, isObject, "Identity should be a JSON object when present in API 1.53 image inspect response")
		break
	}
	if !foundIdentity {
		t.Skip("no image with identity metadata found to validate inspect response")
	}
}

func TestImageListIdentityAfterInspectWarmup(t *testing.T) {
	skip.If(t, versions.LessThan(testEnv.DaemonAPIVersion(), "1.54"), "requires API version 1.54 or newer")

	ctx := setupTest(t)

	images := imageListRaw(t, ctx, "/v1.54/images/json")
	if len(images) == 0 {
		t.Skip("no images available to validate list identity response")
	}

	imageID := ""
	for _, img := range images {
		id, _ := img["Id"].(string)
		if id == "" {
			continue
		}
		inspect := imageInspectRaw(t, ctx, fmt.Sprintf("/v1.53/images/%s/json", url.PathEscape(id)))
		identity, has := inspect["Identity"]
		if !has || identity == nil {
			continue
		}
		_, isObject := identity.(map[string]any)
		assert.Check(t, isObject, "Identity should be a JSON object when present in API 1.53 image inspect response")
		imageID = id
		break
	}
	if imageID == "" {
		t.Skip("no image with identity metadata found to validate cache warmup and list behavior")
	}

	withIdentity := imageListRaw(t, ctx, "/v1.54/images/json?identity=1")
	foundImage := false
	for _, img := range withIdentity {
		id, _ := img["Id"].(string)
		if id != imageID {
			continue
		}
		foundImage = true

		_, hasTopLevel := img["Identity"]
		assert.Check(t, !hasTopLevel, "Identity should be present on manifests, not at the image summary level")

		manifests, hasManifests := img["Manifests"]
		assert.Check(t, hasManifests, "Manifests should be present in API 1.54 image list response when identity=1")
		if !hasManifests || manifests == nil {
			break
		}
		mfstList, isArray := manifests.([]any)
		assert.Check(t, isArray, "Manifests should be a JSON array when present")
		if !isArray {
			break
		}
		foundManifestIdentity := false
		for _, m := range mfstList {
			mfst, ok := m.(map[string]any)
			if !ok {
				continue
			}
			identity, has := mfst["Identity"]
			if !has || identity == nil {
				continue
			}
			_, isObject := identity.(map[string]any)
			assert.Check(t, isObject, "Manifest Identity should be a JSON object when present in API 1.54 image list response")
			foundManifestIdentity = true
			break
		}
		assert.Check(t, foundManifestIdentity, "Expected at least one manifest identity in API 1.54 image list response after inspect warmup")
		break
	}
	assert.Check(t, foundImage, "inspected image should be present in image list response")
}

func imageListRaw(t *testing.T, ctx context.Context, endpoint string) []map[string]any {
	t.Helper()

	resp, body, err := request.Get(ctx, endpoint, request.JSON)
	assert.NilError(t, err)
	assert.Equal(t, resp.StatusCode, http.StatusOK)

	buf, err := request.ReadBody(body)
	assert.NilError(t, err)

	var images []map[string]any
	assert.NilError(t, json.Unmarshal(buf, &images), string(buf))
	return images
}

func imageInspectRaw(t *testing.T, ctx context.Context, endpoint string) map[string]any {
	t.Helper()

	resp, body, err := request.Get(ctx, endpoint, request.JSON)
	assert.NilError(t, err)
	assert.Equal(t, resp.StatusCode, http.StatusOK)

	buf, err := request.ReadBody(body)
	assert.NilError(t, err)

	var image map[string]any
	assert.NilError(t, json.Unmarshal(buf, &image), string(buf))
	return image
}
