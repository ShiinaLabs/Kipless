#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test-common.sh
source "$SCRIPT_DIR/test-common.sh"

APP_PATH="${KIPLESS_APP_PATH:-$DERIVED_DATA_PATH/Build/Products/Release/Kipless.app}"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/Kipless"
SLEEP_HELPER_PATH="$APP_PATH/Contents/MacOS/KiplessSleepHelper"
SLEEP_HELPER_PLIST="$APP_PATH/Contents/Library/LaunchDaemons/com.kaoru.kipless.lidsleep.plist"
APP_PID=""
TEST_SUCCEEDED=0

find_app_pid() {
    pgrep -f -- "$APP_EXECUTABLE$" | head -n 1 || true
}

wait_for_app_exit() {
    local deadline=$((SECONDS + 5))

    while (( SECONDS < deadline )); do
        if [[ -z "$(find_app_pid)" ]]; then
            return 0
        fi
        sleep 0.2
    done

    return 1
}

cleanup() {
    local status=$?

    if (( TEST_SUCCEEDED == 0 )) && [[ -n "$APP_PID" ]]; then
        if kill -0 "$APP_PID" 2>/dev/null; then
            kill "$APP_PID" 2>/dev/null || true
            wait_for_app_exit || {
                kill -KILL "$APP_PID" 2>/dev/null || true
                wait "$APP_PID" 2>/dev/null || true
            }
        fi
    fi

    return "$status"
}

trap cleanup EXIT

terminate_app() {
    [[ -n "$APP_PID" ]] || return 0

    if kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait_for_app_exit || {
            kill -KILL "$APP_PID" 2>/dev/null || true
            wait "$APP_PID" 2>/dev/null || true
            wait_for_app_exit
        }
    else
        wait_for_app_exit
    fi

    APP_PID=""
}

printf 'Kipless app smoke tests\n'
printf '  release app build\n'
xcodebuild build \
    -project "$REPO_ROOT/Kipless.xcodeproj" \
    -scheme Kipless \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -quiet

[[ -x "$APP_EXECUTABLE" ]] || {
    printf 'Release app executable was not built at %s\n' "$APP_EXECUTABLE" >&2
    exit 1
}

printf '  bundle metadata\n'
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
ls_ui_element="$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP_PATH/Contents/Info.plist")"
minimum_system_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_PATH/Contents/Info.plist")"

[[ "$bundle_identifier" == 'com.kaoru.kipless' ]] || {
    printf 'Unexpected bundle identifier: %s\n' "$bundle_identifier" >&2
    exit 1
}
[[ "$ls_ui_element" == 'true' ]] || {
    printf 'LSUIElement must be true, got: %s\n' "$ls_ui_element" >&2
    exit 1
}
[[ "$minimum_system_version" == '14.0' ]] || {
    printf 'Unexpected minimum macOS version: %s\n' "$minimum_system_version" >&2
    exit 1
}

if find "$APP_PATH" -type f -name 'KiplessPowerTestHelper' -print -quit | grep -q .; then
    printf 'Power test helper must not be included in the app bundle.\n' >&2
    exit 1
fi

[[ -x "$SLEEP_HELPER_PATH" ]] || {
    printf 'Sleep helper was not embedded at %s\n' "$SLEEP_HELPER_PATH" >&2
    exit 1
}
[[ -f "$SLEEP_HELPER_PLIST" ]] || {
    printf 'Sleep helper LaunchDaemon plist was not embedded at %s\n' "$SLEEP_HELPER_PLIST" >&2
    exit 1
}
plutil -lint "$SLEEP_HELPER_PLIST" >/dev/null
helper_label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$SLEEP_HELPER_PLIST")"
helper_program="$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$SLEEP_HELPER_PLIST")"
helper_mach_service="$(/usr/libexec/PlistBuddy -c 'Print :MachServices:com.kaoru.kipless.lidsleep' "$SLEEP_HELPER_PLIST")"
[[ "$helper_label" == 'com.kaoru.kipless.lidsleep' ]] || {
    printf 'Unexpected sleep helper label: %s\n' "$helper_label" >&2
    exit 1
}
[[ "$helper_program" == 'Contents/MacOS/KiplessSleepHelper' ]] || {
    printf 'Unexpected sleep helper program path: %s\n' "$helper_program" >&2
    exit 1
}
[[ "$helper_mach_service" == 'true' ]] || {
    printf 'Sleep helper Mach service is not enabled.\n' >&2
    exit 1
}

printf '  signed app and helper with a Team ID\n'
codesign --verify --deep --strict "$APP_PATH"
# A daemon registered through SMAppService is only allowed to start when its
# signature carries a Team ID; an ad-hoc signed helper is killed by the kernel
# before main() runs, so fail the smoke test instead of shipping that.
helper_team="$(codesign -dv --verbose=4 "$SLEEP_HELPER_PATH" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[[ -n "$helper_team" && "$helper_team" != 'not set' ]] || {
    printf 'Sleep helper has no Team ID (%s); launchd will refuse to run it.\n' "${helper_team:-none}" >&2
    exit 1
}

if [[ -n "$(find_app_pid)" ]]; then
    printf 'A Kipless process is already running; refusing to attach smoke-test state.\n' >&2
    exit 1
fi

printf '  launch and no-immediate-crash\n'
assert_no_kipless_assertion
open -n "$APP_PATH"

for _ in {1..25}; do
    APP_PID="$(find_app_pid)"
    [[ -n "$APP_PID" ]] && break
    sleep 0.2
done

[[ -n "$APP_PID" ]] || {
    printf 'Kipless did not launch.\n' >&2
    exit 1
}
sleep 2
kill -0 "$APP_PID"
assert_no_kipless_assertion

printf '  terminate and release state\n'
terminate_app
assert_no_kipless_assertion
TEST_SUCCEEDED=1
printf 'App smoke tests passed.\n'
