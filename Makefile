#####################################################
# Support multiple build image
#####################################################
GITCOMMIT:=$(shell git describe --dirty --always)
BINARY:=coredns
SYSTEM:=
CHECKS:=check
BUILDOPTS:=-v
# Variables are related to Go build
GO_VERSION                   := 1.18.7
CGO_ENABLED                  := 0
GO111MODULE                  := on


# Variables are related to command buildx
DOCKER_BUILDX_OUTPUT         := type=docker
BUILDER_NAME                 := dev
TARGETS                      := linux/amd64,linux/arm64 #debian darwin


# Variables are related to images
IMAGE_REGISTRY               := my.registry.cn
IMAGE_PROJECT                := cloudv3
TAG                          ?= v0.9.1
DOCKERFILE_AMD64             := Dockerfile.amd64
DOCKERFILE_ARM64             := Dockerfile.arm64


# Variables are related to application
GO_MAIN_FILE_NAME            := ./cmd/adapter/
APPLICATION_NAME             := prometheus-adapter


#####################################################
# Relation to code
#####################################################

GIT_SHA_SHORT                := $$(git rev-parse --short HEAD)
# GIT_TREE_DIFF         := $$(git diff-index --quiet HEAD; echo $$?)
GIT_TREE_STATUS              ?=

ifeq ($(shell git diff-index --quiet HEAD; echo $$?),0)
    GIT_TREE_STATUS          := "clean"
else
	GIT_TREE_STATUS          := "dirty"
endif

.PHONY: check-git-status
check-git-status:
	@echo $(GIT_TREE_STATUS)

.PHONY: check-git-sha
check-git-sha:
	@echo $(GIT_SHA_SHORT)


##########################################################
# Multiple architecture builder creation
##########################################################


.PHONY: multi-driver
multi-driver:
	docker buildx create --name $(BUILDER_NAME) --platform $(TARGETS) --config ./docker-buildx/buildkitd.toml --driver-opt network=host --use --bootstrap


.PHONY: test-multi-driver
test-multi-driver:
	docker buildx ls


##########################################################
# Multiple image local building pipline
##########################################################


.PHONY: build-${APPLICATION_NAME}-amd64
build-${APPLICATION_NAME}-amd64:
	docker buildx build --builder $(BUILDER_NAME) --platform linux/amd64 \
	-o $(DOCKER_BUILDX_OUTPUT) \
	-t $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)-amd64  \
	-f $(DOCKERFILE_AMD64) \
	--build-arg GOARCH=amd64 \
	--build-arg GO_VERSION=$(GO_VERSION) \
	--build-arg CGO_ENABLED=0 \
	--build-arg GO111MODULE=on \
	--build-arg IMAGE_REGISTRY=$(IMAGE_REGISTRY) \
	--build-arg APPLICATION_NAME=$(APPLICATION_NAME) \
	--build-arg FILE_NAME=$(GO_MAIN_FILE_NAME) \
	--build-arg BASE_IMAGE=$(SYSTEM_BASE_IMAGE_NAME) \
	--build-arg COMMIT_ID=$(GIT_SHA_SHORT)+$(GIT_TREE_STATUS) .

.PHONY: build-${APPLICATION_NAME}-arm64
build-${APPLICATION_NAME}-arm64:
	docker buildx build --builder $(BUILDER_NAME) --platform linux/arm64 \
	-o $(DOCKER_BUILDX_OUTPUT) \
	-t $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)-arm64  \
	-f $(DOCKERFILE_ARM64) \
	--build-arg GOARCH=arm64 \
	--build-arg GO_VERSION=$(GO_VERSION) \
	--build-arg CGO_ENABLED=0 \
	--build-arg GO111MODULE=on \
	--build-arg IMAGE_REGISTRY=$(IMAGE_REGISTRY) \
	--build-arg APPLICATION_NAME=$(APPLICATION_NAME) \
	--build-arg FILE_NAME=$(GO_MAIN_FILE_NAME) \
	--build-arg BASE_IMAGE=$(SYSTEM_BASE_IMAGE_NAME) \
	--build-arg COMMIT_ID=$(GIT_SHA_SHORT)+$(GIT_TREE_STATUS) .


.PHONY: build-all-images
build-all-images: build-${APPLICATION_NAME}-amd64
build-all-images: build-${APPLICATION_NAME}-arm64


.PHONY: docker-push
docker-push:
	docker push $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)-arm64
	docker push $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)-amd64


##########################################################
# Manifest
##########################################################

.IGNORE:
	docker manifest rm $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)


.PHONY: docker-manifest-create
docker-manifest-create: .IGNORE manifest-create

manifest-create:
	docker manifest create --amend \
	$(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG) \
	$(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)-arm64 \
	$(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)-amd64


.PHONY: docker-manifest-push
docker-manifest-push:
	docker manifest push $(IMAGE_REGISTRY)/$(IMAGE_PROJECT)/$(APPLICATION_NAME):$(TAG)


.PHONY: manifest-auto
manifest-auto: docker-push
manifest-auto: docker-manifest-create
manifest-auto: docker-manifest-push


##########################################################
# Base images manifest creating
##########################################################

VERSIONS_NEED        := 1.12.17 1.13.15 1.16.15 1.15.15
ORIGINAL_IMAGE_NAME  := golang
IMAGE_NAME           := $(IMAGE_REGISTRY)/library/golang
ARCH                 :=$(shell docker info | grep Architecture | awk '{ print $$NF}')

ifeq ($(ARCH),x86_64)
	ARCH   := amd64
else
	ARCH   := arm64
endif

.PHONY: check_arch
check_arch:
	@echo $(ARCH)


.PHONY: local_pull
local_pull:
	@for i in $(VERSIONS_NEED); do \
		docker pull $(ORIGINAL_IMAGE_NAME):$$i;\
	done

.PHONY: retag
retag:
	@for i in $(VERSIONS_NEED); do \
		docker tag $(ORIGINAL_IMAGE_NAME):$$i $(IMAGE_NAME):$$i-$(ARCH); \
		echo "$(IMAGE_NAME):$$i-$(ARCH)" is done; \
	done

.PHONY: local_push
local_push:
	@for i in $(VERSIONS_NEED); do \
		docker push $(IMAGE_NAME):$$i-$(ARCH); \
		echo "$(IMAGE_NAME):$$i-$(ARCH)" is done; \
	done


.PHONY: local_manifest
local_manifest:
	@for i in $(VERSIONS_NEED); do \
		docker manifest create --amend $(IMAGE_NAME):$$i $(IMAGE_NAME):$$i-amd64 $(IMAGE_NAME):$$i-arm64; \
		docker manifest push $(IMAGE_NAME):$$i; \
	done


.PHONY: local-arm64
local-arm64: local_pull
local-arm64: retag
local-arm64: local_push


.PHONY: local-amd64
local-amd64: local_pull
local-amd64: retag
local-amd64: local_push
local-amd64: local_manifest
