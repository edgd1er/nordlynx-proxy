.PHONY: help lint build

# Use bash for inline if-statements in arch_patch target
SHELL:=bash
NEWVERSION := $(shell grep -oE 'changelog.: .+' README.md | cut -f2 -d' ')

# Enable BuildKit for Docker build
export DOCKER_BUILDKIT:=1
export COMPOSE_DOCKER_CLI_BUILD:=1
export NORDVPN_PACKAGE:=https://repo.nordvpn.com/deb/nordvpn/debian/dists/stable/main/binary-amd64/Packages

# https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help: ## generate help list
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

lint: ## stop all containers
	@echo "lint dockerfile ..."
	docker run -i --rm hadolint/hadolint < Dockerfile

build: ## build image
	@echo "build image ..."
	docker compose build

run: ## run container
	@echo "run container"
	docker compose up

check: ##check Version
	@echo "local  version: "$$(grep -oP "(?<=changelog\): )[^ ]+" README.md)
	@echo "remote version: "$$(curl -Ls "${NORDVPN_PACKAGE}" | grep -oP "(?<=Version: )(.*)" | sort -t. -n -k1,1 -k2,2 -k3,3 | tail -1)
	@echo "NEWVERSION: $(NEWVERSION)"
	@sed -i -E "s/VERSION:.+/VERSION: ${NEWVERSION}/" docker-compose.yml
	@sed -i -E "s/VERSION=.+/VERSION=${NEWVERSION}/" Dockerfile
	@grep -E 'VERSION[:=].+' Dockerfile docker-compose.yml

actcheck: ## GHA check nordvpn app version
	@act -r -j check_version -P ubuntu-latest=nektos/act-environments-ubuntu:20.04