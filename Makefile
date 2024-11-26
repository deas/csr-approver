# Makefile for releasing csr-approver
#
# The release version is controlled from pkg/version
.DEFAULT_GOAL := help
TAG?=latest
NAME:=csr-approver
DOCKER_REPOSITORY:=ghcr.io/deas
# DOCKER_REPOSITORY:=deas
DOCKER_IMAGE_NAME:=$(DOCKER_REPOSITORY)/$(NAME)
GIT_COMMIT:=$(shell git describe --dirty --always)
VERSION:=0.0.1 # $(shell grep 'VERSION' pkg/version/version.go | awk '{ print $$4 }' | tr -d '"')
KIND_NAME=kind
EXTRA_RUN_ARGS?=

# Repository root based on Git metadata.
REPOSITORY_ROOT := $(shell git rev-parse --show-toplevel)
BUILD_DIR := $(REPOSITORY_ROOT)/build

# Allows for defining additional Docker buildx arguments,
# e.g. '--push'.
BUILD_ARGS ?=
# Architectures to build images for
BUILD_PLATFORMS ?= linux/amd64 #,linux/arm64,linux/arm/v7

export CGO_ENABLED=1

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
#KUSTOMIZE ?= $(LOCALBIN)/kustomize
#CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
ENVTEST ?= $(LOCALBIN)/setup-envtest
ENVTEST_K8S_VERSION = 1.31.0
# ENVTEST_K8S_VERSION = 1.25.0

## Tool Versions
#KUSTOMIZE_VERSION ?= v3.8.7
#CONTROLLER_TOOLS_VERSION ?= v0.10.0

# Defines whether cosign verification should be skipped.
SKIP_COSIGN_VERIFICATION ?= true

ifeq (,$(shell go env GOBIN))
export GOBIN=$(BUILD_DIR)/gobin
else
export GOBIN=$(shell go env GOBIN)
endif
export PATH:=${GOBIN}:${PATH}

define go-install-tool
@[ -f $(1) ] || { \
set -e ;\
TMP_DIR=$$(mktemp -d) ;\
cd $$TMP_DIR ;\
go mod init tmp ;\
echo "Downloading $(2)" ;\
env -i bash -c "GOBIN=$(GOBIN) PATH=$(PATH) GOPATH=$(shell go env GOPATH) GOCACHE=$(shell go env GOCACHE) go install $(2)" ;\
rm -rf $$TMP_DIR ;\
}
endef

# libgit2: $(LIBGIT2)  ## Detect or download libgit2 library

COSIGN = $(GOBIN)/cosign

#$(LIBGIT2):
#	$(call go-install-tool,$(COSIGN),github.com/sigstore/cosign/cmd/cosign@latest)
##	IMG=$(LIBGIT2_IMG)
#	IMG=$(LIBGIT2_IMG) TAG=$(LIBGIT2_TAG) PATH=$(PATH):$(GOBIN) ./hack/install-libraries.sh

#HC_INSTALL = $(GOBIN)/hc-install
## .PHONY: envtest
#setup-hc-install:
#	$(call go-install-tool,$(HC_INSTALL),github.com/hashicorp/hc-install/cmd/hc-install@latest)


