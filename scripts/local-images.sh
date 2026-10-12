#!/usr/bin/env bash
set -euo pipefail
action=${1:-list}
case "$action" in list|select|protect|unprotect|clean) ;; *) echo 'Unknown image management action' >&2; exit 2 ;; esac
record_root=${BUILD_RECORD_DIR:-.local-builds}
docker=${DOCKER:-docker}
image=${IMAGE:-devcontainer-images}
days=${KEEP_DAYS:-7}
[[ $days =~ ^[0-9]+$ && ${#days} -le 4 ]] || { echo 'KEEP_DAYS must be 0..9999' >&2; exit 2; }
# shellcheck source=scripts/local-state-lock.sh
source "$(dirname "$0")/local-state-lock.sh"
acquire_local_state_lock
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"; rmdir "$state_lock"' EXIT
state_file="$record_root/retention.json"
if [[ -f $state_file ]]; then cp "$state_file" "$fixture/state.json"; else
    printf '{"projects":{},"protected":[]}\n' > "$fixture/state.json"
fi
jq -e '(.projects | type == "object") and (.protected | type == "array") and
  all(.protected[]; type == "string") and
  all(.projects[]; (.current | type == "string") and
    ((.previous == null) or (.previous | type == "string")))' "$fixture/state.json" >/dev/null
: > "$fixture/records.jsonl"
for file in "$record_root"/*/result.json; do
    [[ -f $file ]] || continue
    jq -ce 'if (.selected_ref | type == "string") and (.base_ref | type == "string")
      and (.kind | type == "string") and (.architecture | type == "string")
      then . else error("Invalid build record") end' "$file" >> "$fixture/records.jsonl"
done
jq -s . "$fixture/records.jsonl" > "$fixture/records.json"
if [[ $action == select || $action == protect || $action == unprotect ]]; then
    ref=${IMAGE_REF:?Set IMAGE_REF to the chosen image}
    [[ $ref == "$image:"* ]] || { echo 'Reference is outside this image repository' >&2; exit 1; }
    if [[ $action != unprotect ]]; then "$docker" image inspect "$ref" >/dev/null; fi
    if [[ $action == select ]]; then
        project=$(cd -- "${PROJECT:?Set PROJECT}" && pwd -P)
        actual_id=$("$docker" image inspect "$ref" --format '{{.Id}}')
        jq -e --arg ref "$ref" --arg id "$actual_id" 'any(.[];
          .selected_ref == $ref and .status == "verified" and .image_id == $id)' "$fixture/records.json" >/dev/null ||
          { echo 'Selection requires a matching verified build record' >&2; exit 1; }
        jq --arg project "$project" --arg ref "$ref" '
          if .projects[$project].current == $ref then . else
          .projects[$project] = {current:$ref,previous:.projects[$project].current} end' "$fixture/state.json" > "$fixture/new.json"
    elif [[ $action == protect ]]; then
        jq --arg ref "$ref" '.protected |= (. + [$ref] | unique)' "$fixture/state.json" > "$fixture/new.json"
    else
        jq --arg ref "$ref" '.protected -= [$ref]' "$fixture/state.json" > "$fixture/new.json"
    fi
    mv "$fixture/new.json" "$state_file"
    printf '%s: %s\n' "$action" "$ref"
    exit
fi
container_snapshot() {
    "$docker" ps -aq > "$fixture/container-ids"
    local ids=()
    while IFS= read -r id; do [[ -z $id ]] || ids+=("$id"); done < "$fixture/container-ids"
    if (( ${#ids[@]} )); then
        "$docker" inspect --format '{"id":{{json .Id}},"Image":{{json .Image}},"Config":{"Image":{{json .Config.Image}}}}' "${ids[@]}" |
          jq -s 'sort_by(.id)' > "$fixture/containers.json"
    else
        printf '[]\n' > "$fixture/containers.json"
    fi
}
container_snapshot
"$docker" image ls "$image" --format '{{.Repository}}:{{.Tag}}' > "$fixture/tags"
now=$(date +%s)
jq -n --slurpfile records "$fixture/records.json" --slurpfile state "$fixture/state.json" \
    --slurpfile containers "$fixture/containers.json" --rawfile tags "$fixture/tags" --arg prefix "$image:" \
    --argjson cutoff "$((now - 10#$days * 86400))" '
  $records[0] as $r | $state[0] as $s | $containers[0] as $c |
  ([$s.projects[] | .current,.previous] + $s.protected | map(select(. != null))) as $p |
  ([$r[] | select(.status == "verified" and (.created_at | type == "number"))]
    | group_by([.kind,.architecture]) | map(sort_by(.created_at,.selected_ref) | last | .selected_ref)) as $latest |
  ([$r[] | .selected_ref,.base_ref] + ($tags | split("\n") | map(select(length > 0)))) | unique | map(. as $ref |
    select(($tags | split("\n") | index($ref)) != null) |
    [$r[] | select(.selected_ref == $ref or .base_ref == $ref)] as $owners |
    ([$owners[] | if .selected_ref == $ref then .image_id else .base_image_id end]
      | map(select(type == "string" and length > 0)) | unique) as $ids |
    [if ($owners | length) == 0 then "unrecorded image" else empty end,
     if ($ref | startswith($prefix) | not) then "unmanaged repository" else empty end,
     if any($owners[]; (.created_at | type != "number")) then "legacy record" else empty end,
     if ($ids | length) != 1 then "unknown image identity" else empty end,
     if ($p | index($ref)) != null then "selected/rollback/protected" else empty end,
     if any($owners[]; .selected_ref as $selected | ($p | index($selected)) != null) then "protected base" else empty end,
     if ($latest | index($ref)) != null or any($owners[]; .selected_ref as $selected | ($latest | index($selected)) != null)
       then "latest verified candidate/base" else empty end,
     if any($owners[]; (.created_at // 0) >= $cutoff) then "within retention period" else empty end,
     if any($c[]; .Config.Image == $ref or (.Image as $id | $ids | index($id)) != null)
       then "container reference" else empty end] as $reasons |
    {ref:$ref,id:($ids[0] // ""),delete:($reasons | length == 0),reasons:$reasons})' > "$fixture/plan.json"
jq -r '.[] | [if .delete then "DELETE" else "KEEP" end,.ref,(.reasons | join(", "))] | @tsv' "$fixture/plan.json"
if [[ $action != clean || ${APPLY:-0} != 1 ]]; then exit; fi
while IFS=$'\t' read -r ref expected_id; do
    # Stop on changed tags or container inventory; Docker deletion is never forced.
    actual_id=$("$docker" image inspect "$ref" --format '{{.Id}}' 2>/dev/null) || continue
    [[ $actual_id == "$expected_id" ]] || { echo "Image changed: $ref; rerun dry-run" >&2; exit 1; }
    cp "$fixture/containers.json" "$fixture/containers-before.json"
    container_snapshot
    cmp -s "$fixture/containers-before.json" "$fixture/containers.json" ||
      { echo 'Container inventory changed; rerun dry-run' >&2; exit 1; }
    "$docker" image rm "$ref"
done < <(jq -r '.[] | select(.delete) | [.ref,.id] | @tsv' "$fixture/plan.json")
