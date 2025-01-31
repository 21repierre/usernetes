# targets prefixed with underscore are not intended be invoked by human

.DEFAULT_GOAL := binaries
IMAGE=ghcr.io/rootless-containers/usernetes

binaries: image _binaries

_binaries:
	rm -rf bin
	$(eval cid := $(shell docker create $(IMAGE)))
	docker cp $(cid):/home/user/usernetes/bin ./bin
	docker rm $(cid)
	curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml --show-error --output manifests/calico/tigera-operator.yaml

image:
ifeq ($(DOCKER_BUILDKIT),1)
	./hack/translate-dockerfile-runopt-directive.sh < Dockerfile | docker build -t $(IMAGE) -f - $(DOCKER_BUILD_FLAGS) .
else
	docker build -t $(IMAGE) $(DOCKER_BUILD_FLAGS) .
endif

test: image _test

_test:
	./hack/smoketest-docker.sh u7s-test-containerd $(IMAGE) --cri=containerd
	./hack/smoketest-docker.sh u7s-test-crio $(IMAGE) --cri=crio

up: image _up

_up:
	docker-compose --project-name=usernetes up -d
	docker run --rm -v usernetes_tls-master:/a busybox timeout 60 sh -c "until test -f /a/done; do sleep 1; echo \"waiting for /a/done\"; done"
	mkdir -p $(HOME)/.config/usernetes
	docker run --rm -v usernetes_tls-master:/a busybox cat /a/admin-localhost.kubeconfig > $(HOME)/.config/usernetes/docker-compose.kubeconfig
	echo "To use kubectl: export KUBECONFIG=$(HOME)/.config/usernetes/docker-compose.kubeconfig"

down:
	docker-compose --project-name=usernetes down -v -t 0
	rm -f $(HOME)/.config/usernetes/docker-compose.kubeconfig

artifact: binaries _artifact

_artifact:
	rm -rf _artifact _SHA256SUMS
	mkdir _artifact
	( cd .. && tar --exclude=usernetes/.git --exclude=usernetes/_artifact -cjvf ./usernetes/_artifact/usernetes-x86_64.tbz usernetes )
	(cd _artifact ; sha256sum * > ../_SHA256SUMS; mv ../_SHA256SUMS ./SHA256SUMS)
	cat _artifact/SHA256SUMS

clean:
	rm -rf _artifact bin

.PHONY: binaries _binaries image test _test up _up down artifact _artifact clean
