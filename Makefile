.PHONY: all binary dynbinary build cross help install manpages run shell test test-docker-py test-integration test-unit validate win buildx

DOCKER ?= docker

BUILDX_VERSION ?= v0.8.2
ifneq (, $(BUILDX_BIN))
	BUILDX := $(BUILDX_BIN)
else ifneq (, $(shell docker buildx version))
	BUILDX := docker buildx
else ifneq (, $(shell which buildx))
	BUILDX := $(which buildx)
endif
BUILDX ?= out/buildx

ifneq (, $(INSTALL_PREFIX))
	INSTALL_PREFIX := /usr/local
endif

ifdef APT_MIRROR
	export APT_MIRROR
endif

ifndef DEV_IMAGE
	DEV_IMAGE := docker-dev
endif
export DEV_IMAGE

ifdef DEV_SYSTEMD
	DEV_SYSTEMD := true
	export DEV_SYSTEMD
endif

# set the graph driver as the current graphdriver if not set
DOCKER_GRAPHDRIVER := $(if $(DOCKER_GRAPHDRIVER),$(DOCKER_GRAPHDRIVER),$(shell docker info 2>&1 | grep "Storage Driver" | sed 's/.*: //'))
export DOCKER_GRAPHDRIVER

# allow overriding the repository and branch that validation scripts are running
# against these are used in hack/validate/.validate to check what changed in the PR.
export VALIDATE_REPO
export VALIDATE_BRANCH
export VALIDATE_ORIGIN_BRANCH

# env vars passed through directly to Docker's build scripts
# to allow things like `make KEEPBUNDLE=1 binary` easily
# `project/PACKAGERS.md` have some limited documentation of some of these
#
# GO_LDFLAGS can be used to pass additional parameters to -ldflags
# option of "go build". For example, a built-in graphdriver priority list
# can be changed during build time like this:
#
# make GO_LDFLAGS="-X github.com/docker/docker/daemon/graphdriver.priority=overlay2,devicemapper" dynbinary
#
DOCKERDEV_ENVS := \
	-e BUILDFLAGS \
	-e KEEPBUNDLE \
	-e GO_DEBUG \
	-e GO_STRIP \
	-e GO_LINKMODE \
	-e GO_LDFLAGS \
	-e GO_BUILDMODE \
	-e GO_BUILDTAGS \
	-e DOCKER_BUILDKIT \
	-e DOCKER_BASH_COMPLETION_PATH \
	-e DOCKER_CLI_PATH \
	-e DOCKER_EXPERIMENTAL \
	-e DOCKER_GRAPHDRIVER \
	-e DOCKER_PORT \
	-e DOCKER_REMAP_ROOT \
	-e DOCKER_ROOTLESS \
	-e DOCKER_STORAGE_OPTS \
	-e DOCKER_TEST_HOST \
	-e DOCKER_USERLANDPROXY \
	-e DOCKERD_ARGS \
	-e TEST_FORCE_VALIDATE \
	-e TEST_INTEGRATION_DIR \
	-e TEST_SKIP_INTEGRATION \
	-e TEST_SKIP_INTEGRATION_CLI \
	-e TESTDEBUG \
	-e TESTDIRS \
	-e TESTFLAGS \
	-e TEST_FILTER \
	-e TIMEOUT \
	-e VALIDATE_REPO \
	-e VALIDATE_BRANCH \
	-e VALIDATE_ORIGIN_BRANCH \
	-e VERSION \
	-e PLATFORM \
	-e DEFAULT_PRODUCT_LICENSE \
	-e PRODUCT \
	-e PACKAGER_NAME
# note: we _cannot_ add "-e GO_BUILDTAGS" here because even if it's unset in the shell, that would shadow the "ENV GO_BUILDTAGS" set in our Dockerfile, which is very important for our official builds

# to allow `make BIND_DIR=. shell` or `make BIND_DIR= test`
# (default to no bind mount if DOCKER_HOST is set)
# note: BINDDIR is supported for backwards-compatibility here
DOCKERDEV_BIND_DIR := $(if $(BINDDIR),$(BINDDIR),$(if $(DOCKER_HOST),,build))

