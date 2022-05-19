# syntax=docker/dockerfile:1

ARG BASE_IMAGE="debian:bullseye"
ARG GO_VERSION=1.18.2
ARG XX_VERSION=1.1.0

ARG DEBIAN_FRONTEND=noninteractive
ARG APT_MIRROR=deb.debian.org
ARG DOCKER_LINKMODE=static
ARG SYSTEMD=false

# build deps
ARG TINI_VERSION=v0.19.0
ARG GOWINRES_VERSION=v0.2.3

# extra tools
ARG CONTAINERD_VERSION=v1.6.4
ARG RUNC_VERSION=v1.1.2
ARG ROOTLESSKIT_VERSION=1920341cd41e047834a21007424162a2dc946315
ARG VPNKIT_VERSION=0.5.0
ARG CONTAINERUTILITY_VERSION=aa1ba87e99b68e0113bd27ec26c60b88f9d4ccd9

# dev deps
ARG GOSWAGGER_VERSION=c56166c036004ba7a3a321e5951ba472b9ae298c
ARG GOTESTSUM_VERSION=v1.7.0
ARG SHFMT_VERSION=v3.0.2
ARG GOLANGCI_LINT_VERSION=v1.44.0
# GOTOML_VERSION specifies the version of the tomll binary. When updating this
# version, consider updating the github.com/pelletier/go-toml dependency in
# vendor.mod accordingly.
ARG GOTOML_VERSION=v1.8.1
# DELVE_VERSION specifies the version of the Delve debugger binary.
ARG DELVE_VERSION=v1.8.1
ARG CRIU_VERSION=v3.16.1
ARG REGISTRY_VERSION=v2.3.0
ARG REGISTRY_VERSION_SCHEMA1=v2.1.0
ARG DOCKERCLI_VERSION=v17.09.1-ce
# DOCKERCLI_MODE indicates which way we want to retrieve the docker cli binary.
# - "build" will build the docker cli from the git ref specified in DOCKERCLI_VERSION
# - "download" will download the docker cli from download.docker.com
ARG DOCKERCLI_MODE=download

# cross compilation helper
FROM --platform=$BUILDPLATFORM tonistiigi/xx:${XX_VERSION} AS xx

# go base image to retrieve /usr/local/go
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION} AS golang

# dummy stage to make sure the image is built for unsupported deps
FROM --platform=$BUILDPLATFORM busybox AS build-dummy
RUN mkdir -p /out
FROM scratch AS binary-dummy
COPY --from=build-dummy / /

FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS base
COPY --from=xx / /
ENV XX_APT_PREFER_CROSS=1
RUN echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
ARG APT_MIRROR
RUN sed -ri "s/(httpredir|deb).debian.org/${APT_MIRROR:-deb.debian.org}/g" /etc/apt/sources.list \
 && sed -ri "s/(security).debian.org/${APT_MIRROR:-security.debian.org}/g" /etc/apt/sources.list
ENV GO111MODULE=off
ARG DEBIAN_FRONTEND
RUN --mount=type=cache,sharing=locked,id=moby-base-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-base-aptcache,target=/var/cache/apt \
    apt-get update && apt-get install --no-install-recommends -y \
      bash \
      ca-certificates \
      cmake \
      file \
      gcc \
      git \
      libc6-dev \
      lld \
      make \
      pkg-config \
      wget
COPY --from=golang /usr/local/go /usr/local/go
ENV GOROOT="/usr/local/go"
ENV GOPATH="/go"
ENV PATH="$GOPATH/bin:/usr/local/go/bin:$PATH"
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

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

FROM containerd-base-${DOCKER_LINKMODE} AS containerd-build
ARG DEBIAN_FRONTEND
ARG TARGETPLATFORM
RUN --mount=type=cache,sharing=locked,id=moby-containerd-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-containerd-aptcache,target=/var/cache/apt \
    xx-apt-get update && xx-apt-get install -y \
      binutils \
      g++ \
      gcc \
      libbtrfs-dev \
      libsecret-1-dev \
      pkg-config \
    && xx-go --wrap
ARG DOCKER_LINKMODE
ARG CONTAINERD_VERSION
RUN --mount=from=containerd-src,src=/usr/src/containerd,rw \
    --mount=type=cache,target=/root/.cache <<EOT
  set -e
  git fetch origin
  git checkout -q "$CONTAINERD_VERSION"
  make bin/containerd
  xx-verify $([ "$DOCKER_LINKMODE" = "static" ] && echo "--static") bin/containerd
  make bin/containerd-shim-runc-v2
  xx-verify $([ "$DOCKER_LINKMODE" = "static" ] && echo "--static") bin/containerd-shim-runc-v2
  make bin/ctr
  # FIXME: ctr not statically linked: https://github.com/containerd/containerd/issues/5824
  xx-verify bin/ctr
  mv bin /out
