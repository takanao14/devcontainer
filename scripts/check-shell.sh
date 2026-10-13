#!/usr/bin/env bash
set -euo pipefail
for directory in scripts tests tools images; do
    while IFS= read -r -d '' file; do
        bash -n "$file"
        shellcheck -x -P . "$file"
    done < <(find "$directory" -type f -name '*.sh' -print0)
done
while IFS= read -r -d '' workflow; do
    yq -r '.jobs[].steps[] | select(has("run")) | .run' "$workflow" | bash -n
done < <(find .github/workflows -type f -name '*.yml' -print0)
