IMAGE ?= ccc-freeswitch-docker
TAG ?= dev
PLATFORMS ?= linux/amd64,linux/arm64
FREESWITCH_VERSION ?= v1.11.1

.PHONY: build build-local push run smoke-test shell

build:
	docker buildx build \
	  --platform $(PLATFORMS) \
	  --build-arg FREESWITCH_VERSION=$(FREESWITCH_VERSION) \
	  -t $(IMAGE):$(TAG) \
	  --push \
	  .

build-local:
	docker buildx build \
	  --platform linux/amd64 \
	  --build-arg FREESWITCH_VERSION=$(FREESWITCH_VERSION) \
	  -t $(IMAGE):$(TAG) \
	  --load \
	  .

push: build

run:
	docker compose up -d

smoke-test:
	./scripts/smoke-test.sh $(IMAGE):$(TAG)

shell:
	docker run --rm -it --net=host \
	  -v "$$(pwd)/runtime/config:/etc/freeswitch" \
	  -v "$$(pwd)/runtime/logs:/var/log/freeswitch" \
	  -v "$$(pwd)/runtime/recordings:/var/lib/freeswitch/recordings" \
	  -v "$$(pwd)/runtime/fax:/var/spool/fax" \
	  $(IMAGE):$(TAG) /bin/bash
