The `Dockerfile` supports building and cross compiling docker daemon and extra
tools using [Docker Buildx](https://github.com/docker/buildx) and [BuildKit](https://github.com/moby/buildkit).
A [bake definition](https://github.com/docker/buildx/blob/master/docs/reference/buildx_bake.md) named `docker-bake.hcl` is in place to ease the build process:

```shell
# build binaries for the current host platform
# output to ./dist/binary by default
docker buildx bake

# build binaries for the current host platform
# output to ./bin
BINARY_OUTPUT=./bin docker buildx bake

# build dynamically linked binaries
# output to ./dist/dynbinary by default
GO_LINKMODE=dynamic docker buildx bake

# build binaries for all supported platforms
docker buildx bake binary-cross

# build binaries for a specific platform
docker buildx bake --set *.platform=linux/arm64

# build bundle for the current host platform (binaries + containerd, runc, tini, ...)
# output to ./dist/bundle by default
docker buildx bake bundle

# build bundle for the current host platform
# output to ./bin
BUNDLE_OUTPUT=./bin docker buildx bake bundle

# build bundle for all supported platforms
docker buildx bake bundle-cross
```

It's also possible to build directly using the scripts in `hack/make` folder
outside the Dockerfile but this is **not recommended** as you're not sandboxed.
You might also need to install additional dependencies and have a working local dev
environment:

```shell
# build dockerd
./hack/make/binary-daemon

# build docker-proxy
./hack/make/binary-daemon

# build both
./hack/make/binary
```
