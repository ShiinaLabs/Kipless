#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-common.sh"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kipless-process-cleanup.XXXXXX")"
ACTIVE_PID=""

cleanup() {
    local cleanup_result=0

    if [[ -n "$ACTIVE_PID" ]]; then
        kill_helper "$ACTIVE_PID" || cleanup_result=1
        ACTIVE_PID=""
    fi

    wait_for_no_kipless_assertion || cleanup_result=1
    rm -rf "$TEST_DIR"
    return "$cleanup_result"
}

trap cleanup EXIT

run_kill_test() {
    local mode="$1"
    local output_file="$TEST_DIR/kill-$mode.log"

    printf '  %s assertion survives SIGKILL cleanup\n' "$mode"
    assert_no_kipless_assertion

    start_helper "hold-$mode" "$output_file"
    ACTIVE_PID="$HELPER_PID"
    wait_for_marker "$ACTIVE_PID" "$output_file" "KIPLESS_ASSERTION_READY $mode"
    wait_for_assertion "$mode"

    kill_helper "$ACTIVE_PID"
    ACTIVE_PID=""
    wait_for_no_kipless_assertion
}

printf 'Kipless process cleanup integration tests\n'
build_power_helper
run_kill_test system
run_kill_test display
printf 'Process cleanup integration tests passed.\n'
