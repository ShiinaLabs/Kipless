#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
ARCHIVE_PATH="${1:-$REPO_ROOT/.build/KiplessAppStore.xcarchive}"
APP_PATH="$ARCHIVE_PATH/Products/Applications/KiplessAppStore.app"
PRODUCT_BUNDLE_IDENTIFIER="com.kaoru.kipless.mas"

fail() {
    printf 'App Store archive check failed: %s\n' "$1" >&2
    exit 1
}

printf 'Kipless Mac App Store archive checks\n'

[[ -d "$ARCHIVE_PATH" ]] || fail "archive is missing: $ARCHIVE_PATH"
[[ -d "$APP_PATH" ]] || fail "archived app is missing"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" == "$PRODUCT_BUNDLE_IDENTIFIER" ]] || fail "archive has the wrong Bundle ID"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP_PATH/Contents/Info.plist")" == "true" ]] || fail "archived app must be an accessory app"

codesign --verify --deep --strict "$APP_PATH" || fail "archive app signature is invalid"

signed_entitlements="$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null)" || fail "archive entitlements cannot be read"
grep -Fq '<key>com.apple.security.app-sandbox</key>' <<<"$signed_entitlements" || fail "archive is not signed with App Sandbox"
grep -Fq '<key>com.apple.security.get-task-allow</key>' <<<"$signed_entitlements" && fail "archive contains the debug get-task-allow entitlement"

[[ ! -e "$APP_PATH/Contents/MacOS/KiplessSleepHelper" ]] || fail "archive embeds KiplessSleepHelper"
[[ ! -e "$APP_PATH/Contents/Library/LaunchDaemons" ]] || fail "archive embeds a LaunchDaemon"
[[ ! -e "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]] || fail "archive embeds Sparkle"
grep -Fq 'SUFeedURL' "$APP_PATH/Contents/Info.plist" && fail "archive contains Sparkle feed metadata"
grep -Fq 'SUPublicEDKey' "$APP_PATH/Contents/Info.plist" && fail "archive contains Sparkle signing metadata"

for localization in de en es fr it ja ko pt-BR zh-Hans zh-Hant; do
    [[ -f "$APP_PATH/Contents/Resources/$localization.lproj/Localizable.strings" ]] || fail "archive is missing $localization localization"
done

binary="$APP_PATH/Contents/MacOS/KiplessAppStore"
[[ -x "$binary" ]] || fail "archive executable is missing"
strings "$binary" | grep -Fq 'pmset disablesleep' && fail "archive contains the Closed Lid pmset path"
strings "$binary" | grep -Fq 'KiplessSleepHelper' && fail "archive contains helper symbols"
strings "$binary" | grep -Fq 'Closed Lid' && fail "archive contains Closed Lid UI text"

printf 'PASS\n'
