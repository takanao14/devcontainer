DOCKER ?= docker
IMAGE ?= devcontainer-images
TAG ?= ubuntu-26.04
IMAGE_REF ?= $(IMAGE):$(TAG)
PROJECT ?= $(CURDIR)
MOUNTS ?=
NETWORK ?= none
DRY_RUN ?= 0

export DOCKER IMAGE_REF PROJECT MOUNTS NETWORK DRY_RUN
.DEFAULT_GOAL := help
.PHONY: help build rebuild pull run shell codex claude codex-remote codex-remote-start codex-remote-stop codex-remote-pair codex-remote-shell codex-remote-status test verify smoke smoke-daemon smoke-remote

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build a local development image
	$(DOCKER) build -t "$(IMAGE_REF)" .

rebuild: ## Refresh the base and CLIs without build cache
	$(DOCKER) build --pull --no-cache -t "$(IMAGE_REF)" .

pull: ## Fetch the selected published image
	$(DOCKER) pull "$(IMAGE_REF)"

run: shell ## Alias for shell

shell codex claude: ## Start a shell or agent for PROJECT
	@bash scripts/launch.sh $@

codex-remote: codex-remote-start ## Alias for codex-remote-start

codex-remote-start: ## Start the project remote environment without pairing
	@bash scripts/launch.sh $@

codex-remote-stop: ## Stop the remote environment and retain its state volumes
	@bash scripts/launch.sh $@

codex-remote-pair: ## Issue a pairing code for the running remote environment
	@bash scripts/launch.sh $@

codex-remote-shell: ## Open a shell without owning the remote environment lifetime
	@bash scripts/launch.sh $@

codex-remote-status: ## Show the remote container state
	@bash scripts/launch.sh $@

test: ## Test launcher validation
	bash tests/test_launch.sh
	bash tests/test_codex_remote.sh
	bash tests/test_remote_operations.sh


verify: ## Check the image without credentials
	$(DOCKER) run --rm --network none --cap-drop ALL --security-opt no-new-privileges "$(IMAGE_REF)" bash -ec 'test "$$(id -u)" != 0; if sudo -n true 2>/dev/null; then exit 1; fi; codex --version; claude --version; diff /usr/local/share/devcontainer-images/versions.txt <(codex --version; claude --version; node --version)'
	$(DOCKER) run --rm --network none --cap-drop ALL --security-opt no-new-privileges "$(IMAGE_REF)" bash -ec 'yq --version; shellcheck --version; test "$$(printf "value: true\n" | yq -o=json "." | jq -r .value)" = true; printf "#!/bin/sh\nexit 0\n" | shellcheck -s sh -'

smoke: ## Check mounts and state persistence with temporary fixtures
	bash tests/smoke_container.sh

smoke-daemon: ## Check a remote Docker daemon without runner bind mounts
	bash tests/smoke_daemon.sh

smoke-remote: ## Check remote lifecycle in Docker without credentials
	bash tests/smoke_codex_remote.sh
