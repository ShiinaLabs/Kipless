#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test-common.sh
source "$SCRIPT_DIR/test-common.sh"

APP_PATH="${KIPLESS_APP_PATH:-$DERIVED_DATA_PATH/Build/Products/Release/Kipless.app}"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/Kipless"
APP_PID=""

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
    local cleanup_result=0

    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait_for_app_exit || {
            kill -KILL "$APP_PID" 2>/dev/null || true
            wait "$APP_PID" 2>/dev/null || true
        }
    fi

    wait_for_no_kipless_assertion || cleanup_result=1
    return "$cleanup_result"
}

trap cleanup EXIT

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

printf '  ad-hoc code signature\n'
codesign --verify --deep --strict "$APP_PATH"

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

printf 'App smoke tests passed.\n'
