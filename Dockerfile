# syntax=docker/dockerfile:1.3

ARG CROSS="false"
ARG SYSTEMD="false"
ARG GO_VERSION=1.18.1
ARG DEBIAN_FRONTEND=noninteractive
ARG VPNKIT_VERSION=0.5.0
ARG DOCKER_BUILDTAGS="apparmor seccomp"

ARG BASE_DEBIAN_DISTRO="bullseye"
ARG GOLANG_IMAGE="golang:${GO_VERSION}-${BASE_DEBIAN_DISTRO}"

FROM ${GOLANG_IMAGE} AS base
RUN echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
ARG APT_MIRROR
RUN sed -ri "s/(httpredir|deb).debian.org/${APT_MIRROR:-deb.debian.org}/g" /etc/apt/sources.list \
 && sed -ri "s/(security).debian.org/${APT_MIRROR:-security.debian.org}/g" /etc/apt/sources.list
ENV GO111MODULE=off

FROM base AS cross-false

FROM --platform=linux/amd64 base AS cross-true
ARG DEBIAN_FRONTEND
RUN dpkg --add-architecture arm64
RUN dpkg --add-architecture armel
RUN dpkg --add-architecture armhf
RUN dpkg --add-architecture ppc64el
RUN dpkg --add-architecture s390x
RUN --mount=type=cache,sharing=locked,id=moby-cross-true-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-cross-true-aptcache,target=/var/cache/apt \
        apt-get update && apt-get install -y --no-install-recommends \
            crossbuild-essential-arm64 \
            crossbuild-essential-armel \
            crossbuild-essential-armhf \
            crossbuild-essential-ppc64el \
            crossbuild-essential-s390x

FROM cross-${CROSS} AS dev-base

FROM dev-base AS runtime-dev-cross-false
ARG DEBIAN_FRONTEND
RUN --mount=type=cache,sharing=locked,id=moby-cross-false-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-cross-false-aptcache,target=/var/cache/apt \
        apt-get update && apt-get install -y --no-install-recommends \
            binutils-mingw-w64 \
            g++-mingw-w64-x86-64 \
            libapparmor-dev \
            libbtrfs-dev \
            libdevmapper-dev \
            libseccomp-dev \
            libsystemd-dev \
            libudev-dev

FROM --platform=linux/amd64 runtime-dev-cross-false AS runtime-dev-cross-true
ARG DEBIAN_FRONTEND
# These crossbuild packages rely on gcc-<arch>, but this doesn't want to install
# on non-amd64 systems, so other architectures cannot crossbuild amd64.
RUN --mount=type=cache,sharing=locked,id=moby-cross-true-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-cross-true-aptcache,target=/var/cache/apt \
        apt-get update && apt-get install -y --no-install-recommends \
            libapparmor-dev:arm64 \
            libapparmor-dev:armel \
            libapparmor-dev:armhf \
            libapparmor-dev:ppc64el \
            libapparmor-dev:s390x \
            libseccomp-dev:arm64 \
            libseccomp-dev:armel \
            libseccomp-dev:armhf \
            libseccomp-dev:ppc64el \
            libseccomp-dev:s390x

FROM runtime-dev-cross-${CROSS} AS runtime-dev

FROM base AS gowinres
# GOWINRES_VERSION defines go-winres tool version
ARG GOWINRES_VERSION=v0.2.3
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
        GOBIN=/build/ GO111MODULE=on go install "github.com/tc-hib/go-winres@${GOWINRES_VERSION}" \
     && /build/go-winres --help

FROM dev-base AS containerd
ARG DEBIAN_FRONTEND
RUN --mount=type=cache,sharing=locked,id=moby-containerd-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-containerd-aptcache,target=/var/cache/apt \
        apt-get update && apt-get install -y --no-install-recommends \
            libbtrfs-dev
ARG CONTAINERD_VERSION
COPY /hack/dockerfile/install/install.sh /hack/dockerfile/install/containerd.installer /
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
        PREFIX=/build /install.sh containerd

FROM runtime-dev AS runc
ARG RUNC_VERSION
ARG RUNC_BUILDTAGS
COPY /hack/dockerfile/install/install.sh /hack/dockerfile/install/runc.installer /
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
        PREFIX=/build /install.sh runc

