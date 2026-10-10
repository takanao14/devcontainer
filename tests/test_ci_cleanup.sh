#!/usr/bin/env bash
set -euo pipefail
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export COMMIT=1111111111111111111111111111111111111111 RUN_ID=42 ATTEMPT=2
export CONTAINER_REGISTRY=forgejo.example.test REPOSITORY=Owner/Repo
export CLEANUP_LOG="$fixture/commands" DOCKER="$fixture/docker"
cat > "$DOCKER" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CLEANUP_LOG"
if [[ $1 == image && $2 == inspect && $3 == *locks* ]]; then exit 1; fi
if [[ $1 == image && $2 == rm && ${FAIL_REMOVE:-0} == 1 ]]; then exit 1; fi
SH
chmod +x "$DOCKER"
bash scripts/ci-cleanup-images.sh
test "$(grep -c '^image rm ' "$CLEANUP_LOG")" = 8
if grep -Eq '^image rm .*locks|prune|--force' "$CLEANUP_LOG"; then exit 1; fi
for prefix in '' dns- go- rust-; do
    grep -Fx "image rm devcontainer-images:${prefix}ci-${COMMIT}-42-2" "$CLEANUP_LOG" >/dev/null
    grep -Fx "image rm forgejo.example.test/owner/repo:${prefix}ci-${COMMIT}-42-2" "$CLEANUP_LOG" >/dev/null
done
if FAIL_REMOVE=1 bash scripts/ci-cleanup-images.sh; then
    printf 'Cleanup ignored a removal failure\n' >&2; exit 1
fi
: > "$CLEANUP_LOG"
if RUN_ID=invalid bash scripts/ci-cleanup-images.sh; then exit 1; fi
test ! -s "$CLEANUP_LOG"
printf 'CI cleanup scopes tags to this run and reports removal failures\n'
