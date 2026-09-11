# Kipless Automated Testing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the three-layer Kipless test system: fast GitHub CI, real local IOKit integration tests, and a one-command release preflight.

**Architecture:** Keep `WakeSessionManager` unit-testable through its existing `SleepAsserting` protocol and Mock implementation. Add a separate `KiplessPowerTestHelper` executable that owns real IOKit assertions only during local tests; shell scripts launch it, inspect `pmset -g assertions`, and always clean it up. Keep GitHub Actions limited to deterministic Debug tests and Debug/Release compilation, while `preflight.sh` composes all local and packaging checks.

**Tech Stack:** Swift 6, SwiftUI/AppKit, IOKit Power Management, XCTest, Bash, GitHub Actions, XcodeGen.

**Spec:** `docs/testing-plan.md`, derived from the user-provided Kipless automated testing plan.

## Global Constraints

- GitHub CI runs only fast deterministic tests and Debug/Release builds.
- Real power-management integration tests run only on the developer's Mac.
- No integration test waits for 15, 30, 60, or 120 minutes.
- Every integration script uses `trap cleanup EXIT` and fails if a Kipless assertion remains.
- `KiplessPowerTestHelper` is a separate executable and is never copied into the app bundle.
- Release checks accept the local ad-hoc signature; Developer ID signing and notarization remain in the Release workflow.
- The Bundle ID remains `com.kaoru.kipless`; the minimum OS remains macOS 14.
- Scripts use only the existing macOS command-line tools and the helper; no third-party runtime dependency is added.
- No passwords, tokens, certificates, or other secrets are written to the repository.

## File Map

- Create `docs/testing-plan.md`: durable project-facing version of the three-layer test contract.
- Modify `.gitignore`: ignore the local `.build/` scratch directory used by scripts.
- Modify `project.yml` and regenerate `Kipless.xcodeproj/project.pbxproj`: add the helper executable target and scheme.
- Create `KiplessPowerTestHelper/main.swift`: real IOKit assertion helper with one-shot, hold, and replacement commands.
- Modify `KiplessTests/WakeSessionManagerTests.swift`: complete missing lifecycle and replacement coverage.
- Modify `KiplessTests/WakeSessionTests.swift`: document the required model and mode contracts.
- Create `scripts/test-common.sh`: shared repository paths, helper build, assertion parsing, polling, and cleanup primitives.
- Create `scripts/test-power-assertions.sh`: system/display acquire-release and replacement integration tests.
- Create `scripts/test-process-cleanup.sh`: `kill -9` cleanup tests for system and display assertions.
- Create `scripts/test-integration.sh`: local integration entry point composing assertion and process tests.
- Create `scripts/test-app-smoke.sh`: Release app launch, process, bundle, signature, and leak checks.
- Create `scripts/preflight.sh`: one-command release gate with ordered checks and final leak check.
- Modify `.github/workflows/ci.yml`: add Xcode output and unsigned Release build.
- Modify `.github/workflows/release.yml`: normalize tag output for tag and manual dispatch paths.
- Modify `README.md`, `docs/plan.md`, and the Obsidian Kipless index: document the runnable test commands and boundaries.

### Task 1: Capture the testing contract and expand deterministic unit coverage

**Files:**
- Create: `docs/testing-plan.md`
- Modify: `KiplessTests/WakeSessionManagerTests.swift`
- Modify: `KiplessTests/WakeSessionTests.swift`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: existing `WakeSessionManager`, `WakeSession`, `WakeDuration`, `WakeMode`, `MockSleepAssertionManager`.
- Produces: deterministic XCTest coverage for every CI-level session invariant and a repository test contract.

- [x] **Step 1: Write the failing lifecycle tests**

Add these tests to `WakeSessionManagerTests` before changing production code:

```swift
func testSwitchingFromDisplayToSystemKeepsOneAssertion() {
    manager.start(mode: .display, duration: .indefinite)
    manager.start(mode: .system, duration: .indefinite)

    XCTAssertEqual(manager.session?.mode, .system)
    XCTAssertEqual(assertions.maxHeldCount, 1)
    XCTAssertEqual(assertions.events, [
        .release, .acquire(.display), .release, .acquire(.system)
    ])
}

func testFailedReplacementLeavesTheManagerInactiveAndReleasesTheOldAssertion() {
    manager.start(mode: .system, duration: .indefinite)
    assertions.errorToThrow = SleepAssertionError.creationFailed(mode: .display, code: -1)

    manager.start(mode: .display, duration: .indefinite)

    XCTAssertFalse(manager.isActive)
    XCTAssertNil(manager.session)
    XCTAssertFalse(assertions.isHolding)
    XCTAssertEqual(assertions.maxHeldCount, 1)
}
```

