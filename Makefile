.PHONY: all binary dynbinary build cross help install manpages run shell test test-docker-py test-integration test-unit validate win

BUILDX_VERSION ?= v0.8.2
ifneq (, $(BUILDX_BIN))
	BUILDX := $(BUILDX_BIN)
else ifneq (, $(shell docker buildx version))
	BUILDX := docker buildx
else ifneq (, $(shell which buildx))
	BUILDX := $(which buildx)
endif
BUILDX ?= dist/buildx

DOCKER ?= docker

# set the graph driver as the current graphdriver if not set
DOCKER_GRAPHDRIVER := $(if $(DOCKER_GRAPHDRIVER),$(DOCKER_GRAPHDRIVER),$(shell docker info 2>&1 | grep "Storage Driver" | sed 's/.*: //'))
export DOCKER_GRAPHDRIVER

# get OS/Arch of docker engine
DOCKER_OSARCH := $(shell bash -c 'source hack/make/.detect-daemon-osarch && echo $${DOCKER_ENGINE_OSARCH}')
DOCKERFILE := $(shell bash -c 'source hack/make/.detect-daemon-osarch && echo $${DOCKERFILE}')

DOCKER_GITCOMMIT := $(shell git rev-parse --short HEAD || echo unsupported)
export DOCKER_GITCOMMIT

# allow overriding the repository and branch that validation scripts are running
# against these are used in hack/validate/.validate to check what changed in the PR.
export VALIDATE_REPO
export VALIDATE_BRANCH
export VALIDATE_ORIGIN_BRANCH

# env vars passed through directly to Docker's build scripts
# to allow things like `make KEEPBUNDLE=1 binary` easily
# `project/PACKAGERS.md` have some limited documentation of some of these
#
# DOCKER_LDFLAGS can be used to pass additional parameters to -ldflags
# option of "go build". For example, a built-in graphdriver priority list
# can be changed during build time like this:
#
# make DOCKER_LDFLAGS="-X github.com/docker/docker/daemon/graphdriver.priority=overlay2,devicemapper" dynbinary
#
DOCKER_ENVS := \
	-e BUILD_APT_MIRROR \
	-e BUILDFLAGS \
	-e KEEPBUNDLE \
	-e DOCKER_BUILD_ARGS \
	-e DOCKER_BUILD_GOGC \
	-e DOCKER_BUILD_OPTS \
	-e DOCKER_BUILD_PKGS \
	-e DOCKER_BUILDKIT \
	-e DOCKER_BASH_COMPLETION_PATH \
	-e DOCKER_CLI_PATH \
	-e DOCKER_DEBUG \
	-e DOCKER_EXPERIMENTAL \
	-e DOCKER_GITCOMMIT \
	-e DOCKER_GRAPHDRIVER \
	-e DOCKER_LDFLAGS \
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
	-e TESTFLAGS_INTEGRATION \
	-e TESTFLAGS_INTEGRATION_CLI \
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
# note: we _cannot_ add "-e DOCKER_BUILDTAGS" here because even if it's unset in the shell, that would shadow the "ENV DOCKER_BUILDTAGS" set in our Dockerfile, which is very important for our official builds

# to allow `make BIND_DIR=. shell` or `make BIND_DIR= test`
# (default to no bind mount if DOCKER_HOST is set)
# note: BINDDIR is supported for backwards-compatibility here
BIND_DIR := $(if $(BINDDIR),$(BINDDIR),$(if $(DOCKER_HOST),,bundles))

# DOCKER_MOUNT can be overriden, but use at your own risk!
ifndef DOCKER_MOUNT
DOCKER_MOUNT := $(if $(BIND_DIR),-v "$(CURDIR)/$(BIND_DIR):/go/src/github.com/docker/docker/$(BIND_DIR)")
DOCKER_MOUNT := $(if $(DOCKER_BINDDIR_MOUNT_OPTS),$(DOCKER_MOUNT):$(DOCKER_BINDDIR_MOUNT_OPTS),$(DOCKER_MOUNT))

# This allows the test suite to be able to run without worrying about the underlying fs used by the container running the daemon (e.g. aufs-on-aufs), so long as the host running the container is running a supported fs.
# The volume will be cleaned up when the container is removed due to `--rm`.
# Note that `BIND_DIR` will already be set to `bundles` if `DOCKER_HOST` is not set (see above BIND_DIR line), in such case this will do nothing since `DOCKER_MOUNT` will already be set.
DOCKER_MOUNT := $(if $(DOCKER_MOUNT),$(DOCKER_MOUNT),-v /go/src/github.com/docker/docker/bundles) -v "$(CURDIR)/.git:/go/src/github.com/docker/docker/.git"

DOCKER_MOUNT_CACHE := -v docker-dev-cache:/root/.cache -v docker-mod-cache:/go/pkg/mod/
DOCKER_MOUNT_CLI := $(if $(DOCKER_CLI_PATH),-v $(shell dirname $(DOCKER_CLI_PATH)):/usr/local/cli,)
DOCKER_MOUNT_BASH_COMPLETION := $(if $(DOCKER_BASH_COMPLETION_PATH),-v $(shell dirname $(DOCKER_BASH_COMPLETION_PATH)):/usr/local/completion/bash,)
DOCKER_MOUNT := $(DOCKER_MOUNT) $(DOCKER_MOUNT_CACHE) $(DOCKER_MOUNT_CLI) $(DOCKER_MOUNT_BASH_COMPLETION)
endif # ifndef DOCKER_MOUNT

