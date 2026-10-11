# Devcontainer images

Ubuntu 26.04 development image with Codex CLI, Claude Code, a non-root
`developer` user, UTF-8 locale, Git, SSH client, GCC/G++, Make, and basic
command-line tools, including ripgrep, jq, Mike Farah yq v4.54.1, and ShellCheck.
sudo requires password authentication; the user has no
password configured in the image. The launcher also prevents privilege
escalation with `no-new-privileges`.

Docker must be running on the host. The launcher uses Bash and jq; YAML mounts
require Mike Farah yq v4. No Python runtime is required.

Each usage machine builds and verifies its own native images. Apple Silicon
Macs use ARM64 through Docker / OrbStack. Forgejo CI runs static repository
checks without building containers or publishing images.

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
Pinned mise 2026.10.4 installs them from committed Linux AMD64 / ARM64 locks.
Runtime commands use image-owned paths rather than project-selected mise shims.
Toolchain downloads at runtime are disabled (`GOTOOLCHAIN=local`).

```sh
make build
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
make build
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

The initial infrastructure image provides Terraform 1.16.5, Terragrunt 1.1.6,
Packer 1.16.1, DNSControl 5.3.1, SOPS 3.13.3, age 1.3.2, and direnv 2.38.1
using reviewed mise locks for Linux AMD64 and ARM64. DNS and infrastructure
projects use the same image with separate project mounts and state volumes.
Terraform is an image pin because homelab does not pin an exact CLI version;
Terragrunt and Packer match homelab's existing declarations. The image uses
fixed executable paths and disables HashiCorp checkpoint requests.

```sh
make update-local KIND=infra
# Use the verified candidate printed by the command:
make check-dns-project INFRA_IMAGE_REF=<verified-infra-reference> PROJECT=/absolute/path/to/homelab-private
make check-infra-project INFRA_IMAGE_REF=<verified-infra-reference> PROJECT=/absolute/path/to/homelab
make codex IMAGE_REF=<verified-infra-reference> PROJECT=/absolute/path/to/homelab NETWORK=bridge
```

For direct builds, first build the common image, then use `make build-infra`
and `make verify-infra` plus `make verify-infra-lock` (downloads a test artifact).
`check-infra-lock` checks both platform records;
`update-locks` and `check-locks` include the infrastructure declarations.
`check-infra-project` mounts only `tf/` and `packer/` read-only and checks a
disposable copy offline. It checks Terraform/Terragrunt formatting and Packer
syntax, without provider/plugin validation, backend access, or deployment.
`check-dns-project` runs homelab-private's `dns-record` checks offline in a
disposable copy without loading credentials or `.envrc`. Encryption tests use
temporary keys and dummy data. direnv's shell hook and environment approval
are not enabled automatically. SOPS uses checksum-backed provenance in the
reviewed lock without re-verifying SLSA at installation time.

QEMU, Ansible collections, Kubernetes tools, and other infrastructure tools
remain future additions. Host credentials and Docker/device access are not
part of this image.

The common image supplies checksum-pinned mise 2026.10.4 and installs yq 4.54.1
from `tools/common`'s committed lock. APT still supplies OS packages and npm
installs agent CLIs under the local image-update policy. `make check-common-lock`
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

[Forgejo Actions](.forgejo/workflows/image.yml) runs `make check` on pull requests,
main pushes, and manual runs. Checks include mock launcher/lifecycle tests,
committed lock consistency, shell syntax, ShellCheck, and npm release-age tests.
The runner needs Bash, Make, Git, jq, Mike Farah yq v4, ShellCheck, Node.js, and npm;
Docker and registry credentials are not required. Runtime checks run locally.
See [CI and local verification](docs/ci.md) for coverage and migration cleanup.

`renovate.json` applies the two-day cooldown to update candidates and includes
the custom mise config paths and mise/rustup bootstrap versions. Bootstrap
updates also require reviewing the published checksums and version checks.
The existing `takanao/renovate` service manages this repository; bot access and
dependency lookup with a GitHub fine-grained token have been verified.
Update proposals require Dependency Dashboard approval and are not automatically
merged. Tool locks for Linux x64 and ARM64 are regenerated and compared locally. Run `make update-locks` to apply generated locks locally for review;
`make check-locks` checks them without modifying the working tree. These targets
use a disposable non-root container and `docker cp`, without shared daemon paths.
Applying generated locks also requires rsync on the host.
Generated Python manifests under `images/rust/tools/.mise/locks/` are excluded
from dependency extraction; the tool config remains the update source.

Use a unique verified candidate for updates:

```sh
make update-local KIND=common UPDATE_MODE=rebuild
# KIND=go, rust, or infra also builds and verifies that derived image.
# Use the Verified candidate printed by the command:
make codex IMAGE_REF=devcontainer-images:local-<build-id> PROJECT=/absolute/path/to/project NETWORK=bridge
```

`update-local` never replaces an existing tag, stops a running environment, or
removes state. It verifies the common image before building the selected
component. `.local-builds/<build-id>/result.json` records the source commit,
working-tree changes, architecture, selected reference, image ID, versions,
and success or failure. Failed candidates are retained for investigation.
Direct `build-*` targets require an existing `IMAGE_REF` and do not rebuild it.
`make verify-local` checks common tools, permissions, mounts, state persistence,
and mock remote shutdown. Derived checks use `verify-go`,
`verify-rust`, or `verify-infra`, plus the infrastructure/Rust lock rejection checks.

Keep the previous image reference before switching. Stop remote sessions with
`make codex-remote-stop PROJECT=/absolute/path/to/project`, and close other
sessions using the same state volumes. Inspect `DRY_RUN=1` output for their
names. For each stopped state volume, create a protected backup directory and
archive it using the old image (repeat for Codex and Claude):

```sh
umask 077
mkdir -p /absolute/path/to/state-backup
docker run --rm --user 0 --network none --cap-drop ALL --cap-add DAC_OVERRIDE --security-opt no-new-privileges \
  --mount type=volume,source=<state-volume>,target=/state,readonly \
  --mount type=bind,source=/absolute/path/to/state-backup,target=/backup \
  <old-image-reference> tar -C /state -czf /backup/<state-volume>.tar.gz .