- [x] **Step 2: Run the focused tests and verify the expected red state**

Run:

```bash
xcodebuild test -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS' \
  -only-testing:KiplessTests/WakeSessionManagerTests/testSwitchingFromDisplayToSystemKeepsOneAssertion \
  -only-testing:KiplessTests/WakeSessionManagerTests/testFailedReplacementLeavesTheManagerInactiveAndReleasesTheOldAssertion
```

Expected: the first test is already green if the existing replacement invariant is complete; if it is green, keep it as a regression test. The second test must fail only if the existing mock event expectation exposes a lifecycle defect; otherwise keep both as passing regression coverage and proceed without changing manager behavior.

- [x] **Step 3: Add the complete testing-plan document**

Write `docs/testing-plan.md` with the three layers, helper command interface, exact scripts, release blockers, CI exclusions, and PASS output described by the user. Keep the explicit non-goals: no real sleep, no long durations, no Launch at Login E2E, no DMG/notarization in ordinary CI, and no nightly workflow.

- [x] **Step 4: Ignore only generated local scratch output**

Append this exact rule to `.gitignore`:

```gitignore
# Local test/build scratch output
.build/
```

- [x] **Step 5: Run all unit tests**

Run:

```bash
xcodebuild test -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS'
```

Expected: all XCTest cases pass with no test failure.

### Task 2: Add the real IOKit power-test helper target

**Files:**
- Create: `KiplessPowerTestHelper/main.swift`
- Modify: `project.yml`
- Regenerate: `Kipless.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: macOS `IOPMAssertionCreateWithName`, `IOPMAssertionRelease`, and `WakeMode` semantics.
- Produces: executable commands `system`, `display`, `hold-system`, `hold-display`, `replace-system-display`, and `replace-display-system`.

- [x] **Step 1: Define the helper command contract in the test plan**

The helper prints `KIPLESS_ASSERTION_READY <mode>` after acquisition, prints `KIPLESS_ASSERTION_RELEASED <mode>` after normal release, and exits nonzero for an invalid command or IOKit failure. `system` and `display` hold for one second; `hold-*` run until terminated; replacement commands release the first assertion before acquiring the second and then hold the second.

- [x] **Step 2: Write the helper executable**

Implement the following shape in `main.swift`:

```swift
import Foundation
import IOKit.pwr_mgt

enum HelperFailure: Error { case usage, assertion(IOReturn) }

let command = CommandLine.arguments.dropFirst().first ?? ""
let reason = "Kipless is keeping your Mac awake." as CFString

func assertionType(for mode: String) -> CFString? {
    switch mode {
    case "system": kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
    case "display": kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
    default: nil
    }
}

func acquire(_ mode: String) throws -> IOPMAssertionID {
    guard let type = assertionType(for: mode) else { throw HelperFailure.usage }
    var id: IOPMAssertionID = 0
    let result = IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id)
    guard result == kIOReturnSuccess else { throw HelperFailure.assertion(result) }
    return id
}
```

Use `FileHandle.standardOutput.write` for readiness markers so the shell scripts can reliably read them through a pipe. Release one-shot assertions with `defer`; hold commands keep the process alive with `RunLoop.current.run(until:)` and rely on the OS to clean the assertion after `SIGKILL`.

- [x] **Step 3: Add the target and dedicated scheme to `project.yml`**

Add:

```yaml
  KiplessPowerTestHelper:
    type: tool
    platform: macOS
    sources:
      - path: KiplessPowerTestHelper
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.kaoru.kipless.power-test-helper
        PRODUCT_NAME: KiplessPowerTestHelper

schemes:
  KiplessPowerTestHelper:
    build:
      targets:
        KiplessPowerTestHelper: all
