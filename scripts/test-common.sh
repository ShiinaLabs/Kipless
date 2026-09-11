#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
DERIVED_DATA_PATH="${KIPLESS_DERIVED_DATA_PATH:-$REPO_ROOT/.build/derived-data}"
HELPER_PATH="${KIPLESS_POWER_HELPER:-$DERIVED_DATA_PATH/Build/Products/Debug/KiplessPowerTestHelper}"
POWER_REASON="Kipless is keeping your Mac awake."
HELPER_PID=""

export REPO_ROOT DERIVED_DATA_PATH HELPER_PATH POWER_REASON

build_power_helper() {
    xcodebuild build \
        -project "$REPO_ROOT/Kipless.xcodeproj" \
        -scheme KiplessPowerTestHelper \
        -configuration Debug \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        CODE_SIGNING_ALLOWED=NO \
        -quiet

    if [[ ! -x "$HELPER_PATH" ]]; then
        printf 'Power helper was not built at %s\n' "$HELPER_PATH" >&2
        return 1
    fi
}

assertions() {
    pmset -g assertions
}

assert_no_kipless_assertion() {
    local current
    current="$(assertions)"
    if grep -Fq "$POWER_REASON" <<<"$current"; then
        printf '%s\n' "$current" >&2
        printf 'Found a leaked Kipless power assertion.\n' >&2
        return 1
    fi
}

assertion_type_for_mode() {
    case "$1" in
        system) printf '%s\n' 'PreventUserIdleSystemSleep' ;;
        display) printf '%s\n' 'PreventUserIdleDisplaySleep' ;;
        *) printf 'Unknown power mode: %s\n' "$1" >&2; return 1 ;;
    esac
}

assert_has_mode_assertion() {
    local mode="$1"
    local expected_type
    local current
    expected_type="$(assertion_type_for_mode "$mode")"
    current="$(assertions)"

    grep -F "$POWER_REASON" <<<"$current" | grep -Fq "$expected_type"
}

assert_no_mode_assertion() {
    local mode="$1"
    local expected_type
    local current
    expected_type="$(assertion_type_for_mode "$mode")"
    current="$(assertions)"

    if grep -F "$POWER_REASON" <<<"$current" | grep -Fq "$expected_type"; then
        printf '%s\n' "$current" >&2
        printf 'Found an unexpected %s Kipless assertion.\n' "$mode" >&2
        return 1
    fi
}

wait_for_assertion() {
    local mode="$1"
    local deadline=$((SECONDS + 5))

    while (( SECONDS < deadline )); do
        if assert_has_mode_assertion "$mode"; then
            return 0
        fi
        sleep 0.2
    done

    printf 'Timed out waiting for the %s Kipless assertion.\n' "$mode" >&2
    assertions >&2
    return 1
}

wait_for_no_kipless_assertion() {
    local deadline=$((SECONDS + 5))

    while (( SECONDS < deadline )); do
        if assert_no_kipless_assertion; then
            return 0
        fi
        sleep 0.2
    done

    printf 'Timed out waiting for Kipless assertions to disappear.\n' >&2
    assertions >&2
    return 1
}

start_helper() {
    local command="$1"
    local output_file="$2"

    "$HELPER_PATH" "$command" >"$output_file" 2>&1 &
    # shellcheck disable=SC2034
    HELPER_PID=$!
}

wait_for_marker() {
    local pid="$1"
    local output_file="$2"
    local marker="$3"
    local deadline=$((SECONDS + 5))

    while (( SECONDS < deadline )); do
        if grep -Fq "$marker" "$output_file" 2>/dev/null; then
            return 0
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            printf 'Helper exited before emitting %s. Output:\n' "$marker" >&2
            cat "$output_file" >&2
            return 1
        fi
        sleep 0.2
    done

    printf 'Timed out waiting for helper marker %s. Output:\n' "$marker" >&2
    cat "$output_file" >&2
    return 1
}

stop_helper() {
    local pid="$1"

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
}

kill_helper() {
    local pid="$1"

    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
}
