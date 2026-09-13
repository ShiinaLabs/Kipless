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

run_release_bundle_checks() {
    local app_path="$DERIVED_DATA_PATH/Build/Products/Release/Kipless.app"
    local helper_path="$app_path/Contents/MacOS/KiplessSleepHelper"
    local helper_plist="$app_path/Contents/Library/LaunchDaemons/com.kaoru.kipless.lidsleep.plist"

    [[ -x "$helper_path" ]] || {
        printf 'Sleep helper is missing or not executable: %s\n' "$helper_path" >&2
        return 1
    }
    [[ -f "$helper_plist" ]] || {
        printf 'Sleep helper LaunchDaemon plist is missing: %s\n' "$helper_plist" >&2
        return 1
    }
    plutil -lint "$helper_plist" >/dev/null
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$helper_plist")" == 'com.kaoru.kipless.lidsleep' ]] || return 1
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$helper_plist")" == 'Contents/MacOS/KiplessSleepHelper' ]] || return 1

    # The system derives a launch requirement for the daemon from the plist:
    # signing identifier == the program's file name, plus the Developer ID team.
    # A helper built with an embedded Info.plist (which renames the identifier)
    # or signed ad-hoc fails it and is killed by the kernel on every launch.
    [[ "$(codesign -dv --verbose=2 "$helper_path" 2>&1 | sed -n 's/^Identifier=//p')" == 'com.kaoru.kipless.lidsleep' ]] || {
        printf 'Sleep helper signing identifier must be com.kaoru.kipless.lidsleep.\n' >&2
        return 1
    }
    [[ "$(codesign -dv --verbose=2 "$helper_path" 2>&1 | sed -n 's/^TeamIdentifier=//p')" != 'not set' ]] || {
        printf 'Sleep helper must be signed with a Developer ID team.\n' >&2
        return 1
    }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :MachServices:com.kaoru.kipless.lidsleep' "$helper_plist")" == 'true' ]] || return 1

    local sparkle_path="$app_path/Contents/Frameworks/Sparkle.framework"

    # Sparkle installs an update by handing off to its own updater and then
    # swapping the app out, so it has to be embedded along with the XPC services
    # it drives the install through. Notarization rejects the DMG if any of that
    # nested code is unsigned or carries a different team, and the app cannot
    # update at all without the XPC services.
    [[ -d "$sparkle_path" ]] || {
        printf 'Sparkle.framework is not embedded: %s\n' "$sparkle_path" >&2
        return 1
    }
    [[ -d "$sparkle_path/Versions/Current/XPCServices" ]] || {
        printf 'Sparkle is embedded without its XPC services.\n' >&2
        return 1
    }

    # Without this key no downloaded update can be verified, so a build without
    # it could ship but never update.
    [[ -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app_path/Contents/Info.plist" 2>/dev/null)" ]] || {
        printf 'Info.plist has no SUPublicEDKey; no update could be verified.\n' >&2
        return 1
    }
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
run_check 'Release helper bundle' run_release_bundle_checks
run_check 'System assertion' "$SCRIPT_DIR/test-power-assertions.sh" system
run_check 'Display assertion' "$SCRIPT_DIR/test-power-assertions.sh" display
run_check 'Assertion replacement' "$SCRIPT_DIR/test-power-assertions.sh" replacement
run_check 'Process cleanup' "$SCRIPT_DIR/test-process-cleanup.sh"
run_check 'App smoke test' "$SCRIPT_DIR/test-app-smoke.sh"
run_check 'Final assertion leak check' assert_no_kipless_assertion
printf '\nPASS\n'