# This allows to set the docker-dev container name
DOCKER_CONTAINER_NAME := $(if $(CONTAINER_NAME),--name $(CONTAINER_NAME),)

DOCKER_IMAGE := docker-dev
DOCKER_PORT_FORWARD := $(if $(DOCKER_PORT),-p "$(DOCKER_PORT)",)

DOCKER_FLAGS := $(DOCKER) run --rm -i --privileged $(DOCKER_CONTAINER_NAME) $(DOCKER_ENVS) $(DOCKER_MOUNT) $(DOCKER_PORT_FORWARD)
BUILD_APT_MIRROR := $(if $(DOCKER_BUILD_APT_MIRROR),--build-arg APT_MIRROR=$(DOCKER_BUILD_APT_MIRROR))
export BUILD_APT_MIRROR

SWAGGER_DOCS_PORT ?= 9000

define \n


endef

# if this session isn't interactive, then we don't want to allocate a
# TTY, which would fail, but if it is interactive, we do want to attach
# so that the user can send e.g. ^C through.
INTERACTIVE := $(shell [ -t 0 ] && echo 1 || echo 0)
ifeq ($(INTERACTIVE), 1)
	DOCKER_FLAGS += -t
endif

DOCKER_RUN_DOCKER := $(DOCKER_FLAGS) "$(DOCKER_IMAGE)"

DOCKER_BUILD_ARGS += --build-arg=GO_VERSION
ifdef DOCKER_SYSTEMD
DOCKER_BUILD_ARGS += --build-arg=SYSTEMD=true
endif

BUILD_OPTS := ${BUILD_APT_MIRROR} ${DOCKER_BUILD_ARGS} ${DOCKER_BUILD_OPTS} -f "$(DOCKERFILE)"
BUILD_CMD := $(BUILDX) build
BAKE_CMD := $(BUILDX) bake

default: binary

dist:
	mkdir -p dist

all: build ## validate all checks, build linux binaries and run all tests
	$(DOCKER_RUN_DOCKER) bash -c 'hack/validate/default && hack/make.sh'

binary: buildx ## build statically linked linux binaries
	$(BAKE_CMD) binary

dynbinary: buildx ## build dynamically linked linux binaries
	GO_LINKMODE=dynamic $(BAKE_CMD) binary

cross: buildx ## cross build the binaries
	$(BAKE_CMD) binary-cross

bundles:
	mkdir bundles

.PHONY: clean
clean: clean-cache

.PHONY: clean-cache
clean-cache: ## remove the docker volumes that are used for caching in the dev-container
	docker volume rm -f docker-dev-cache docker-mod-cache

help: ## this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {gsub("\\\\n",sprintf("\n%22c",""), $$2);printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## install the linux binaries
	KEEPBUNDLE=1 hack/make.sh install-binary

run: build ## run the docker daemon in a container
	$(DOCKER_RUN_DOCKER) sh -c "KEEPBUNDLE=1 hack/make.sh install-binary run"
 
.PHONY: build
ifeq ($(BIND_DIR), .)
build: shell_target := --target=dev-base
else
build: shell_target := --target=dev
endif
build: buildx
	$(BUILD_CMD) $(BUILD_OPTS) $(shell_target) --load -t "$(DOCKER_IMAGE)" .

shell: build  ## start a shell inside the build env
	$(DOCKER_RUN_DOCKER) bash

test: build test-unit ## run the unit, integration and docker-py tests
	$(DOCKER_RUN_DOCKER) hack/make.sh dynbinary test-integration test-docker-py

test-docker-py: build ## run the docker-py tests
	$(DOCKER_RUN_DOCKER) hack/make.sh dynbinary test-docker-py

test-integration-cli: test-integration ## (DEPRECATED) use test-integration

ifneq ($(and $(TEST_SKIP_INTEGRATION),$(TEST_SKIP_INTEGRATION_CLI)),)
test-integration:
	@echo Both integrations suites skipped per environment variables
else
test-integration: build ## run the integration tests
	$(DOCKER_RUN_DOCKER) hack/make.sh dynbinary test-integration
endif

test-integration-flaky: build ## run the stress test for all new integration tests
	$(DOCKER_RUN_DOCKER) hack/make.sh dynbinary test-integration-flaky

test-unit: build ## run the unit tests
	$(DOCKER_RUN_DOCKER) hack/test/unit

validate: build ## validate DCO, Seccomp profile generation, gofmt,\n./pkg/ isolation, golint, tests, tomls, go vet and vendor
	$(DOCKER_RUN_DOCKER) hack/validate/all

win: build ## cross build the binary for windows
	$(BAKE_CMD) bake --set *.platform=windows/amd64 binary

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

.PHONY: buildx
ifeq ($(BUILDX), dist/buildx)
buildx: dist/buildx ## download buildx CLI tool
dist/buildx:
	curl -fsSL https://raw.githubusercontent.com/moby/buildkit/70deac12b5857a1aa4da65e90b262368e2f71500/hack/install-buildx | VERSION="$(BUILDX_VERSION)" BINDIR="$(@D)" bash
	$@ version
else
buildx: dist
endif