```

Backups contain credentials and history; keep them outside Git. Start the new
reference explicitly. To roll back, stop sessions and select the old reference.
If the old CLI cannot read the changed state, restore its matching archive into
a new temporary volume first:

```sh
docker volume create <restore-check-volume>
docker run --rm --user 0 --network none --cap-drop ALL \
  --cap-add DAC_OVERRIDE --cap-add CHOWN --cap-add FOWNER --security-opt no-new-privileges \
  --mount type=volume,source=<restore-check-volume>,target=/state \
  --mount type=bind,source=/absolute/path/to/state-backup,target=/backup,readonly \
  <old-image-reference> tar --numeric-owner -C /state -xzf /backup/<state-volume>.tar.gz
docker run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
  --mount type=volume,source=<restore-check-volume>,target=/state,readonly \
  <old-image-reference> ls -la /state
```

After checking that archive extraction succeeded and the developer can read
its state, preserve a separate backup of the failed new state. With every
session stopped, remove and recreate only the original named state volume,
then repeat the extraction command with that original name. Start the old
image and confirm authentication, pairing, and history. Keep both backups
until recovery succeeds; delete the temporary verification volume afterward.
`make pull` remains available for optional external image references.
Image and cache cleanup is an explicit operator action; no automatic prune is
part of builds. Same-commit rebuilds can differ because CLI and APT selection
also depends on build time.

Project-specific toolchains are supplied by the derived images. The
[Project tool inventory](docs/project-tools.md) lists requirements and validation.
The [implementation plan](docs/devcontainer-implementation-plan.md) covers remaining isolation and validation work.
