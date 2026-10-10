#!/usr/bin/env bash
set -euo pipefail

: "${COMMIT:?COMMIT is required}"
: "${RUN_ID:?RUN_ID is required}"
: "${ATTEMPT:?ATTEMPT is required}"
: "${CONTAINER_REGISTRY:?CONTAINER_REGISTRY is required}"
: "${REPOSITORY:?REPOSITORY is required}"
[[ $COMMIT =~ ^[a-f0-9]{40}$ && $RUN_ID =~ ^[0-9]+$ && $ATTEMPT =~ ^[0-9]+$ ]]
[[ $CONTAINER_REGISTRY =~ ^[a-zA-Z0-9.-]+(:[0-9]+)?$ ]]
[[ $REPOSITORY =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]

docker_command=${DOCKER:-docker}
tag="ci-${COMMIT}-${RUN_ID}-${ATTEMPT}"
repository=${REPOSITORY,,}
refs=("devcontainer-images:locks-${COMMIT}-${RUN_ID}-${ATTEMPT}"
      "devcontainer-images:locks-${COMMIT}-${RUN_ID}-${ATTEMPT}-bootstrap")
for prefix in '' dns- go- rust-; do
    refs+=("devcontainer-images:${prefix}${tag}"
           "${CONTAINER_REGISTRY}/${repository}:${prefix}${tag}")
done

failed=0
for ref in "${refs[@]}"; do
    if "$docker_command" image inspect "$ref" >/dev/null 2>&1; then
        # Remove only this run's tags; never force removal of an in-use image.
        "$docker_command" image rm "$ref" || failed=1
    fi
done
"$docker_command" system df
exit "$failed"
