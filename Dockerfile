# syntax=docker/dockerfile:1

ARG BASE_VARIANT=bullseye
ARG GO_VERSION=1.18.1
ARG XX_VERSION=1.1.0

ARG DEBIAN_FRONTEND=noninteractive
ARG APT_MIRROR=deb.debian.org
ARG GO_LINKMODE=static

# tools required for building
ARG TINI_VERSION=v0.19.0
ARG GOWINRES_VERSION=v0.2.3

# extra tools
ARG CONTAINERD_VERSION=v1.6.2
ARG RUNC_VERSION=v1.1.1
ARG VPNKIT_VERSION=0.5.0
ARG ROOTLESSKIT_VERSION=1920341cd41e047834a21007424162a2dc946315
ARG CONTAINERUTILITY_VERSION=aa1ba87e99b68e0113bd27ec26c60b88f9d4ccd9

# cross compilation helper
FROM --platform=$BUILDPLATFORM tonistiigi/xx:${XX_VERSION} AS xx

# dummy stage to make sure the image is built for unsupported deps
FROM --platform=$BUILDPLATFORM busybox AS build-dummy
RUN mkdir -p /out
FROM scratch AS binary-dummy
COPY --from=build-dummy / /

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-${BASE_VARIANT} AS base
COPY --from=xx / /
RUN echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
ARG APT_MIRROR
RUN sed -ri "s/(httpredir|deb).debian.org/${APT_MIRROR:-deb.debian.org}/g" /etc/apt/sources.list \
  && sed -ri "s/(security).debian.org/${APT_MIRROR:-security.debian.org}/g" /etc/apt/sources.list
ENV GO111MODULE=off
ARG DEBIAN_FRONTEND
# bullseye-backports for cmake
RUN echo "deb https://deb.debian.org/debian bullseye-backports main contrib non-free" >> /etc/apt/sources.list
RUN --mount=type=cache,sharing=locked,id=moby-base-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-base-aptcache,target=/var/cache/apt \
  apt-get update && apt-get install --no-install-recommends -y bash file git make lld && \
  apt-get -y -t bullseye-backports install cmake

# go-winres
FROM base AS gowinres
ARG GOWINRES_VERSION
RUN --mount=type=cache,target=/root/.cache/go-build \
  --mount=type=cache,target=/go/pkg/mod \
  GOBIN=/out GO111MODULE=on go install "github.com/tc-hib/go-winres@${GOWINRES_VERSION}" \
  && /out/go-winres --help

# containerd
FROM base AS containerd-src
WORKDIR /usr/src
RUN git clone https://github.com/containerd/containerd.git containerd

FROM base AS containerd-base-static
WORKDIR /go/src/github.com/containerd/containerd
ENV CGO_ENABLED=1
ENV BUILDTAGS="netgo osusergo static_build"
ENV EXTRA_LDFLAGS='-extldflags "-fno-PIC -static"'
ENV GO111MODULE=off

FROM base AS containerd-base-dynamic
WORKDIR /go/src/github.com/containerd/containerd
ENV GO111MODULE=off

FROM containerd-base-${GO_LINKMODE} AS containerd-base
ARG DEBIAN_FRONTEND
ARG TARGETPLATFORM
RUN --mount=type=cache,sharing=locked,id=moby-containerd-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-containerd-aptcache,target=/var/cache/apt \
  xx-apt-get update && xx-apt-get install --no-install-recommends -y binutils gcc g++ pkg-config libbtrfs-dev libsecret-1-dev && \
  xx-go --wrap

FROM containerd-base AS containerd-build
ARG GO_LINKMODE
ARG CONTAINERD_VERSION
RUN --mount=from=containerd-src,src=/usr/src/containerd,rw \
  --mount=type=cache,target=/root/.cache \
  git fetch origin \
  && git checkout -q "$CONTAINERD_VERSION" \
  && make bin/containerd \
  && xx-verify $([ "$GO_LINKMODE" = "static" ] && echo "--static") bin/containerd \
  && make bin/containerd-shim-runc-v2 \
  && xx-verify $([ "$GO_LINKMODE" = "static" ] && echo "--static") bin/containerd-shim-runc-v2 \
  && make bin/ctr \
  # FIXME: ctr not statically linked: https://github.com/containerd/containerd/issues/5824
  && xx-verify bin/ctr \
  && mv bin /out

FROM binary-dummy AS containerd-darwin
FROM binary-dummy AS containerd-freebsd
FROM containerd-build AS containerd-linux
FROM binary-dummy AS containerd-windows
FROM containerd-${TARGETOS} AS containerd

# runc
FROM base AS runc-src
WORKDIR /usr/src
RUN git clone https://github.com/opencontainers/runc.git runc

FROM base AS runc-base
WORKDIR /go/src/github.com/opencontainers/runc
ARG DEBIAN_FRONTEND
ARG TARGETPLATFORM
RUN --mount=type=cache,sharing=locked,id=moby-runc-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-runc-aptcache,target=/var/cache/apt \
  xx-apt-get update && xx-apt-get install -y binutils gcc g++ dpkg-dev pkg-config libseccomp-dev && \
  xx-go --wrap