EOT

FROM binary-dummy AS containerd-darwin
FROM binary-dummy AS containerd-freebsd
FROM containerd-build AS containerd-linux
FROM binary-dummy AS containerd-windows
FROM containerd-${TARGETOS} AS containerd

# runc
FROM base AS runc-src
WORKDIR /usr/src
RUN git clone https://github.com/opencontainers/runc.git runc

FROM base AS runc-build
WORKDIR /go/src/github.com/opencontainers/runc
ARG DEBIAN_FRONTEND
ARG TARGETPLATFORM
RUN --mount=type=cache,sharing=locked,id=moby-runc-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-runc-aptcache,target=/var/cache/apt \
    xx-apt-get update && xx-apt-get install -y \
      binutils \
      g++ \
      gcc \
      dpkg-dev \
      libseccomp-dev \
      pkg-config \
    && xx-go --wrap
ENV CGO_ENABLED=1
ARG DOCKER_LINKMODE
ARG RUNC_VERSION
RUN --mount=from=runc-src,src=/usr/src/runc,rw \
    --mount=type=cache,target=/root/.cache <<EOT
  set -e
  git fetch origin
  git checkout -q "$RUNC_VERSION"
  make BUILDTAGS="seccomp" "$([ "$DOCKER_LINKMODE" = "static" ] && echo "static" || echo "runc")"
  xx-verify $([ "$DOCKER_LINKMODE" = "static" ] && echo "--static") runc
  mkdir /out
  mv runc /out/
EOT

FROM binary-dummy AS runc-darwin
FROM binary-dummy AS runc-freebsd
FROM runc-build AS runc-linux
FROM binary-dummy AS runc-windows
FROM runc-${TARGETOS} AS runc

# tini (docker-init)
FROM base AS tini-src
WORKDIR /usr/src
RUN git clone https://github.com/krallin/tini.git tini

FROM base AS tini-build
WORKDIR /go/src/github.com/krallin/tini
ARG DEBIAN_FRONTEND
ARG TARGETPLATFORM
RUN --mount=type=cache,sharing=locked,id=moby-tini-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-tini-aptcache,target=/var/cache/apt \
    xx-apt-get update && xx-apt-get install -y \
      gcc \
      libc6-dev
ARG DOCKER_LINKMODE
ARG TINI_VERSION
RUN --mount=from=tini-src,src=/usr/src/tini,rw \
    --mount=type=cache,target=/root/.cache <<EOT
  set -e
  export TINI_TARGET=$([ "$DOCKER_LINKMODE" = "static" ] && echo "tini-static" || echo "tini")
  git fetch origin
  git checkout -q "$TINI_VERSION"
  CC=$(xx-info)-gcc cmake .
  make "$TINI_TARGET"
  xx-verify $([ "$DOCKER_LINKMODE" = "static" ] && echo "--static") "$TINI_TARGET"
  mkdir /out
  mv "$TINI_TARGET" /out/docker-init
EOT

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

FROM rootlesskit-base-${DOCKER_LINKMODE} AS rootlesskit-build
ARG DEBIAN_FRONTEND
ARG TARGETPLATFORM
RUN --mount=type=cache,sharing=locked,id=moby-rootlesskit-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-rootlesskit-aptcache,target=/var/cache/apt \
    xx-apt-get update && xx-apt-get install -y \
      gcc \
      libc6-dev \
    && xx-go --wrap
ARG DOCKER_LINKMODE
ARG ROOTLESSKIT_VERSION
ENV GOBIN=/out GO111MODULE=on
COPY ./contrib/dockerd-rootless.sh /out/
COPY ./contrib/dockerd-rootless-setuptool.sh /out/
RUN --mount=from=rootlesskit-src,src=/usr/src/rootlesskit,rw \
    --mount=type=cache,target=/root/.cache <<EOT
  set -e
  git fetch origin
  git checkout -q "$ROOTLESSKIT_VERSION"
  go build -o /out/rootlesskit -ldflags="$ROOTLESSKIT_LDFLAGS" -v ./cmd/rootlesskit
  xx-verify $([ "$DOCKER_LINKMODE" = "static" ] && echo "--static") /out/rootlesskit
  go build -o /out/rootlesskit-docker-proxy -ldflags="$ROOTLESSKIT_LDFLAGS" -v ./cmd/rootlesskit-docker-proxy
  xx-verify $([ "$DOCKER_LINKMODE" = "static" ] && echo "--static") /out/rootlesskit-docker-proxy
