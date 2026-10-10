DOCKER ?= docker
IMAGE ?= devcontainer-images
TAG ?= ubuntu-26.04
IMAGE_REF ?= $(IMAGE):$(TAG)
GO_IMAGE_REF ?= $(IMAGE):go-1.27.1
RUST_IMAGE_REF ?= $(IMAGE):rust-1.99.0
DNS_IMAGE_REF ?= $(IMAGE):dns-5.3.0
PROJECT ?= $(CURDIR)
MOUNTS ?=
NETWORK ?= none
DRY_RUN ?= 0
LOCK_IMAGE_REF ?= $(IMAGE):lock-tools

export DOCKER IMAGE_REF GO_IMAGE_REF RUST_IMAGE_REF DNS_IMAGE_REF PROJECT MOUNTS NETWORK DRY_RUN
export LOCK_IMAGE_REF
.PHONY: build-lock-tools check-locks update-locks
.DEFAULT_GOAL := help
.PHONY: build-go lock-go check-go-lock verify-go check-go-project check-buf-project
.PHONY: build-rust lock-rust check-rust-lock verify-rust verify-rust-lock check-rust-project
.PHONY: build-dns lock-dns check-dns-lock verify-dns verify-dns-lock check-dns-project
.PHONY: help check-common-lock lock-common build rebuild pull run shell codex claude codex-remote codex-remote-start codex-remote-stop codex-remote-pair codex-remote-shell codex-remote-status test verify smoke smoke-daemon smoke-remote

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build a local development image
	$(DOCKER) build -t "$(IMAGE_REF)" .

build-lock-tools: ## Build the isolated lock generator without application installs
	$(DOCKER) build --target mise-bootstrap -t "$(LOCK_IMAGE_REF)-bootstrap" .
	$(DOCKER) build --build-arg "BASE_IMAGE=$(LOCK_IMAGE_REF)-bootstrap" -t "$(LOCK_IMAGE_REF)" tools/lock

check-locks: build-lock-tools ## Regenerate both Linux platform locks and reject differences
	bash scripts/lock-tools.sh check

update-locks: build-lock-tools ## Regenerate tool locks for review without changing declared pins
	bash scripts/lock-tools.sh update

check-common-lock: ## Check common application declarations and platform artifacts
	bash tests/check_tool_lock.sh tools/common

lock-common: ## Refresh common tool locks with the built image's pinned mise
	$(DOCKER) run --rm --user "$$(id -u):$$(id -g)" --network bridge --cap-drop ALL --security-opt no-new-privileges --mount "type=bind,source=$(CURDIR)/tools/common,target=/tools" -e MISE_CONFIG_FILE=/tools/config.toml -e MISE_DATA_DIR=/tmp/mise-data -e MISE_CACHE_DIR=/tmp/mise-cache -e MISE_STATE_DIR=/tmp/mise-state "$(IMAGE_REF)" mise --yes lock --global --platform linux-x64,linux-arm64
	chmod -R a+rX tools/common
	$(MAKE) check-common-lock

rebuild: ## Refresh the base and CLIs without build cache
	$(DOCKER) build --pull --no-cache -t "$(IMAGE_REF)" .

build-go: build check-go-lock ## Build the Go development image on the common image
	$(DOCKER) build --build-arg "BASE_IMAGE=$(IMAGE_REF)" -t "$(GO_IMAGE_REF)" images/go

verify-go: ## Check the Go toolchain and inherited agent environment
	$(MAKE) verify IMAGE_REF="$(GO_IMAGE_REF)"
	$(DOCKER) run --rm --network none --cap-drop ALL --security-opt no-new-privileges "$(GO_IMAGE_REF)" bash -ec 'test "$$(id -u)" != 0; test "$$(go env GOTOOLCHAIN)" = local; diff /usr/local/share/devcontainer-images/go-version.txt <(go version); test -x "$$(go env GOROOT)/bin/go"; gcc --version >/dev/null'
	$(DOCKER) run --rm --network none --cap-drop ALL --security-opt no-new-privileges "$(GO_IMAGE_REF)" bash -ec 'diff /usr/local/share/devcontainer-images/buf-version.txt <(buf --version); test "$$(buf --version)" = 1.73.0'
	$(DOCKER) run --rm --network none --cap-drop ALL --security-opt no-new-privileges "$(GO_IMAGE_REF)" bash -ec 'test ! -w /opt/dev-tools/mise; fixture=$$(mktemp -d); trap "rm -rf \"$$fixture\"" EXIT; cd "$$fixture"; printf "[tools]\ngo = \"0.0.0\"\nbuf = \"0.0.0\"\n" > mise.toml; test "$$(go env GOVERSION)" = go1.27.1; test "$$(buf --version)" = 1.73.0'

lock-go: build ## Refresh both Go/API lock platforms with the pinned mise
	$(DOCKER) build --target mise-bootstrap --build-arg "BASE_IMAGE=$(IMAGE_REF)" -t "$(IMAGE):go-mise-bootstrap" images/go
	$(DOCKER) run --rm --user "$$(id -u):$$(id -g)" --network bridge --cap-drop ALL --security-opt no-new-privileges --mount "type=bind,source=$(CURDIR)/images/go/tools,target=/tools" -e MISE_CONFIG_FILE=/tools/config.toml -e MISE_DATA_DIR=/tmp/mise-data -e MISE_CACHE_DIR=/tmp/mise-cache -e MISE_STATE_DIR=/tmp/mise-state "$(IMAGE):go-mise-bootstrap" mise --yes lock --global --platform linux-x64,linux-arm64
	chmod -R a+rX images/go/tools
	$(MAKE) check-go-lock

