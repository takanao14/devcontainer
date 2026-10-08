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
unique `ci-<commit>-<run>-<attempt>` tag after verification. The `ubuntu-24.04`
runner needs Docker, Make, Bash, jq, Mike Farah yq v4, Git, and Node.js for checkout. CI uses named-volume smoke tests so the job and daemon need not share
filesystem paths. Local `make smoke` separately verifies host bind mounts. Publication targets
`forgejo.home.butaco.net/takanao/devcontainer-images`; the registry hostname is
defined in the workflow. Configure `REGISTRY_USER` and `REGISTRY_PASSWORD` secrets with package write
access. CI runs #1 and #3 verified AMD64 builds, tests, and registry publication;
run #3 includes yq, ShellCheck, and remote lifecycle validation.
The initial workflow builds the runner's native architecture only.
See [CI setup and verification](docs/ci.md) for required settings and test coverage.

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

Project-specific toolchains are listed in [Project tool inventory](docs/project-tools.md)
and are not installed. The [implementation plan](docs/devcontainer-implementation-plan.md)
covers network enforcement, derived images, and remaining validation.