FROM dev-base AS tini
ARG DEBIAN_FRONTEND
ARG TINI_VERSION
RUN --mount=type=cache,sharing=locked,id=moby-tini-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-tini-aptcache,target=/var/cache/apt \
        apt-get update && apt-get install -y --no-install-recommends \
            cmake \
            vim-common
COPY /hack/dockerfile/install/install.sh /hack/dockerfile/install/tini.installer /
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
        PREFIX=/build /install.sh tini

FROM dev-base AS rootlesskit
ARG ROOTLESSKIT_VERSION
ARG PREFIX=/build
COPY /hack/dockerfile/install/install.sh /hack/dockerfile/install/rootlesskit.installer /
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
        /install.sh rootlesskit \
     && "${PREFIX}"/rootlesskit --version \
     && "${PREFIX}"/rootlesskit-docker-proxy --help
COPY ./contrib/dockerd-rootless.sh /build
COPY ./contrib/dockerd-rootless-setuptool.sh /build

FROM --platform=amd64 djs55/vpnkit:${VPNKIT_VERSION} AS vpnkit-amd64

FROM --platform=arm64 djs55/vpnkit:${VPNKIT_VERSION} AS vpnkit-arm64

FROM scratch AS vpnkit
COPY --from=vpnkit-amd64 /vpnkit /build/vpnkit.x86_64
COPY --from=vpnkit-arm64 /vpnkit /build/vpnkit.aarch64

FROM runtime-dev AS binary-base
ARG DOCKER_GITCOMMIT=HEAD
ENV DOCKER_GITCOMMIT=${DOCKER_GITCOMMIT}
ARG VERSION
ENV VERSION=${VERSION}
ARG PLATFORM
ENV PLATFORM=${PLATFORM}
ARG PRODUCT
ENV PRODUCT=${PRODUCT}
ARG DEFAULT_PRODUCT_LICENSE
ENV DEFAULT_PRODUCT_LICENSE=${DEFAULT_PRODUCT_LICENSE}
ARG PACKAGER_NAME
ENV PACKAGER_NAME=${PACKAGER_NAME}
ARG DOCKER_BUILDTAGS
ENV DOCKER_BUILDTAGS="${DOCKER_BUILDTAGS}"
ENV PREFIX=/build
# TODO: This is here because hack/make.sh binary copies these extras binaries
# from $PATH into the bundles dir.
# It would be nice to handle this in a different way.
COPY --from=tini          /build/ /usr/local/bin/
COPY --from=runc          /build/ /usr/local/bin/
COPY --from=containerd    /build/ /usr/local/bin/
COPY --from=rootlesskit   /build/ /usr/local/bin/
COPY --from=vpnkit        /build/ /usr/local/bin/
COPY --from=gowinres      /build/ /usr/local/bin/
WORKDIR /go/src/github.com/docker/docker

FROM binary-base AS build-binary
RUN --mount=type=cache,target=/root/.cache \
    --mount=type=bind,target=.,ro \
    --mount=type=tmpfs,target=cli/winresources/dockerd \
    --mount=type=tmpfs,target=cli/winresources/docker-proxy \
        hack/make.sh binary

FROM binary-base AS build-dynbinary
RUN --mount=type=cache,target=/root/.cache \
    --mount=type=bind,target=.,ro \
    --mount=type=tmpfs,target=cli/winresources/dockerd \
    --mount=type=tmpfs,target=cli/winresources/docker-proxy \
        hack/make.sh dynbinary

FROM binary-base AS build-cross
ARG DOCKER_CROSSPLATFORMS
RUN --mount=type=cache,target=/root/.cache \
    --mount=type=bind,target=.,ro \
    --mount=type=tmpfs,target=cli/winresources/dockerd \
    --mount=type=tmpfs,target=cli/winresources/docker-proxy \
        hack/make.sh cross

FROM scratch AS binary
COPY --from=build-binary /build/bundles/ /

FROM scratch AS dynbinary
COPY --from=build-dynbinary /build/bundles/ /

FROM scratch AS cross
COPY --from=build-cross /build/bundles/ /
