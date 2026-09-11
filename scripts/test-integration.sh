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
printf 'Kipless local integration tests passed.\n'