FROM runc-base AS runc-build
ENV CGO_ENABLED=1
ARG GO_LINKMODE
ARG RUNC_VERSION
RUN --mount=from=runc-src,src=/usr/src/runc,rw \
  --mount=type=cache,target=/root/.cache \
  git fetch origin \
  && git checkout -q "$RUNC_VERSION" \
  && make BUILDTAGS="seccomp" "$([ "$GO_LINKMODE" = "static" ] && echo "static" || echo "runc")" \
  && xx-verify $([ "$GO_LINKMODE" = "static" ] && echo "--static") runc \
  && mkdir /out \
  && mv runc /out/

FROM binary-dummy AS runc-darwin
FROM binary-dummy AS runc-freebsd
FROM runc-build AS runc-linux
FROM binary-dummy AS runc-windows
FROM runc-${TARGETOS} AS runc

# tini (docker-init)
FROM base AS tini-src
WORKDIR /usr/src
RUN git clone https://github.com/krallin/tini.git tini

FROM base AS tini-base
WORKDIR /go/src/github.com/krallin/tini
ARG DEBIAN_FRONTEND
RUN apt-get update && apt-get install -y clang
ENV XX_CC_PREFER_LINKER=ld
ARG TARGETPLATFORM
RUN --mount=type=cache,sharing=locked,id=moby-tini-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-tini-aptcache,target=/var/cache/apt \
  xx-apt-get update && xx-apt-get install -y libc6-dev gcc

FROM tini-base AS tini-build
ARG GO_LINKMODE
ARG TINI_VERSION
RUN --mount=from=tini-src,src=/usr/src/tini,rw \
  --mount=type=cache,target=/root/.cache \
  export TINI_TARGET=$([ "$GO_LINKMODE" = "static" ] && echo "tini-static" || echo "tini") \
  && git fetch origin \
  && git checkout -q "$TINI_VERSION" \
  && cmake $(xx-clang --print-cmake-defines) . \
  && make "$TINI_TARGET" \
  && xx-verify $([ "$GO_LINKMODE" = "static" ] && echo "--static") "$TINI_TARGET" \
  && mkdir /out \
  && mv "$TINI_TARGET" /out/docker-init

FROM binary-dummy AS tini-darwin
FROM binary-dummy AS tini-freebsd
FROM tini-build AS tini-linux
FROM binary-dummy AS tini-windows
FROM tini-${TARGETOS} AS tini

# rootlesskit
FROM base AS rootlesskit-src
WORKDIR /usr/src
RUN git clone https://github.com/rootless-containers/rootlesskit.git rootlesskit

FROM base AS rootlesskit-base-static
ENV CGO_ENABLED=0
WORKDIR /go/src/github.com/rootless-containers/rootlesskit

FROM base AS rootlesskit-base-dynamic
ENV ROOTLESSKIT_LDFLAGS="-linkmode=external"
WORKDIR /go/src/github.com/rootless-containers/rootlesskit

FROM rootlesskit-base-${GO_LINKMODE} AS rootlesskit-base
ARG DEBIAN_FRONTEND
ARG TARGETPLATFORM
RUN --mount=type=cache,sharing=locked,id=moby-rootlesskit-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-rootlesskit-aptcache,target=/var/cache/apt \
  xx-apt-get update && xx-apt-get install -y libc6-dev gcc \
  && xx-go --wrap

FROM rootlesskit-base AS rootlesskit-build
ARG GO_LINKMODE
ARG ROOTLESSKIT_VERSION
ENV GOBIN=/out GO111MODULE=on
COPY ./contrib/dockerd-rootless.sh /out/
COPY ./contrib/dockerd-rootless-setuptool.sh /out/
RUN --mount=from=rootlesskit-src,src=/usr/src/rootlesskit,rw \
  --mount=type=cache,target=/root/.cache \
  git fetch origin \
  && git checkout -q "$ROOTLESSKIT_VERSION" \
  && go build -o /out/rootlesskit -ldflags="$ROOTLESSKIT_LDFLAGS" -v ./cmd/rootlesskit \
  && xx-verify $([ "$GO_LINKMODE" = "static" ] && echo "--static") /out/rootlesskit \
  && go build -o /out/rootlesskit-docker-proxy -ldflags="$ROOTLESSKIT_LDFLAGS" -v ./cmd/rootlesskit-docker-proxy \
  && xx-verify $([ "$GO_LINKMODE" = "static" ] && echo "--static") /out/rootlesskit-docker-proxy

FROM binary-dummy AS rootlesskit-darwin
FROM binary-dummy AS rootlesskit-freebsd
FROM rootlesskit-build AS rootlesskit-linux
FROM binary-dummy AS rootlesskit-windows
FROM rootlesskit-${TARGETOS} AS rootlesskit

# containerutility
FROM base AS containerutility-src
WORKDIR /usr/src
RUN git clone https://github.com/docker-archive/windows-container-utility.git containerutility

FROM base AS containerutility-base
ARG TARGETPLATFORM
RUN --mount=type=cache,sharing=locked,id=moby-containerutility-aptlib,target=/var/lib/apt \
  --mount=type=cache,sharing=locked,id=moby-containerutility-aptcache,target=/var/cache/apt \
  xx-apt-get install -y binutils gcc g++ dpkg-dev pkg-config

