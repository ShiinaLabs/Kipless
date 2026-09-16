#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
PROJECT_PATH="$REPO_ROOT/Kipless.xcodeproj"
SCHEME="KiplessAppStore"
DERIVED_DATA_PATH="${KIPLESS_APP_STORE_DERIVED_DATA_PATH:-$REPO_ROOT/.build/app-store-derived-data}"
PRODUCT_BUNDLE_IDENTIFIER="com.kaoru.kipless.mas"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/KiplessAppStore.app"

fail() {
    printf 'App Store target check failed: %s\n' "$1" >&2
    exit 1
}

printf 'Kipless Mac App Store target checks\n'

build_settings="$(xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null)" || {
    fail "scheme $SCHEME is not available"
}

grep -Fq "PRODUCT_BUNDLE_IDENTIFIER = $PRODUCT_BUNDLE_IDENTIFIER" <<<"$build_settings" || {
    fail "unexpected MAS Bundle ID"
}
grep -Fq 'CODE_SIGN_ENTITLEMENTS = KiplessAppStore/KiplessAppStore.entitlements' <<<"$build_settings" || {
    fail "MAS entitlements file is not configured"
}
grep -Fq 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = KIPLESS_APP_STORE' <<<"$build_settings" || {
    fail "MAS target does not enable the App Store compilation boundary"
}

xcodebuild build \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    -quiet

[[ -x "$APP_PATH/Contents/MacOS/KiplessAppStore" ]] || fail "MAS app executable is missing"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" == "$PRODUCT_BUNDLE_IDENTIFIER" ]] || fail "MAS Info.plist has the wrong Bundle ID"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP_PATH/Contents/Info.plist")" == "true" ]] || fail "MAS app must be an accessory app"

[[ -f "$REPO_ROOT/KiplessAppStore/KiplessAppStore.entitlements" ]] || fail "MAS entitlements file is missing"
grep -Fq '<key>com.apple.security.app-sandbox</key>' "$REPO_ROOT/KiplessAppStore/KiplessAppStore.entitlements" || fail "App Sandbox entitlement is missing"
grep -Fq '<true/>' "$REPO_ROOT/KiplessAppStore/KiplessAppStore.entitlements" || fail "App Sandbox entitlement is not enabled"

[[ ! -e "$APP_PATH/Contents/MacOS/KiplessSleepHelper" ]] || fail "MAS app embeds KiplessSleepHelper"
[[ ! -e "$APP_PATH/Contents/Library/LaunchDaemons" ]] || fail "MAS app embeds a LaunchDaemon"
[[ ! -e "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]] || fail "MAS app embeds Sparkle"
grep -Fq 'SUFeedURL' "$APP_PATH/Contents/Info.plist" && fail "MAS Info.plist contains Sparkle feed metadata"
grep -Fq 'SUPublicEDKey' "$APP_PATH/Contents/Info.plist" && fail "MAS Info.plist contains Sparkle signing metadata"

binary="$APP_PATH/Contents/MacOS/KiplessAppStore"
strings "$binary" | grep -Fq 'Closed Lid' && fail "MAS binary contains Closed Lid UI text"
strings "$binary" | grep -Fq 'pmset disablesleep' && fail "MAS binary contains the Closed Lid pmset path"
strings "$binary" | grep -Fq 'KiplessSleepHelper' && fail "MAS binary contains helper symbols"

smoke_output="$($binary --smoke-test 2>&1)" || {
    printf '%s\n' "$smoke_output" >&2
    fail "MAS power assertion smoke test failed"
}
grep -Fq 'KIPLESS_APP_STORE_POWER_ASSERTIONS_PASS' <<<"$smoke_output" || {
    printf '%s\n' "$smoke_output" >&2
    fail "MAS power assertion smoke test did not report success"
}

printf 'PASS\n'