# DOCKERDEV_MOUNT can be overriden, but use at your own risk!
ifndef DOCKERDEV_MOUNT
DOCKERDEV_MOUNT := $(if $(DOCKERDEV_BIND_DIR),-v "$(CURDIR)/$(DOCKERDEV_BIND_DIR):/go/src/github.com/docker/docker/$(DOCKERDEV_BIND_DIR)")
DOCKERDEV_MOUNT := $(if $(DOCKER_BINDDIR_MOUNT_OPTS),$(DOCKERDEV_MOUNT):$(DOCKER_BINDDIR_MOUNT_OPTS),$(DOCKERDEV_MOUNT))

# This allows the test suite to be able to run without worrying about the underlying fs used by the container running the daemon (e.g. aufs-on-aufs), so long as the host running the container is running a supported fs.
# The volume will be cleaned up when the container is removed due to `--rm`.
# Note that `BIND_DIR` will already be set to `build` if `DOCKER_HOST` is not set (see above BIND_DIR line), in such case this will do nothing since `DOCKERDEV_MOUNT` will already be set.
DOCKERDEV_MOUNT := $(if $(DOCKERDEV_MOUNT),$(DOCKERDEV_MOUNT),-v /go/src/github.com/docker/docker/build)

DOCKERDEV_MOUNT_CACHE := -v docker-dev-cache:/root/.cache -v docker-mod-cache:/go/pkg/mod/
DOCKERDEV_MOUNT_CLI := $(if $(DOCKER_CLI_PATH),-v $(shell dirname $(DOCKER_CLI_PATH)):/usr/local/cli,)
DOCKERDEV_MOUNT_BASH_COMPLETION := $(if $(DOCKER_BASH_COMPLETION_PATH),-v $(shell dirname $(DOCKER_BASH_COMPLETION_PATH)):/usr/local/completion/bash,)
DOCKERDEV_MOUNT := $(DOCKERDEV_MOUNT) $(DOCKERDEV_MOUNT_CACHE) $(DOCKERDEV_MOUNT_CLI) $(DOCKERDEV_MOUNT_BASH_COMPLETION)
endif # ifndef DOCKERDEV_MOUNT

# This allows to set the docker-dev container name
DOCKERDEV_CONTAINER_NAME := $(if $(CONTAINER_NAME),--name $(CONTAINER_NAME),)

ifndef DOCKERDEV_RUN_EXTRA_FLAGS
	DOCKERDEV_RUN_EXTRA_FLAGS := -i
endif

DOCKERDEV_PORT_FORWARD := $(if $(DOCKER_PORT),-p "$(DOCKER_PORT)",)
DOCKERDEV_RUN_FLAGS := $(DOCKER) run --rm $(DOCKERDEV_RUN_EXTRA_FLAGS) --privileged $(DOCKERDEV_CONTAINER_NAME) $(DOCKERDEV_ENVS) $(DOCKERDEV_MOUNT) $(DOCKERDEV_PORT_FORWARD)

# if this session isn't interactive, then we don't want to allocate a
# TTY, which would fail, but if it is interactive, we do want to attach
# so that the user can send e.g. ^C through.
ifeq ($(shell [ -t 0 ] && echo 1 || echo 0), 1)
	DOCKERDEV_RUN_FLAGS += -t
endif

DOCKERDEV_RUN := $(DOCKERDEV_RUN_FLAGS) "$(DEV_IMAGE)"

SWAGGER_DOCS_PORT ?= 9000

default: binary

.PHONY: clean
clean: clean-cache clean-bin clean-bundle

.PHONY: clean-%
clean-%:
	@$(RM) -r build/$*

.PHONY: clean-cache
clean-cache: ## remove the docker volumes that are used for caching in the dev-container
	$(DOCKER) volume rm -f docker-dev-cache docker-mod-cache

out:
	mkdir -p build

ifeq ($(BUILDX), out/buildx)
buildx: out/buildx ## download buildx CLI tool
out/buildx: out
	curl -fsSL https://raw.githubusercontent.com/moby/buildkit/70deac12b5857a1aa4da65e90b262368e2f71500/hack/install-buildx | VERSION="$(BUILDX_VERSION)" BINDIR="$(@D)" bash
	$@ version
else
buildx: out
endif

all: dev-image ## validate all checks, build linux binaries, run all tests,\ncross build non-linux binaries, and generate archives
	$(DOCKERDEV_RUN) bash -c 'hack/validate/default && hack/make.sh'

ifeq ($(SKIP_BUILD_DEV_IMAGE), 1)
dev-image:
	# skip building dev image