```

Regenerate the checked-in project with `xcodegen generate` and confirm the helper is not a dependency or resource of the `Kipless` application target.

- [x] **Step 4: Build and run every helper command**

Run:

```bash
xcodebuild build -project Kipless.xcodeproj -scheme KiplessPowerTestHelper -configuration Debug -destination 'platform=macOS'
HELPER="$(xcodebuild -project Kipless.xcodeproj -scheme KiplessPowerTestHelper -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F ' = ' '/TARGET_BUILD_DIR/{print $2; exit}')/KiplessPowerTestHelper"
"$HELPER" system
"$HELPER" display
```

Expected: both commands exit 0 after a short hold and print their release marker.

### Task 3: Build shared shell primitives and assertion integration tests

**Files:**
- Create: `scripts/test-common.sh`
- Create: `scripts/test-power-assertions.sh`
- Create: `scripts/test-integration.sh`

**Interfaces:**
- Consumes: `KiplessPowerTestHelper` Debug build and `pmset -g assertions`.
- Produces: `./scripts/test-power-assertions.sh` and `./scripts/test-integration.sh` with exit 1 on any failed assertion or cleanup check.

- [x] **Step 1: Define common functions**

`test-common.sh` must export `REPO_ROOT`, `DERIVED_DATA_PATH`, and `HELPER_PATH`, and define:

```bash
build_power_helper() { ...; }
assertions() { pmset -g assertions; }
assert_no_kipless_assertion() { ...; }
wait_for_assertion() { mode="$1"; ...; }
wait_for_no_kipless_assertion() { ...; }
kill_helper() { ...; }
```

`wait_for_assertion` polls for at most 5 seconds at 0.2-second intervals and checks both the exact reason string and the expected `PreventUserIdleSystemSleep` or `PreventUserIdleDisplaySleep` type. All temporary files are created below `mktemp -d` and removed by `cleanup`.

- [x] **Step 2: Add System and Display acquire-release tests**

For each mode, run `hold-system` or `hold-display` in the background, wait for its readiness marker and matching `pmset` record, then terminate normally, wait for the process, and require `assert_no_kipless_assertion`.

- [x] **Step 3: Add replacement tests**

Run each replacement helper command, verify after its readiness marker that the final type is present and the first type is absent, then stop the helper and verify the final leak check.

- [x] **Step 4: Add the integration wrapper**

`test-integration.sh` uses `set -Eeuo pipefail`, sources `test-common.sh`, and runs `test-power-assertions.sh` followed by `test-process-cleanup.sh` with a concise `Kipless local integration tests` header. It must propagate the first nonzero exit code.

- [x] **Step 5: Make scripts executable and run them locally**

Run:

```bash
chmod +x scripts/test-common.sh scripts/test-power-assertions.sh scripts/test-integration.sh
./scripts/test-power-assertions.sh
./scripts/test-integration.sh
```

Expected: System, Display, and both replacement paths pass; final output confirms no Kipless assertion remains.

### Task 4: Add process-death cleanup tests

**Files:**
- Create: `scripts/test-process-cleanup.sh`

**Interfaces:**
- Consumes: helper `hold-system` and `hold-display`, common assertion functions.
- Produces: a release-blocking test for macOS cleanup after `kill -9`.

- [x] **Step 1: Implement one mode's kill test**

Start the selected hold helper in the background, wait for the exact assertion, record the PID, execute `kill -KILL "$pid"`, wait up to 2 seconds for process exit, then poll until the reason string disappears. The cleanup trap must also kill the PID if a preceding assertion fails.

- [x] **Step 2: Run both modes**

Invoke the same function for `system` and `display`; never use an unbounded wait and never kill a process selected by a broad name pattern.

- [x] **Step 3: Verify the test**

Run:

```bash
./scripts/test-process-cleanup.sh
```

Expected: both processes die by `SIGKILL` and both assertions disappear without manual intervention.

### Task 5: Add Release app smoke and Preflight orchestration

**Files:**
- Create: `scripts/test-app-smoke.sh`
- Create: `scripts/preflight.sh`

**Interfaces:**
- Consumes: unit test command, Release `Kipless.app`, local integration scripts, `PlistBuddy`, `codesign`, and `pmset`.
- Produces: `./scripts/preflight.sh` as the only release-readiness command, exiting 1 at the first failed gate.

- [x] **Step 1: Implement app smoke checks**

`test-app-smoke.sh` must build Release with the normal local ad-hoc identity, resolve the exact app path from the build settings, verify:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
```

