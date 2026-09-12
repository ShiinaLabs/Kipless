#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test-common.sh
source "$SCRIPT_DIR/test-common.sh"

cleanup() {
    wait_for_no_kipless_assertion
}

trap cleanup EXIT

printf 'Kipless local integration tests\n'
bash "$SCRIPT_DIR/test-power-assertions.sh"
bash "$SCRIPT_DIR/test-process-cleanup.sh"

if [[ "${KIPLESS_RUN_LID_AWAKE_INTEGRATION:-0}" == "1" ]]; then
    printf 'Closed-lid helper tests will temporarily modify SleepDisabled.\n'
    xcodebuild test \
        -project "$REPO_ROOT/Kipless.xcodeproj" \
        -scheme Kipless \
        -configuration Debug \
        -destination 'platform=macOS' \
        -only-testing:KiplessTests/LidAwakeIntegrationTests
else
    printf 'Skipping closed-lid helper tests (set KIPLESS_RUN_LID_AWAKE_INTEGRATION=1 to opt in).\n'
fi

printf 'Kipless local integration tests passed.\n'
