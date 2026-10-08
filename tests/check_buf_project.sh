#!/usr/bin/env bash
# Commands are evaluated inside the container.
# shellcheck disable=SC2016
set -euo pipefail
docker=${DOCKER:-docker}
image=${GO_IMAGE_REF:?GO_IMAGE_REF is required}
project=$(cd -- "${PROJECT:?PROJECT is required}" && pwd -P)
[[ -f $project/buf.yaml && -f $project/buf.gen.yaml ]] || {
    printf 'error: PROJECT must contain buf.yaml and buf.gen.yaml\n' >&2
    exit 1
}
[[ $project != *','* ]] || { printf 'error: PROJECT cannot contain a comma\n' >&2; exit 1; }
"$docker" run --rm --network bridge --cap-drop ALL --security-opt no-new-privileges \
    --mount "type=bind,source=$project,target=/source,readonly" \
    "$image" bash -ec '
      mkdir /tmp/project
      rsync -a --exclude=.git /source/ /tmp/project/
      cd /tmp/project
      buf --version
      make format-check lint generate-check
    '
printf 'Buf formatting, lint, and generated bindings checks passed\n'