run: ## Run the bot
	go run -ldflags "-s -w" cmd/csr-approver/* --log-level=debug $(EXTRA_RUN_ARGS)
#	 -ldflags "-s -w -X github.com/deas/csr-approver/pkg/version.REVISION=$(GIT_COMMIT)" cmd/csr-approver/* \
#	--level=debug --grpc-port=9999 --backend-url=https://httpbin.org/status/401 --backend-url=https://httpbin.org/status/500 \
#	--ui-logo=https://raw.githubusercontent.com/deas/csr-approver/gh-pages/cuddle_clap.gif $(EXTRA_RUN_ARGS)

run-image: ## Run the bot image
	docker run -v $$PWD/.kube:/home/app/.kube --env-file .env --rm $(DOCKER_IMAGE_NAME):$(VERSION) $(EXTRA_RUN_ARGS)

update-mod: ## Update all modules recursively
	go get -u ./...
	go mod tidy

.PHONY: fmt
fmt: ## Run go fmt against code.
#	gofmt -l -s -w ./
#	goimports -l -w ./
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: envtest
envtest: $(ENVTEST) ## Download envtest-setup locally if necessary.
$(ENVTEST): $(LOCALBIN)
	test -s $(LOCALBIN)/setup-envtest || GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest

.PHONY: test
# test: manifests generate fmt vet envtest ## Run tests.
test: fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" go test ./... -coverprofile cover.out
#	go test ./... -coverprofile cover.out
#	go test ./pkg/git # ./... -coverprofile cover.out

.PHONY: build
build: ## Basic go build 
#	GIT_COMMIT=$$(git rev-list -1 HEAD) &&
	go build  -ldflags "-s -w" -a -o $(BUILD_DIR)/csr-approver ./cmd/csr-approver/*
#	-X github.com/deas/csr-approver/pkg/version.REVISION=$(GIT_COMMIT)

tidy: ## Mod tidy
	rm -f go.sum; go mod tidy -compat=1.18

build-charts: ## Build the charts
	helm lint charts/*
	helm package charts/*

build-image: ## Build the Docker image
	docker buildx build -t $(DOCKER_IMAGE_NAME):$(VERSION) -o type=docker $(BUILD_ARGS) .

.PHONY: kind-load
kind-load: ## Load image into kind
	kind load docker-image $(DOCKER_IMAGE_NAME):$(VERSION) --name $(KIND_NAME) 

#docker-build:  ## Build the Docker image
#	docker buildx build \
#		--build-arg LIBGIT2_IMG=$(LIBGIT2_IMG)
#		--build-arg LIBGIT2_TAG=$(LIBGIT2_TAG) \
#		--platform=$(BUILD_PLATFORMS) \
#		-t $(DOCKER_IMAGE_NAME):$(VERSION) \
#		$(BUILD_ARGS) .

#build-xx:
#	docker buildx build \
#	--platform=linux/amd64 \
#	-t $(DOCKER_IMAGE_NAME):$(VERSION) \
#	--load \
#	-f Dockerfile.xx .

#build-base:
#	docker build -f Dockerfile.base -t $(DOCKER_REPOSITORY)/csr-approver-base:latest .

#push-base: build-base
#	docker push $(DOCKER_REPOSITORY)/csr-approver-base:latest

#test-container:
#	@docker rm -f csr-approver || true
#	@docker run -dp 9898:9898 --name=csr-approver $(DOCKER_IMAGE_NAME):$(VERSION)
#	@docker ps
#	@TOKEN=$$(curl -sd 'test' localhost:9898/token | jq -r .token) && \
#	curl -sH "Authorization: Bearer $${TOKEN}" localhost:9898/token/validate | grep test

#push-container:
#	docker tag $(DOCKER_IMAGE_NAME):$(VERSION) $(DOCKER_IMAGE_NAME):latest
#	docker push $(DOCKER_IMAGE_NAME):$(VERSION)
#	docker push $(DOCKER_IMAGE_NAME):latest
#	docker tag $(DOCKER_IMAGE_NAME):$(VERSION) quay.io/$(DOCKER_IMAGE_NAME):$(VERSION)
#	docker tag $(DOCKER_IMAGE_NAME):$(VERSION) quay.io/$(DOCKER_IMAGE_NAME):latest
#	docker push quay.io/$(DOCKER_IMAGE_NAME):$(VERSION)
#	docker push quay.io/$(DOCKER_IMAGE_NAME):latest

version-set:
	@next="$(TAG)" && \
	current="$(VERSION)" && \
	/usr/bin/sed -i '' "s/$$current/$$next/g" pkg/version/version.go && \
	/usr/bin/sed -i '' "s/tag: $$current/tag: $$next/g" charts/csr-approver/values.yaml && \
	/usr/bin/sed -i '' "s/tag: $$current/tag: $$next/g" charts/csr-approver/values-prod.yaml && \
	/usr/bin/sed -i '' "s/appVersion: $$current/appVersion: $$next/g" charts/csr-approver/Chart.yaml && \
	/usr/bin/sed -i '' "s/version: $$current/version: $$next/g" charts/csr-approver/Chart.yaml && \
	/usr/bin/sed -i '' "s/csr-approver:$$current/csr-approver:$$next/g" kustomize/deployment.yaml && \
	/usr/bin/sed -i '' "s/csr-approver:$$current/csr-approver:$$next/g" deploy/webapp/frontend/deployment.yaml && \
	/usr/bin/sed -i '' "s/csr-approver:$$current/csr-approver:$$next/g" deploy/webapp/backend/deployment.yaml && \
	/usr/bin/sed -i '' "s/csr-approver:$$current/csr-approver:$$next/g" deploy/bases/frontend/deployment.yaml && \
	/usr/bin/sed -i '' "s/csr-approver:$$current/csr-approver:$$next/g" deploy/bases/backend/deployment.yaml && \
	/usr/bin/sed -i '' "s/$$current/$$next/g" cue/main.cue && \
	echo "Version $$next set in code, deployment, chart and kustomize"

release: ## Git release version
	git tag $(VERSION)
	git push origin $(VERSION)

#.PHONY: cue-mod
#cue-mod:#
#	@cd cue && cue get go k8s.io/api/...

#.PHONY: cue-gen
#cue-gen:#
#	@cd cue && cue fmt ./... && cue vet --all-errors --concrete ./...
#	@cd cue && cue gen

#env: $(LIBGIT2)
#	echo 'GO_ENABLED="1"' > $(BUILD_DIR)/.env
#	echo 'PKG_CONFIG_PATH="$(PKG_CONFIG_PATH)"' >> $(BUILD_DIR)/.env
#	echo 'LIBRARY_PATH="$(LIBRARY_PATH)"' >> $(BUILD_DIR)/.env
#	echo 'CGO_CFLAGS="$(CGO_CFLAGS)"' >> $(BUILD_DIR)/.env
#	echo 'CGO_LDFLAGS="$(CGO_LDFLAGS)"' >> $(BUILD_DIR)/.env

.PHONY: decode-csr
decode-csr: ## Decode base64 encoded csr
	@jq '.spec.request | @base64d' -r - | openssl req -text -noout

.PHONY: help
help:  ## Display this help menu
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
