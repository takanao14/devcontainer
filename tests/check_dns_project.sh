#!/usr/bin/env bash
# Commands are evaluated inside the container.
# shellcheck disable=SC2016
set -euo pipefail
docker=${DOCKER:-docker}
project=$(cd -- "${PROJECT:?PROJECT is required}/dns-record" && pwd -P)
[[ $project != *','* ]] || { printf 'error: PROJECT cannot contain a comma\n' >&2; exit 1; }
"$docker" run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    --mount "type=bind,source=$project,target=/source,readonly" \
    "${DNS_IMAGE_REF:?DNS_IMAGE_REF is required}" bash -ec '
      mkdir /tmp/project
      rsync -a --exclude=.git --exclude=.envrc --exclude="secrets*" --exclude=creds.json /source/ /tmp/project/
      cd /tmp/project
      if ! make check > /tmp/dns-check.log 2>&1; then
        printf "error: DNS static check failed; inspect locally with make check (zone output suppressed)\n" >&2
        exit 1
      fi
    '
printf 'DNS project static checks passed offline without credentials\n'