else
dev-image: buildx ## build dev image
	$(BUILDX) bake $(BAKE_DEV_SET_FLAGS) dev
endif

ifeq ($(SKIP_BUILD_BINARY), 1)
binary:
	# skip building binary
else
binary: buildx ## build statically linked binaries
	$(BUILDX) bake $(BAKE_BINARY_SET_FLAGS) $@
endif

ifeq ($(SKIP_BUILD_DYNBINARY), 1)
dynbinary:
	# skip building dynbinary
else
dynbinary: buildx ## build dynamically linked binaries
	GO_LINKMODE=dynamic $(BUILDX) bake $(BAKE_DYNBINARY_SET_FLAGS) binary
endif

cross binary-cross: buildx ## cross build the binaries
	$(BUILDX) bake $(BAKE_BINARY_CROSS_SET_FLAGS) binary-cross

bundle: buildx ## build statically linked binaries and extra tools (containerd, runc, ...)
	$(BUILDX) bake $(BAKE_BUNDLE_SET_FLAGS) $@

bundle-cross: buildx ## cross build the binaries and extra tools (containerd, runc, ...)
	$(BUILDX) bake $(BAKE_BUNDLE_CROSS_SET_FLAGS) $@

win: buildx ## cross build the binary for windows
	$(BUILDX) bake --set *.platform=windows/amd64 binary

install: buildx ## install the linux binaries
	$(eval $@_TMP_OUT := $(shell mktemp -d -t moby-output.XXXXXXXXXX))
	$(BUILDX) bake --set "*.output=$($@_TMP_OUT)" --set "*.target=releaser-bundle" bundle
	cp "$($@_TMP_OUT)"/* $(INSTALL_PREFIX)/bin/

run: dev-image ## run the docker daemon in the dev container
	$(DOCKERDEV_RUN) sh -c "KEEPBUNDLE=1 hack/make.sh install-binary run"

shell: dev-image  ## start a shell inside the build env
	$(DOCKERDEV_RUN) bash

test: dynbinary dev-image test-unit ## run the unit, integration and docker-py tests
	$(DOCKERDEV_RUN) sh -c "KEEPBUNDLE=1 hack/make.sh test-integration test-docker-py"

test-docker-py: dynbinary dev-image ## run the docker-py tests
	$(DOCKERDEV_RUN) sh -c "KEEPBUNDLE=1 hack/make.sh test-docker-py"

test-integration-cli: test-integration ## (DEPRECATED) use test-integration

ifneq ($(and $(TEST_SKIP_INTEGRATION),$(TEST_SKIP_INTEGRATION_CLI)),)
test-integration:
	@echo Both integrations suites skipped per environment variables
else
test-integration: dynbinary dev-image ## run the integration tests
	$(DOCKERDEV_RUN) sh -c "KEEPBUNDLE=1 hack/make.sh test-integration"
endif

test-integration-flaky: dynbinary dev-image ## run the stress test for all new integration tests
	$(DOCKERDEV_RUN) sh -c "KEEPBUNDLE=1 hack/make.sh test-integration-flaky"

test-unit: dev-image ## run the unit tests
	$(DOCKERDEV_RUN) hack/test/unit

validate: dev-image ## validate DCO, Seccomp profile generation, gofmt,\n./pkg/ isolation, golint, tests, tomls, go vet and vendor
	$(DOCKERDEV_RUN) hack/validate/all

.PHONY: swagger-gen
swagger-gen:
	docker run --rm -v $(PWD):/go/src/github.com/docker/docker \
		-w /go/src/github.com/docker/docker \
		--entrypoint hack/generate-swagger-api.sh \
		-e GOPATH=/go \
		quay.io/goswagger/swagger:0.7.4

.PHONY: swagger-docs
swagger-docs: ## preview the API documentation
	@echo "API docs preview will be running at http://localhost:$(SWAGGER_DOCS_PORT)"
	@docker run --rm -v $(PWD)/api/swagger.yaml:/usr/share/nginx/html/swagger.yaml \
		-e 'REDOC_OPTIONS=hide-hostname="true" lazy-rendering' \
		-p $(SWAGGER_DOCS_PORT):80 \
		bfirsh/redoc:1.14.0

help: ## this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {gsub("\\\\n",sprintf("\n%22c",""), $$2);printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
