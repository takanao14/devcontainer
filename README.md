# Devcontainer images

Ubuntu 26.04 development image with Codex CLI, Claude Code, a non-root
`developer` user, UTF-8 locale, Git, SSH client, GCC/G++, Make, and basic
command-line tools. sudo requires password authentication; the user has no
password configured in the image. The launcher also prevents privilege
escalation with `no-new-privileges`.

Docker must be running on the host. The launcher uses Bash and jq; YAML mounts
require Mike Farah yq v4. No Python runtime is required.

```sh
make build
make shell PROJECT=/absolute/path/to/project
```

`run` is an alias for `shell`. `make help` lists targets. For IDE integration,
open this repository with **Dev Containers: Reopen in Container**; this builds
locally and uses the same default network and privilege restrictions.

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
allowlist enforcement is not implemented yet. Neither the host home nor the
Docker socket is mounted. Processes can access all mounted source and agent
credentials allowed by their container permissions. Codex uses the container
boundary with `on-request` approvals (the model decides when to request
confirmation); Claude uses its default permission mode.
CLI approval prompts do not make writable source read-only.

Codex and Claude have separate named volumes per canonical project path for
configuration, authentication, and history. First sign-in happens inside the
container (`codex login --device-auth` can be run from `make shell` for Codex).
The launcher does not copy host credentials. It prints the volume names in a
dry run. To clear saved state, stop sessions and remove the corresponding
volume with `docker volume rm <volume-name>`; this also deletes configuration
and history. Back up state volumes before CLI updates if rollback is needed.

CLIs are installed at build time; in-container Claude updates are disabled.
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
access. CI execution and registry publication have not been verified here.
The initial workflow builds the runner's native architecture only.
See [CI setup and verification](docs/ci.md) for required settings and test coverage.

Use the published reference from CI, optionally a digest, to fetch and run
without building locally:

```sh
make pull IMAGE_REF=registry.example.com/owner/devcontainer-images:ci-commit-run-attempt
make shell IMAGE_REF=registry.example.com/owner/devcontainer-images:ci-commit-run-attempt PROJECT=/absolute/path/to/project
```

Updates select a newer published image; rollback selects a previous reference.
State format changes may require restoring a matching volume backup. Registry
retention and scheduled updates are not configured.

Project-specific toolchains are listed in [Project tool inventory](docs/project-tools.md)
and are not installed. The [implementation plan](docs/devcontainer-implementation-plan.md)
covers network enforcement, derived images, and remaining validation.
