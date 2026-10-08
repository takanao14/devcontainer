#!/usr/bin/env bash
# Commands are evaluated inside the container.
# shellcheck disable=SC2016
set -euo pipefail
docker=${DOCKER:-docker}
image=${GO_IMAGE_REF:?GO_IMAGE_REF is required}
project=$(cd -- "${PROJECT:?PROJECT is required}" && pwd -P)
[[ -f $project/go.mod ]] || { printf 'error: PROJECT must contain go.mod\n' >&2; exit 1; }
[[ $project != *','* ]] || { printf 'error: PROJECT cannot contain a comma\n' >&2; exit 1; }
cache="devcontainer-go-check-$$-$RANDOM"
trap '"$docker" volume rm "$cache" >/dev/null 2>&1 || true' EXIT
"$docker" run --rm --network bridge --cap-drop ALL --security-opt no-new-privileges \
    --mount "type=bind,source=$project,target=/source,readonly" \
    --mount "type=volume,source=$cache,target=/home/developer/go" \
    "$image" bash -ec '
      mkdir /tmp/project
      rsync -a --exclude=.git /source/ /tmp/project/
      cd /tmp/project
      go mod download
    '
# Execute checks offline: no access to project hardware or external services.
"$docker" run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    --mount "type=bind,source=$project,target=/source,readonly" \
    --mount "type=volume,source=$cache,target=/home/developer/go" \
    "$image" bash -ec '
      mkdir /tmp/project
      rsync -a --exclude=.git /source/ /tmp/project/
      cd /tmp/project
      export GOPROXY=off
      go version
      go test ./...
      go test -race ./...
      go vet ./...
      go build ./...
    '
printf 'Go project tests, race detection, vet, and build passed offline\n'