FROM containerutility-base AS containerutility-build
ARG CONTAINERUTILITY_VERSION
RUN --mount=from=containerutility-src,src=/usr/src/containerutility,rw \
  --mount=type=cache,target=/root/.cache \
  git fetch origin \
  && git checkout -q "$CONTAINERUTILITY_VERSION" \
  && CC="$(xx-info)-gcc" CXX="$(xx-info)-g++" make \
  && mkdir /out \
  && mv containerutility.exe /out/

FROM binary-dummy AS containerutility-darwin
FROM binary-dummy AS containerutility-freebsd
FROM binary-dummy AS containerutility-linux
FROM containerutility-build AS containerutility-windows-amd64
FROM binary-dummy AS containerutility-windows-arm64
FROM containerutility-windows-${TARGETARCH} AS containerutility-windows
FROM containerutility-${TARGETOS} AS containerutility

# vpnkit
# TODO: build from source instead
FROM scratch AS vpnkit-windows
FROM scratch AS vpnkit-linux-386
FROM djs55/vpnkit:${VPNKIT_VERSION} AS vpnkit-linux-amd64
FROM scratch AS vpnkit-linux-arm
FROM djs55/vpnkit:${VPNKIT_VERSION} AS vpnkit-linux-arm64
FROM scratch AS vpnkit-linux-ppc64le
FROM scratch AS vpnkit-linux-riscv64
FROM scratch AS vpnkit-linux-s390x
FROM vpnkit-linux-${TARGETARCH} AS vpnkit-linux
FROM vpnkit-${TARGETOS} AS vpnkit

FROM base AS build-base
WORKDIR /go/src/github.com/docker/docker
ARG DEBIAN_FRONTEND
ARG TARGETPLATFORM
RUN --mount=type=cache,sharing=locked,id=moby-build-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-build-aptcache,target=/var/cache/apt \
  xx-apt-get update && xx-apt-get install --no-install-recommends -y binutils gcc g++ pkg-config dpkg-dev \
    libapparmor-dev \
    libbtrfs-dev \
    libdevmapper-dev \
    libseccomp-dev \
    libsecret-1-dev \
    libsystemd-dev \
    libudev-dev \
  && xx-go --wrap

FROM build-base AS build
COPY --from=gowinres /out/ /usr/local/bin
ARG CGO_ENABLED
ARG GO_DEBUG
ARG GO_STRIP=1
ARG GO_BUILDTAGS="apparmor seccomp"
ARG GO_LDFLAGS
ARG GO_BUILDMODE
ARG GO_BUILDTAGS
ARG VERSION
ARG PLATFORM
ARG PRODUCT
ARG DEFAULT_PRODUCT_LICENSE
ARG PACKAGER_NAME
RUN --mount=type=bind,target=.,ro \
  --mount=type=tmpfs,target=cli/winresources/dockerd \
  --mount=type=tmpfs,target=cli/winresources/docker-proxy \
  --mount=type=cache,target=/root/.cache \
  # FIXME: xx doesn't seem to set CC/CXX for windows even if available
  CC=$(xx-info)-gcc CXX=$(xx-info)-g++ OUTPUT=/out ./hack/build/release \
  && xx-verify $([ "$GO_LINKMODE" = "static" ] && echo "--static") /out/dockerd$([ "$(go env GOOS)" = "windows" ] && echo ".exe") \
  && xx-verify $([ "$GO_LINKMODE" = "static" ] && echo "--static") /out/docker-proxy$([ "$(go env GOOS)" = "windows" ] && echo ".exe")

# stage used in Dockerfile.dev through linked context with bake
FROM scratch AS devdeps
COPY --from=tini             /out/ /
COPY --from=runc             /out/ /
COPY --from=containerd       /out/ /
COPY --from=rootlesskit      /out/ /
COPY --from=containerutility /out/ /
COPY --from=vpnkit           /     /

FROM scratch AS releaser-binary
COPY --from=tini         /out/ /
COPY --from=build        /out  /

FROM scratch AS releaser-bundle
COPY --from=tini             /out/ /
COPY --from=runc             /out/ /
COPY --from=containerd       /out/ /
COPY --from=rootlesskit      /out/ /
COPY --from=containerutility /out/ /
COPY --from=vpnkit           /     /
COPY --from=build            /out  /

FROM base AS release-binary
COPY --from=releaser-binary / /out
RUN find /out/ -type f \( ! -iname "checksums.txt" \) -print0 | sort -z | xargs -r0 shasum -a 256 -b | sed 's# .*/#  #' > /out/checksums.txt

FROM base AS release-bundle
COPY --from=releaser-bundle / /out
RUN find /out/ -type f \( ! -iname "checksums.txt" \) -print0 | sort -z | xargs -r0 shasum -a 256 -b | sed 's# .*/#  #' > /out/checksums.txt

FROM scratch AS binary
COPY --from=release-binary /out /

FROM scratch AS bundle
COPY --from=release-bundle /out /

FROM binary
