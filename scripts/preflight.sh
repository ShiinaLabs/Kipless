#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test-common.sh
source "$SCRIPT_DIR/test-common.sh"

PREFLIGHT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kipless-preflight.XXXXXX")"

run_check() {
    local label="$1"
    shift

    printf '\n[%s]\n' "$label"
    "$@"
    printf '✓ %s\n' "$label"
}

run_unit_tests() {
    xcodebuild test \
        -project "$REPO_ROOT/Kipless.xcodeproj" \
        -scheme Kipless \
        -configuration Debug \
        -destination 'platform=macOS' \
        CODE_SIGNING_ALLOWED=NO \
        -quiet
}

run_release_build() {
    xcodebuild build \
        -project "$REPO_ROOT/Kipless.xcodeproj" \
        -scheme Kipless \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -quiet
}

final_cleanup() {
    local cleanup_result=0
    if ! assert_no_kipless_assertion >"$PREFLIGHT_DIR/final-assertions.txt" 2>&1; then
        printf 'Preflight found a leaked Kipless assertion.\n' >&2
        cleanup_result=1
    fi
    rm -rf "$PREFLIGHT_DIR"
    return "$cleanup_result"
}

trap final_cleanup EXIT

printf 'Kipless Preflight\n'
run_check 'Unit tests' run_unit_tests
run_check 'Release build' run_release_build
run_check 'System assertion' "$SCRIPT_DIR/test-power-assertions.sh" system
run_check 'Display assertion' "$SCRIPT_DIR/test-power-assertions.sh" display
run_check 'Assertion replacement' "$SCRIPT_DIR/test-power-assertions.sh" replacement
run_check 'Process cleanup' "$SCRIPT_DIR/test-process-cleanup.sh"
run_check 'App smoke test' "$SCRIPT_DIR/test-app-smoke.sh"
run_check 'Final assertion leak check' assert_no_kipless_assertion
printf '\nPASS\n'