EOT

FROM binary-dummy AS rootlesskit-darwin
FROM binary-dummy AS rootlesskit-freebsd
FROM rootlesskit-build AS rootlesskit-linux
FROM binary-dummy AS rootlesskit-windows
FROM rootlesskit-${TARGETOS} AS rootlesskit

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

# containerutility
FROM base AS containerutility-src
WORKDIR /usr/src
RUN git clone https://github.com/docker-archive/windows-container-utility.git containerutility

FROM base AS containerutility-build
WORKDIR /usr/src/containerutility
ARG TARGETPLATFORM
RUN --mount=type=cache,sharing=locked,id=moby-containerutility-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-containerutility-aptcache,target=/var/cache/apt \
    xx-apt-get update && xx-apt-get install -y \
      binutils \
      dpkg-dev \
      g++ \
      gcc \
      pkg-config
ARG CONTAINERUTILITY_VERSION
RUN --mount=from=containerutility-src,src=/usr/src/containerutility,rw \
    --mount=type=cache,target=/root/.cache <<EOT
  set -e
  git fetch origin
  git checkout -q "$CONTAINERUTILITY_VERSION"
  CC="$(xx-info)-gcc" CXX="$(xx-info)-g++" make
  mkdir /out
  mv containerutility.exe /out/
EOT

FROM binary-dummy AS containerutility-darwin
FROM binary-dummy AS containerutility-freebsd
FROM binary-dummy AS containerutility-linux
FROM containerutility-build AS containerutility-windows-amd64
FROM binary-dummy AS containerutility-windows-arm64
FROM containerutility-windows-${TARGETARCH} AS containerutility-windows
FROM containerutility-${TARGETOS} AS containerutility

# go-swagger
FROM base AS swagger-src
WORKDIR /usr/src
# Currently uses a fork from https://github.com/kolyshkin/go-swagger/tree/golang-1.13-fix
# TODO: move to under moby/ or fix upstream go-swagger to work for us.
RUN git clone https://github.com/kolyshkin/go-swagger.git swagger

FROM base AS swagger
ARG GOSWAGGER_VERSION
WORKDIR /go/src/github.com/go-swagger/go-swagger
RUN --mount=from=swagger-src,src=/usr/src/swagger,rw \
    --mount=type=cache,target=/root/.cache <<EOT
  set -e
  git fetch origin
  git checkout -q "$GOSWAGGER_VERSION"
  go build -o /out/swagger ./cmd/swagger
EOT

# tomll builds and installs from https://github.com/pelletier/go-toml. This
# binary is used in CI in the hack/validate/toml script.
FROM base AS tomll
ARG GOTOML_VERSION
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOBIN=/out GO111MODULE=on go install "github.com/pelletier/go-toml/cmd/tomll@${GOTOML_VERSION}" \
    && /out/tomll --help

# delve builds and installs from https://github.com/go-delve/delve. It can be
# used to run Docker with a possibility of attaching debugger to it.
FROM base AS delve
ARG DELVE_VERSION
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOBIN=/out GO111MODULE=on go install "github.com/go-delve/delve/cmd/dlv@${DELVE_VERSION}" \
    && /out/dlv --help

# gotestsum
FROM base AS gotestsum
ARG GOTESTSUM_VERSION
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOBIN=/out GO111MODULE=on go install "gotest.tools/gotestsum@${GOTESTSUM_VERSION}" \
    && /out/gotestsum --version

# shfmt
FROM base AS shfmt
ARG SHFMT_VERSION
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOBIN=/out GO111MODULE=on go install "mvdan.cc/sh/v3/cmd/shfmt@${SHFMT_VERSION}" \
    && /out/shfmt --version

# golangci-lint
FROM base AS golangci-lint
ARG GOLANGCI_LINT_VERSION
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOBIN=/out GO111MODULE=on go install "github.com/golangci/golangci-lint/cmd/golangci-lint@${GOLANGCI_LINT_VERSION}" \
    && /out/golangci-lint --version

# criu
FROM base AS criu-src
WORKDIR /usr/src
RUN git clone https://github.com/checkpoint-restore/criu.git criu

