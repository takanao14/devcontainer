#!/usr/bin/env bash
# Shared by local builds and retention operations.
# shellcheck disable=SC2154
acquire_local_state_lock() {
    mkdir -p "$record_root"
    state_lock="$record_root/.management-lock"
    if ! mkdir "$state_lock" 2>/dev/null; then
        echo 'Local image management is busy; retry after the other operation finishes.' >&2
        exit 1
    fi
}
