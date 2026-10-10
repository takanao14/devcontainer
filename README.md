# Devcontainer images

Ubuntu 26.04 development image with Codex CLI, Claude Code, a non-root
`developer` user, UTF-8 locale, Git, SSH client, GCC/G++, Make, and basic
command-line tools, including ripgrep, jq, Mike Farah yq v4.54.1, and ShellCheck.
sudo requires password authentication; the user has no
password configured in the image. The launcher also prevents privilege
escalation with `no-new-privileges`.

Docker must be running on the host. The launcher uses Bash and jq; YAML mounts
require Mike Farah yq v4. No Python runtime is required.

During configuration development, Apple Silicon Macs use locally built ARM64
images through Docker / OrbStack. The existing Forgejo CI builds and publishes
AMD64 images; ARM64 publication is not available yet. Local builds remain the
ARM64 usage path until the configuration is stable and ARM64 CI is available.

```sh
make build
make shell PROJECT=/absolute/path/to/project
```

`run` is an alias for `shell`. `make help` lists targets. Open the host project
in the Mac IDE; the container shares its source through the bind mount.
An IDE connection to the container is optional. This repository's
**Dev Containers: Reopen in Container** configuration builds a separate offline
container; it does not attach to the Make-managed remote environment or mount
the launcher's agent state volumes.

The Go/API image adds Go 1.27.1 and Buf 1.73.0 with verified release checksums.
Pinned mise 2026.10.3 installs them from committed Linux AMD64 / ARM64 locks.
Runtime commands use image-owned paths rather than project-selected mise shims.
Toolchain downloads at runtime are disabled (`GOTOOLCHAIN=local`).

```sh
make build-go
make verify-go
make check-go-lock
make check-go-project PROJECT=/absolute/path/to/go-project
make check-buf-project PROJECT=/absolute/path/to/led-image-api
make codex IMAGE_REF=devcontainer-images:go-1.27.1 PROJECT=/absolute/path/to/go-project NETWORK=bridge
```

`check-go-project` downloads dependencies over bridge networking, then runs
tests, race detection, vet, and build offline in a disposable source copy.
The host source is read-only; the temporary module cache is deleted afterward.
`check-buf-project` runs the project's `format-check`, `lint`, and
`generate-check` Make targets in a disposable copy. Remote generation uses
bridge networking and the project's pinned plugins.
Go/API declarations and their origin are in `images/go/tools`. Use `make lock-go`
after changing versions and review the lock diff before rebuilding.

The Rust/LED image adds Rust 1.99.0, rustfmt, Clippy, protoc, ALSA and X11/Wayland
development libraries, Python, ansible-core 2.21.5, and ansible-lint 26.9.0.
Its toolchain is owned by the image; Cargo's cache remains writable by the user.
mise declares Rust's profile and components and replays Ansible's committed
Python dependency graphs with uv 0.12.23. rustup 1.29.1 remains checksum-pinned.

```sh
make build-rust
make verify-rust
make check-rust-lock
make verify-rust-lock
make check-rust-project PROJECT=/absolute/path/to/led-service2
make codex IMAGE_REF=devcontainer-images:rust-1.99.0 PROJECT=/absolute/path/to/led-service2 NETWORK=bridge
```

`check-rust-project` requires initialized `led-image-api` submodule sources. It
fetches locked crates, then checks the emulator build, formatting, Clippy,
tests, Python tests, and Ansible lint offline in a disposable source copy.
It does not connect display, audio, or LED devices or deploy services.
Declarations and dependency sidecars are in `images/rust/tools`. Use `make lock-rust`
with a built Rust image and review the config, lock, and sidecar changes together.
The DNS image installs dnscontrol 5.3.0, SOPS 3.13.3, age 1.3.2, and direnv 2.37.1
through pinned mise 2026.10.3 and the committed platform lockfile. Commands use
direct image-owned paths, so project mise settings do not switch these tools.

```sh
make build-dns
make verify-dns
make verify-dns-lock  # Downloads an artifact to test checksum rejection
make check-dns-project PROJECT=/absolute/path/to/homelab-private
make codex IMAGE_REF=devcontainer-images:dns-5.3.0 PROJECT=/absolute/path/to/homelab-private NETWORK=bridge
```

`check-dns-project` runs `dns-record`'s `make check` offline in a disposable
copy without loading credentials or `.envrc`. Verification uses temporary
keys and dummy data for encryption; host keys are not mounted. direnv's shell
hook and environment approval are not enabled automatically.
The infrastructure image is not implemented yet.
DNS versions are declared in `images/dns/tools/config.toml`; `SOURCE` records
their origin. After changing declarations, use `make lock-dns` and review the
config and lock diff before rebuilding. SOPS uses the Aqua backend; mise trusts
checksum-backed provenance recorded in the lock without re-verifying SLSA at
installation time.

The common image supplies checksum-pinned mise 2026.10.3 and installs yq 4.54.1
from `tools/common`'s committed lock. APT still supplies OS packages and npm
installs agent CLIs under the CI image-update policy. `make check-common-lock`
checks the application lock; `make lock-common` refreshes its platform metadata.
New application releases have a two-day cooldown. Agent CLI installation uses
npm's `--before` cutoff for direct and transitive registry dependencies; the
cutoff is recorded in `npm-before.txt` alongside the resolved versions.
mise uses `minimum_release_age = "2d"` when selecting new versions or Python
dependencies. Existing reviewed pins and lock graphs remain reproducible;
changing an exact pin requires checking its release date. APT updates follow
the distribution's policy.

The launcher mounts only `PROJECT` read-write at `/workspace/<project-name>`.
Edits and deletions affect host files. Optional `MOUNTS` YAML has `readOnly` and
`readWrite` lists of absolute directory paths; see `mounts.example.yaml`.
`mounts.local.yaml` is ignored by Git. Inspect commands with `DRY_RUN=1`.