FROM base AS criu
WORKDIR /go/src/github.com/checkpoint-restore/criu
ARG DEBIAN_FRONTEND
RUN --mount=type=cache,sharing=locked,id=moby-criu-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-criu-aptcache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
      clang \
      gcc \
      libc6-dev \
      libcap-dev \
      libnet1-dev \
      libnl-3-dev \
      libprotobuf-dev \
      libprotobuf-c-dev \
      protobuf-c-compiler \
      protobuf-compiler \
      python3-protobuf
ARG CRIU_VERSION
RUN --mount=from=criu-src,src=/usr/src/criu,rw \
    --mount=type=cache,target=/root/.cache <<EOT
  set -e
  git fetch origin
  git checkout -q "$CRIU_VERSION"
  make
  xx-verify ./criu/criu
  mkdir /out
  mv ./criu/criu /out/
EOT

# registry
FROM base AS registry-src
WORKDIR /usr/src
RUN git clone https://github.com/distribution/distribution.git registry

FROM base AS registry
WORKDIR /go/src/github.com/docker/distribution
ENV CGO_ENABLED=0
ARG REGISTRY_VERSION
ARG REGISTRY_VERSION_SCHEMA1
ARG BUILDPLATFORM
RUN --mount=from=registry-src,src=/usr/src/registry,rw \
    --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/go/pkg/mod <<EOT
  set -e
  git fetch origin
  git checkout -q "$REGISTRY_VERSION"
  export GOPATH="/go/src/github.com/docker/distribution/Godeps/_workspace:$GOPATH"
  go build -o /out/registry-v2 -v ./cmd/registry
  xx-verify /out/registry-v2
  case $BUILDPLATFORM in
    linux/amd64|linux/arm/v7|linux/ppc64le|linux/s390x)
      git checkout -q "$REGISTRY_VERSION_SCHEMA1"
      go build -o /out/registry-v2-schema1 -v ./cmd/registry
      xx-verify /out/registry-v2-schema1
      ;;
  esac
EOT

# dockercli
FROM base AS dockercli-src
WORKDIR /usr/src/dockercli
RUN git clone https://github.com/docker/cli.git .
ARG DOCKERCLI_VERSION
RUN git fetch origin && git checkout -q "$DOCKERCLI_VERSION"

FROM base AS dockercli-build
WORKDIR /go/src/github.com/docker/cli
ENV CGO_ENABLED=0
RUN --mount=from=dockercli-src,src=/usr/src/dockercli/components/cli,rw \
    --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/go/pkg/mod <<EOT
  set -e
  go build -o /out/docker -v ./cmd/docker
  xx-verify /out/docker
EOT

FROM base AS dockercli-download
ARG DOCKERCLI_VERSION
ARG TARGETPLATFORM
WORKDIR /out
RUN wget -qO- "https://download.docker.com/linux/static/stable/$(xx-info march)/docker-${DOCKERCLI_VERSION#v}.tgz" | tar xvz --strip 1

FROM dockercli-${DOCKERCLI_MODE} AS dockercli

# frozen-images gets useful and necessary Hub images so we can "docker load"
# locally instead of pulling. See also frozenImages in
# "testutil/environment/protect.go" (which needs to be updated when adding images to this list)
FROM base AS frozen-images
ARG DEBIAN_FRONTEND
RUN --mount=type=cache,sharing=locked,id=moby-frozenimages-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-frozenimages-aptcache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
      skopeo \
    && mkdir /out
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
# OS, ARCH, VARIANT are used by skopeo cli
ENV OS=$TARGETOS
ENV ARCH=$TARGETARCH
ENV VARIANT=$TARGETVARIANT
RUN <<EOT
  set -e
  skopeo copy docker://busybox@sha256:95cf004f559831017cdf4628aaf1bb30133677be8702a8c5f2994629f637a209 --additional-tag busybox:latest docker-archive:///out/busybox-latest.tar
  skopeo copy docker://busybox@sha256:1f81263701cddf6402afe9f33fca0266d9fff379e59b1748f33d3072da71ee85 --additional-tag busybox:glibc docker-archive:///out/busybox-glibc.tar
  skopeo copy docker://debian@sha256:dacf278785a4daa9de07596ec739dbc07131e189942772210709c5c0777e8437 --additional-tag debian:bullseye-slim docker-archive:///out/debian-bullseye-slim.tar
  skopeo copy docker://hello-world@sha256:d58e752213a51785838f9eed2b7a498ffa1cb3aa7f946dda11af39286c3db9a9 --additional-tag hello-world:latest docker-archive:///out/hello-world-latest.tar
  skopeo copy docker://arm32v7/hello-world@sha256:50b8560ad574c779908da71f7ce370c0a2471c098d44d1c8f6b513c5a55eeeb1 --additional-tag arm32v7/hello-world:latest docker-archive:///out/arm32v7-hello-world-latest.tar
