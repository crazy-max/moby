This directory holds scripts to build using [Docker buildx](https://github.com/docker/buildx)

```shell
# build binaries for the current host platform
# output to ./build/binary by default
docker buildx bake

# build binaries for the current host platform
# output to ./bin
BINARY_OUTPUT=./bin docker buildx bake

# build dynamically linked binaries
GO_LINKMODE=dynamic docker buildx bake

# build binaries for all supported platforms
docker buildx bake binary-cross

# build binaries for a specific platform
docker buildx bake --set *.platform=linux/arm64

# build bundle for the current host platform (binaries + containerd, runc, tini, ...)
# output to ./build/bundle by default
docker buildx bake bundle

# build bundle for the current host platform
# output to ./bin
BUNDLE_OUTPUT=./bin docker buildx bake bundle

# build bundle for all supported platforms
docker buildx bake bundle-cross
```