check-go-lock: ## Check Go/API declarations and both platform checksum records
	bash tests/check_tool_lock.sh images/go/tools

check-go-project: ## Check a Go PROJECT in a disposable copy, offline after dependency download
	bash tests/check_go_project.sh

check-buf-project: ## Check a Buf PROJECT in a disposable copy using its Make targets
	bash tests/check_buf_project.sh

build-rust: build check-rust-lock ## Build the Rust/LED development image on the common image
	$(DOCKER) build --build-arg "BASE_IMAGE=$(IMAGE_REF)" -t "$(RUST_IMAGE_REF)" images/rust

verify-rust: ## Check Rust, native libraries, and Ansible as non-root
	$(MAKE) verify IMAGE_REF="$(RUST_IMAGE_REF)"
	$(DOCKER) run --rm --network none --cap-drop ALL --security-opt no-new-privileges "$(RUST_IMAGE_REF)" bash -ec 'diff /usr/local/share/devcontainer-images/rust-versions.txt <(rustc --version; cargo --version; rustfmt --version; cargo clippy --version); protoc --version; pkg-config --exists alsa x11 wayland-client; python3 --version; ansible --version; ansible-lint --version; test -w "$$CARGO_HOME"; test ! -w "$$RUSTUP_HOME"'
	bash tests/smoke_rust.sh

lock-rust: ## Refresh Rust/Ansible locks using the built image and pinned uv
	$(DOCKER) run --rm --user "$$(id -u):$$(id -g)" --network bridge --cap-drop ALL --security-opt no-new-privileges --mount "type=bind,source=$(CURDIR)/images/rust/tools,target=/tools" -e MISE_CONFIG_FILE=/tools/config.toml -e MISE_DATA_DIR=/tmp/mise-data -e MISE_CACHE_DIR=/tmp/mise-cache -e MISE_STATE_DIR=/tmp/mise-state -e UV_CACHE_DIR=/tmp/uv-cache -e UV_PYTHON_DOWNLOADS=never "$(RUST_IMAGE_REF)" mise --yes lock --global --platform linux-x64,linux-arm64
	chmod -R a+rX images/rust/tools
	$(MAKE) check-rust-lock

check-rust-lock: ## Check Rust components, Python graph sidecars, and uv artifacts
	bash tests/check_tool_lock.sh images/rust/tools

verify-rust-lock: check-rust-lock ## Check corrupted Python dependency graph rejection
	bash tests/test_rust_lock.sh

check-rust-project: ## Check led-service2 in a disposable copy, offline after fetching crates
	bash tests/check_rust_project.sh

build-dns: build ## Build the DNS development image on the common image
	$(DOCKER) build --build-arg "BASE_IMAGE=$(IMAGE_REF)" -t "$(DNS_IMAGE_REF)" images/dns

lock-dns: build ## Refresh both DNS lock platforms with the pinned mise
	$(DOCKER) build --target mise-bootstrap --build-arg "BASE_IMAGE=$(IMAGE_REF)" -t "$(IMAGE):dns-mise-bootstrap" images/dns
	$(DOCKER) run --rm --user "$$(id -u):$$(id -g)" --network bridge --cap-drop ALL --security-opt no-new-privileges --mount "type=bind,source=$(CURDIR)/images/dns/tools,target=/tools" -e MISE_CONFIG_FILE=/tools/config.toml -e MISE_DATA_DIR=/tmp/mise-data -e MISE_CACHE_DIR=/tmp/mise-cache -e MISE_STATE_DIR=/tmp/mise-state "$(IMAGE):dns-mise-bootstrap" mise --yes lock --global --platform linux-x64,linux-arm64
	chmod -R a+rX images/dns/tools
	$(MAKE) check-dns-lock

verify-dns: ## Check DNS tools and dummy encryption without credentials
	$(MAKE) verify IMAGE_REF="$(DNS_IMAGE_REF)"
	bash tests/smoke_dns.sh

check-dns-lock: ## Check declarations and both platform checksum records
	bash tests/check_tool_lock.sh images/dns/tools

verify-dns-lock: check-dns-lock ## Check missing lock and bad checksum rejection (downloads a test artifact)
	bash tests/test_dns_lock.sh

check-dns-project: ## Check homelab-private DNS configuration offline without credentials
	bash tests/check_dns_project.sh

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
	$(DOCKER) run --rm --network none --cap-drop ALL --security-opt no-new-privileges "$(IMAGE_REF)" bash -ec 'mise --version | grep -q "^2026.10.3"; test ! -w /opt/dev-tools/mise; test "$$(yq -p toml -r ".tools.\"aqua:mikefarah/yq\"" /usr/local/share/devcontainer-images/common-tools/config.toml)" = 4.54.1'
	$(DOCKER) run --rm -i --network none --cap-drop ALL --security-opt no-new-privileges "$(IMAGE_REF)" node < tests/test_npm_release_age.cjs

smoke: ## Check mounts and state persistence with temporary fixtures
	bash tests/smoke_container.sh

smoke-daemon: ## Check a remote Docker daemon without runner bind mounts
	bash tests/smoke_daemon.sh

smoke-remote: ## Check remote lifecycle in Docker without credentials
	bash tests/smoke_codex_remote.sh