EOT

FROM base AS dev-systemd-false
COPY --link --from=frozen-images    /out/ /docker-frozen-images
COPY --link --from=tini             /out/ /usr/local/bin/
COPY --link --from=runc             /out/ /usr/local/bin/
COPY --link --from=containerd       /out/ /usr/local/bin/
COPY --link --from=rootlesskit      /out/ /usr/local/bin/
COPY --link --from=containerutility /out/ /usr/local/bin/
COPY --link --from=vpnkit           /     /usr/local/bin/
COPY --link --from=swagger          /out/ /usr/local/bin/
COPY --link --from=tomll            /out/ /usr/local/bin/
COPY --link --from=delve            /out/ /usr/local/bin/
COPY --link --from=gotestsum        /out/ /usr/local/bin/
COPY --link --from=shfmt            /out/ /usr/local/bin/
COPY --link --from=golangci-lint    /out/ /usr/local/bin/
COPY --link --from=criu             /out/ /usr/local/bin/
COPY --link --from=registry         /out/ /usr/local/bin/
COPY --link --from=dockercli        /out/ /usr/local/cli/
ENV PATH=/usr/local/cli:$PATH
ARG DOCKER_BUILDTAGS
ENV DOCKER_BUILDTAGS="${DOCKER_BUILDTAGS}"
WORKDIR /go/src/github.com/docker/docker
VOLUME /var/lib/docker
VOLUME /home/unprivilegeduser/.local/share/docker
# Wrap all commands in the "docker-in-docker" script to allow nested containers
ENTRYPOINT ["hack/dind"]

FROM dev-systemd-false AS dev-systemd-true
ARG DEBIAN_FRONTEND
RUN --mount=type=cache,sharing=locked,id=moby-systemd-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-systemd-aptcache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
      curl \
      dbus \
      dbus-user-session \
      systemd \
      systemd-sysv
RUN <<EOT
  set -e
  mkdir -p hack
  curl -o hack/dind-systemd https://raw.githubusercontent.com/AkihiroSuda/containerized-systemd/b70bac0daeea120456764248164c21684ade7d0d/docker-entrypoint.sh
  chmod +x hack/dind-systemd
EOT
ENTRYPOINT ["hack/dind-systemd"]

FROM dev-systemd-${SYSTEMD} AS dev-base
ARG DEBIAN_FRONTEND
RUN groupadd -r docker
RUN useradd --create-home --gid docker unprivilegeduser \
 && mkdir -p /home/unprivilegeduser/.local/share/docker \
 && chown -R unprivilegeduser /home/unprivilegeduser
# Let us use a .bashrc file
RUN ln -sfv /go/src/github.com/docker/docker/.bashrc ~/.bashrc
# Activate bash completion and include Docker's completion if mounted with DOCKER_BASH_COMPLETION_PATH
RUN echo "source /usr/share/bash-completion/bash_completion" >> /etc/bash.bashrc
RUN ln -s /usr/local/completion/bash/docker /etc/bash_completion.d/docker
RUN ldconfig
# This should only install packages that are specifically needed for the dev environment and nothing else
# Do you really need to add another package here? Can it be done in a different build stage?
RUN --mount=type=cache,sharing=locked,id=moby-dev-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-dev-aptcache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
      apparmor \
      bash-completion \
      bzip2 \
      inetutils-ping \
      iproute2 \
      iptables \
      jq \
      libcap2-bin \
      libnet1 \
      libnl-3-200 \
      libprotobuf-c1 \
      net-tools \
      patch \
      pigz \
      python3-pip \
      python3-setuptools \
      python3-wheel \
      sudo \
      thin-provisioning-tools \
      uidmap \
      vim \
      vim-common \
      xfsprogs \
      xz-utils \
      zip \
      zstd
# Switch to use iptables instead of nftables (to match the CI hosts)
# TODO use some kind of runtime auto-detection instead if/when nftables is supported (https://github.com/moby/moby/issues/26824)
RUN update-alternatives --set iptables  /usr/sbin/iptables-legacy  || true \
 && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true \
 && update-alternatives --set arptables /usr/sbin/arptables-legacy || true
