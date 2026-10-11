#!/usr/bin/env bash
set -euo pipefail
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export LOG="$fixture/commands"
cat > "$fixture/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'docker %s\n' "$*" >> "$LOG"
case "$1" in
    info) echo aarch64 ;;
    image) echo sha256:test ;;
    run) echo 'codex-cli test' ;;
esac
MOCK
cat > "$fixture/make" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'make %s\n' "$*" >> "$LOG"
[[ ${FAIL_STEP:-} != "$1" ]]
MOCK
chmod +x "$fixture/docker" "$fixture/make"
export DOCKER="$fixture/docker" MAKE="$fixture/make" BUILD_RECORD_DIR="$fixture/records"
bash scripts/local-update.sh infra rebuild
record=$(find "$BUILD_RECORD_DIR" -name result.json)
jq -e '.status == "verified" and .architecture == "arm64" and .kind == "infra" and .mode == "rebuild"' "$record" >/dev/null
base=$(jq -r .base_ref "$record")
grep -F "make build-infra IMAGE_REF=$base INFRA_IMAGE_REF=" "$LOG" >/dev/null
grep -F 'make verify-infra-lock INFRA_IMAGE_REF=' "$LOG" >/dev/null
if grep -E 'prune|remote-stop|volume rm|docker tag' "$LOG"; then exit 1; fi
bash scripts/local-update.sh common build
export FAIL_STEP=verify-infra-lock
if bash scripts/local-update.sh infra build; then echo 'Accepted failed lock verification' >&2; exit 1; fi
export FAIL_STEP=verify-local
if bash scripts/local-update.sh go build; then echo 'Accepted failed verification' >&2; exit 1; fi
jq -se 'length == 4 and ([.[].selected_ref] | unique | length) == 4 and ([.[] | select(.status == "failed")] | length) == 2' "$BUILD_RECORD_DIR"/*/result.json >/dev/null
if grep -q 'make build-go' "$LOG"; then echo 'Built derivative after base verification failure' >&2; exit 1; fi
if bash scripts/local-update.sh dns; then exit 1; fi
if bash scripts/local-update.sh invalid; then exit 1; fi
printf 'Local candidate isolation and failure handling passed\n'