It must refuse to continue if a pre-existing Kipless process is already running, launch the exact app with `open -n`, find only that PID by its full executable path, wait 2 seconds, confirm it remains alive, confirm no Kipless assertion exists, then terminate that exact PID and confirm both process and assertion are gone.

- [x] **Step 2: Implement `preflight.sh`**

The script prints the named check result and runs in this order:

```text
Unit tests
Release build
System assertion
Display assertion
Assertion replacement
Process cleanup
App smoke test
Bundle metadata
Code signature
No leaked assertions
```

Use a temporary result directory and a single `trap cleanup EXIT`; after every child script, run a final `pmset -g assertions` leak check. Print `PASS` only after all commands exit 0.

- [x] **Step 3: Run the full local gate**

Run:

```bash
./scripts/preflight.sh
```

Expected: all checks pass on the developer Mac, and a second standalone `pmset -g assertions` check has no Kipless reason string.

### Task 6: Harden Fast CI and Release workflow tag handling

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: XcodeGen-generated project and existing release secrets.
- Produces: deterministic CI builds and a release workflow whose tag is identical for tag pushes and manual dispatch.

- [x] **Step 1: Add the Release build to CI**

Keep `xcodebuild -version`, then run unsigned Debug tests and an unsigned Release build:

```yaml
      - name: Debug tests
        run: |
          xcodebuild test \
            -project Kipless.xcodeproj \
            -scheme Kipless \
            -configuration Debug \
            -destination 'platform=macOS' \
            CODE_SIGNING_ALLOWED=NO

      - name: Release build
        run: |
          xcodebuild build \
            -project Kipless.xcodeproj \
            -scheme Kipless \
            -configuration Release \
            -destination 'platform=macOS' \
            CODE_SIGNING_ALLOWED=NO
```

- [x] **Step 2: Normalize Release workflow outputs**

Expose `INPUT_VERSION` and `REF_NAME` through the step environment, strip one leading `v`, validate `^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$`, and emit both `version` and `tag`:

```bash
if [ -n "$INPUT_VERSION" ]; then
  VERSION="${INPUT_VERSION#v}"
else
  VERSION="${REF_NAME#v}"
fi
printf 'version=%s\n' "$VERSION" >> "$GITHUB_OUTPUT"
printf 'tag=v%s\n' "$VERSION" >> "$GITHUB_OUTPUT"
```

Use `${{ steps.version.outputs.tag }}` in `gh release create` and keep the archive's marketing/build versions sourced from the same step outputs.

- [x] **Step 3: Validate workflow YAML and shell syntax**

Run:

```bash
bash -n scripts/*.sh
git diff --check
```

### Task 7: Document, validate, and hand off

**Files:**
- Modify: `README.md`
- Modify: `docs/plan.md`
- Modify: `docs/testing-plan.md`
- Modify: `/Users/kaoru/Documents/Obsidian Vault/ShiinaLabs/Kipless 索引.md`

**Interfaces:**
- Consumes: the completed scripts, helper target, CI workflow, and release workflow.
- Produces: durable developer instructions and a verified working tree.

- [x] **Step 1: Document commands**

Add the following command table to `README.md` and `docs/testing-plan.md`:

```text
Fast CI equivalent: xcodebuild test ... CODE_SIGNING_ALLOWED=NO
Local integration: ./scripts/test-integration.sh
Release gate: ./scripts/preflight.sh
```

State that local integration must run on a real Mac, does not sleep the machine, and uses assertions lasting only seconds.

- [x] **Step 2: Run the complete verification matrix**

Run all of:

```bash
bash -n scripts/*.sh
xcodebuild test -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS'
xcodebuild build -project Kipless.xcodeproj -scheme Kipless -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
./scripts/test-integration.sh
./scripts/preflight.sh
git diff --check
```

Expected: every command exits 0 and the final power assertion leak check is empty. If the local Mac cannot run a real IOKit check, report that exact environmental blocker instead of weakening the integration assertions.

- [x] **Step 3: Review repository state**

Confirm the helper is not packaged in `Kipless.app`, no secret-like files are staged, and `.build/` is ignored. Leave a concise progress entry in the Obsidian Kipless index with the test-layer status, helper target, script entry points, and any environment-only limitation.