RUN pip3 install yamllint==1.26.1
# set dev environment as safe git directory
RUN git config --global --add safe.directory $GOPATH/src/github.com/docker/docker
RUN --mount=type=cache,sharing=locked,id=moby-build-aptlib,target=/var/lib/apt \
  --mount=type=cache,sharing=locked,id=moby-build-aptcache,target=/var/cache/apt \
  apt-get update && apt-get install --no-install-recommends -y \
    binutils \
    gcc \
    g++ \
    pkg-config \
    dpkg-dev \
    libapparmor-dev \
    libbtrfs-dev \
    libdevmapper-dev \
    libseccomp-dev \
    libsecret-1-dev \
    libsystemd-dev \
    libudev-dev

FROM base AS build-base
WORKDIR /go/src/github.com/docker/docker
ARG DEBIAN_FRONTEND
ARG TARGETPLATFORM
RUN --mount=type=cache,sharing=locked,id=moby-build-aptlib,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,id=moby-build-aptcache,target=/var/cache/apt \
    xx-apt-get update && xx-apt-get install --no-install-recommends -y \
      binutils \
      dpkg-dev \
      g++ \
      gcc \
      libapparmor-dev \
      libbtrfs-dev \
      libdevmapper-dev \
      libseccomp-dev \
      libsecret-1-dev \
      libsystemd-dev \
      libudev-dev \
      pkg-config \
    && xx-go --wrap

FROM build-base AS build
COPY --from=gowinres /out/ /usr/local/bin
ARG CGO_ENABLED
ARG DOCKER_DEBUG
ARG DOCKER_STRIP
ARG DOCKER_LINKMODE
ARG DOCKER_BUILDTAGS
ARG DOCKER_LDFLAGS
ARG DOCKER_BUILDMODE
ARG DOCKER_BUILDTAGS
ARG VERSION
ARG PLATFORM
ARG PRODUCT
ARG DEFAULT_PRODUCT_LICENSE
ARG PACKAGER_NAME
# PREFIX overrides DEST dir in make.sh script otherwise it fails because of
# read only mount in current work dir
ARG PREFIX=/tmp
# OUTPUT is used in hack/make/.binary to override DEST from make.sh script
ARG OUTPUT=/out
RUN --mount=type=bind,target=. \
    --mount=type=tmpfs,target=cli/winresources/dockerd \
    --mount=type=tmpfs,target=cli/winresources/docker-proxy \
    --mount=type=cache,target=/root/.cache <<EOT
  set -e
  # FIXME: xx doesn't seem to set CC/CXX for windows even if available
  CC=$(xx-info)-gcc CXX=$(xx-info)-g++ ./hack/make.sh binary
  xx-verify $([ "$DOCKER_LINKMODE" = "static" ] && echo "--static") /out/dockerd$([ "$(go env GOOS)" = "windows" ] && echo ".exe")
  xx-verify $([ "$DOCKER_LINKMODE" = "static" ] && echo "--static") /out/docker-proxy$([ "$(go env GOOS)" = "windows" ] && echo ".exe")
EOT

FROM scratch AS releaser-binary
COPY --link --from=tini         /out/ /
COPY --link --from=build        /out  /

FROM scratch AS releaser-all
COPY --link --from=tini             /out/ /
COPY --link --from=runc             /out/ /
COPY --link --from=containerd       /out/ /
COPY --link --from=rootlesskit      /out/ /
COPY --link --from=containerutility /out/ /
COPY --link --from=vpnkit           /     /
COPY --link --from=build            /out  /

FROM base AS release-binary
COPY --from=releaser-binary / /out
RUN find /out/ -type f \( ! -iname "checksums.txt" \) -print0 | sort -z | xargs -r0 shasum -a 256 -b | sed 's# .*/#  #' > /out/checksums.txt

FROM base AS release-all
COPY --from=releaser-all / /out
RUN find /out/ -type f \( ! -iname "checksums.txt" \) -print0 | sort -z | xargs -r0 shasum -a 256 -b | sed 's# .*/#  #' > /out/checksums.txt

# usage:
# > docker buildx bake binary
# > DOCKER_LINKMODE=dynamic docker buildx bake binary
# or
# > make binary
# > make dynbinary
FROM scratch AS binary
COPY --link --from=release-binary /out /

# usage:
# > docker buildx bake all
FROM scratch AS all
COPY --link --from=release-all /out /

# usage:
# > make shell
FROM dev-base AS dev
COPY . .

FROM dev
