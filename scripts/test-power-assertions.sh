#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test-common.sh
source "$SCRIPT_DIR/test-common.sh"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kipless-power.XXXXXX")"
ACTIVE_PID=""

cleanup() {
    local cleanup_result=0
    if [[ -n "$ACTIVE_PID" ]]; then
        kill_helper "$ACTIVE_PID"
    fi
    wait_for_no_kipless_assertion || cleanup_result=1
    rm -rf "$TEST_DIR"
    return "$cleanup_result"
}
trap cleanup EXIT

run_acquire_release_test() {
    local mode="$1"
    local output_file="$TEST_DIR/$mode.log"

    printf '  %s assertion acquire/release\n' "$mode"
    assert_no_kipless_assertion
    start_helper "hold-$mode" "$output_file"
    ACTIVE_PID="$HELPER_PID"
    wait_for_marker "$ACTIVE_PID" "$output_file" "KIPLESS_ASSERTION_READY $mode"
    wait_for_assertion "$mode"
    stop_helper "$ACTIVE_PID"
    ACTIVE_PID=""
    grep -Fq "KIPLESS_ASSERTION_RELEASED $mode" "$output_file" || {
        printf 'Helper did not release the %s assertion on normal termination. Output:\n' "$mode" >&2
        cat "$output_file" >&2
        return 1
    }
    wait_for_no_kipless_assertion
}

run_replacement_test() {
    local first="$1"
    local second="$2"
    local command="replace-$first-$second"
    local output_file="$TEST_DIR/$command.log"

    printf '  %s → %s assertion replacement\n' "$first" "$second"
    assert_no_kipless_assertion
    start_helper "$command" "$output_file"
    ACTIVE_PID="$HELPER_PID"
    wait_for_marker "$ACTIVE_PID" "$output_file" "KIPLESS_ASSERTION_READY $second"
    wait_for_assertion "$second"
    assert_no_mode_assertion "$first"
    stop_helper "$ACTIVE_PID"
    ACTIVE_PID=""
    grep -Fq "KIPLESS_ASSERTION_RELEASED $second" "$output_file" || {
        printf 'Helper did not release the replacement assertion on normal termination. Output:\n' >&2
        cat "$output_file" >&2
        return 1
    }
    wait_for_no_kipless_assertion
}

printf 'Kipless power assertion integration tests\n'
build_power_helper
case "${1:-all}" in
    all)
        run_acquire_release_test system
        run_acquire_release_test display
        run_replacement_test system display
        run_replacement_test display system
        ;;
    system)
        run_acquire_release_test system
        ;;
    display)
        run_acquire_release_test display
        ;;
    replacement)
        run_replacement_test system display
        run_replacement_test display system
        ;;
    *)
        printf 'Usage: %s [all|system|display|replacement]\n' "${BASH_SOURCE[0]}" >&2
        exit 2
        ;;
esac
printf 'Power assertion integration tests passed.\n'