```sh
make codex PROJECT=/absolute/path/to/project NETWORK=bridge
make claude PROJECT=/absolute/path/to/project NETWORK=bridge
make shell PROJECT=/absolute/path/to/project MOUNTS=mounts.local.yaml
```

Networking defaults to `none`. `NETWORK=bridge` explicitly permits unrestricted
Docker bridge networking, including reachable internal services. Network
allowlists are optional; the experimental implementation is kept on
`feat/network-allowlist-experiment` and is unavailable on `main`.
Neither the host home nor the
Docker socket is mounted. Processes can access all mounted source and agent
credentials allowed by their container permissions. Codex uses the container
boundary with `on-request` approvals (the model decides when to request
confirmation); Claude uses its default permission mode.
CLI approval prompts do not make writable source read-only.

Remote connections to containerized Claude Code and Codex have been user-verified.
Smartphone approval and denial, and operation after tmux detachment, have also
been user-verified. The Codex remote environment runs independently of terminals:

```sh
make codex-remote-start NETWORK=bridge
make codex-remote-pair     # Initial pairing or adding a phone
make codex-remote-shell   # Exiting this shell keeps the environment running
make codex-remote-status
make codex-remote-stop
```

Use the same `PROJECT` for each operation. `codex-remote` aliases the start
operation. Start never issues a pairing code; pairing output is shown only in
the requesting terminal. Stop removes the container and retains state volumes.
Daemon stop has a 10-second timeout and a further 2-second kill grace period;
Docker waits up to 15 seconds for container shutdown. Stop failures are reported.
Starting an existing environment reuses it; changed mount, network, wrapper, or
image-reference settings require stopping it first. Rebuilding the same image
tag also requires stopping and starting to use the new image.
The wrapper is passed to the existing image at launch; no image rebuild is needed.
See [remote access and validation](docs/remote-access.md) for startup procedures.

Codex and Claude have separate named volumes per canonical project path for
configuration, authentication, and history. First sign-in happens inside the
container (`codex login --device-auth` can be run from `make shell` for Codex).
Reusing the Codex state volume after container recreation preserves access from
an already paired phone; this has been user-verified with the phone registration
retained.
The launcher does not copy host credentials. It prints the volume names in a
dry run. To clear saved state, stop sessions and remove the corresponding
volume with `docker volume rm <volume-name>`; this also deletes configuration
and history. Back up state volumes before CLI updates if rollback is needed.

CLIs are installed at build time; in-container Claude updates are disabled.
Remote startup selects the image-owned Codex daemon package and disables its
updater while retaining authentication, pairing, history, and other settings.
Stop the remote environment before switching images, then start it again.
`make rebuild` refreshes the base and CLIs without cache for local development.
`make verify` checks CLI versions and user permissions without credentials.
Resolved versions are recorded in `/usr/local/share/devcontainer-images/versions.txt`.

[Forgejo Actions](.forgejo/workflows/image.yml) tests, builds, and verifies on
pull requests and main pushes. Main pushes and manual runs on main publish a
unique `ci-<commit>-<run>-<attempt>` common image tag and
`dns-ci-<commit>-<run>-<attempt>` DNS image tag after both pass verification.
DNS checks cover both platform lock records and rejection of missing locks and
invalid checksums. The `ubuntu-24.04`
runner needs Docker, Make, Bash, jq, Mike Farah yq v4, Git, and Node.js for checkout. CI uses named-volume smoke tests so the job and daemon need not share
filesystem paths. Local `make smoke` separately verifies host bind mounts. Publication targets
`forgejo.home.butaco.net/takanao/devcontainer-images`; the registry hostname is
defined in the workflow. Configure `REGISTRY_USER` and `REGISTRY_PASSWORD` secrets with package write
access. CI runs #1 and #3 verified AMD64 builds, tests, and registry publication;
run #3 includes yq, ShellCheck, and remote lifecycle validation.
The initial workflow builds the runner's native architecture only.
See [CI setup and verification](docs/ci.md) for required settings and test coverage.
`renovate.json` applies the two-day cooldown to update candidates and includes
the custom mise config paths and mise/rustup bootstrap versions. Bootstrap
updates also require reviewing the published checksums and version checks.
The existing `takanao/renovate` service manages this repository; bot access and
dependency lookup with a GitHub fine-grained token have been verified.
Update proposals require Dependency Dashboard approval and are not automatically
merged. CI regenerates all four tool locks
for Linux x64 and ARM64 and rejects differences before building application
images. Run `make update-locks` to apply generated locks locally for review;
`make check-locks` checks them without modifying the working tree. These targets
use a disposable non-root container and `docker cp`, without shared daemon paths.
Applying generated locks also requires rsync on the host.
Generated Python manifests under `images/rust/tools/.mise/locks/` are excluded
from dependency extraction; the tool config remains the update source.

For AMD64, use the published reference from CI, optionally a digest, to fetch
and run without building locally:

```sh
make pull IMAGE_REF=registry.example.com/owner/devcontainer-images:ci-commit-run-attempt
make shell IMAGE_REF=registry.example.com/owner/devcontainer-images:ci-commit-run-attempt PROJECT=/absolute/path/to/project
```

Local ARM64 updates use `make rebuild`; published-image updates select a newer
reference, and rollback selects a previous reference.
State format changes may require restoring a matching volume backup. Registry
retention and scheduled updates are not configured.

Project-specific toolchains are supplied by the derived images. The
[Project tool inventory](docs/project-tools.md) lists requirements and validation.
The [implementation plan](docs/devcontainer-implementation-plan.md) covers remaining isolation and validation work.
