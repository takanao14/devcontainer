#!/usr/bin/env bash
set -euo pipefail
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export BUILD_RECORD_DIR="$fixture/records" LOG="$fixture/log"
mkdir -p "$BUILD_RECORD_DIR" "$fixture/project"
PROJECT=$(cd "$fixture/project" && pwd -P)
export PROJECT
cat > "$fixture/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
    ps) [[ ${CONTAINER:-} != 1 ]] || echo container ;;
    inspect) printf '{"id":"container","Image":"sha256:old","Config":{"Image":"devcontainer-images:old"}}\n' ;;
    image)
        case "$2" in
            ls) jq -r '.selected_ref,.base_ref' "$BUILD_RECORD_DIR"/*/result.json ;;
            inspect) if [[ ${CHANGED:-} == 1 && $3 == devcontainer-images:old ]]; then echo sha256:changed;
                else echo "sha256:${3##*:}"; fi ;;
            rm) printf '%s\n' "$3" >> "$LOG" ;;
            *) exit 1 ;;
        esac ;;
    *) exit 1 ;;
esac
MOCK
chmod +x "$fixture/docker"
export DOCKER="$fixture/docker"
record() {
    local name=$1 status=$2 timestamp=$3
    mkdir -p "$BUILD_RECORD_DIR/$name"
    jq -n --arg ref "devcontainer-images:$name" --arg id "sha256:$name" --arg status "$status" --argjson time "$timestamp" \
      '{selected_ref:$ref,base_ref:$ref,image_id:$id,base_image_id:$id,kind:"infra",architecture:"arm64",status:$status,created_at:$time}' \
      > "$BUILD_RECORD_DIR/$name/result.json"
}
record old verified 1
record prior verified 2
jq '.base_ref = "devcontainer-images:base-prior" | .base_image_id = "sha256:base-prior"' \
  "$BUILD_RECORD_DIR/prior/result.json" > "$fixture/prior.json"
mv "$fixture/prior.json" "$BUILD_RECORD_DIR/prior/result.json"
record newest verified "$(date +%s)"
record failed failed 3
record legacy verified null
record recent-failure failed "$(date +%s)"
bash scripts/local-images.sh clean > "$fixture/plan"
grep -q $'DELETE\tdevcontainer-images:old' "$fixture/plan"
grep -q $'KEEP\tdevcontainer-images:newest' "$fixture/plan"
grep -q $'KEEP\tdevcontainer-images:legacy' "$fixture/plan"
grep -q $'KEEP\tdevcontainer-images:recent-failure' "$fixture/plan"
test ! -f "$LOG"
IMAGE_REF=devcontainer-images:old bash scripts/local-images.sh select
IMAGE_REF=devcontainer-images:prior bash scripts/local-images.sh select
IMAGE_REF=devcontainer-images:prior bash scripts/local-images.sh select
jq -e --arg p "$PROJECT" '.projects[$p].previous == "devcontainer-images:old"' "$BUILD_RECORD_DIR/retention.json" >/dev/null
IMAGE_REF=devcontainer-images:failed bash scripts/local-images.sh select && exit 1
IMAGE_REF=devcontainer-images:failed bash scripts/local-images.sh protect
APPLY=1 bash scripts/local-images.sh clean > "$fixture/plan"
grep -q $'KEEP\tdevcontainer-images:base-prior' "$fixture/plan"
test ! -f "$LOG"
IMAGE_REF=devcontainer-images:failed bash scripts/local-images.sh unprotect
APPLY=1 bash scripts/local-images.sh clean > "$fixture/plan"
test "$(cat "$LOG")" = devcontainer-images:failed
rm "$LOG" "$BUILD_RECORD_DIR/retention.json"
CONTAINER=1 APPLY=1 bash scripts/local-images.sh clean > "$fixture/plan"
if grep -qx devcontainer-images:old "$LOG"; then exit 1; fi
CHANGED=1 APPLY=1 bash scripts/local-images.sh clean > "$fixture/plan" 2> "$fixture/error" && exit 1
grep -q 'Image changed' "$fixture/error"
mkdir "$BUILD_RECORD_DIR/.management-lock"
bash scripts/local-images.sh clean > /dev/null 2>&1 && exit 1
printf 'Retention protects project selections, legacy records, containers, and changed images\n'
