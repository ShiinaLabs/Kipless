# Closed-Lid Keep Awake Implementation Plan (superseded)

> This earlier plan described an independent `LidAwakeManager` toggle. It was
> superseded by the three-mode plan in `docs/closed-lid-mode.md`: `System`,
> `Display`, and `Closed Lid` now share one `WakeSession` lifecycle.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a safe, independently controlled “Stay awake with lid closed” modifier backed by a constrained root LaunchDaemon, without changing the existing Wake Session modes or the released `v1.0.0` behavior.

**Architecture:** The app keeps its existing IOKit assertion path for the two Wake Session modes. A separate `LidAwakeManager` talks through a small XPC client to an embedded, root `KiplessSleepHelper` LaunchDaemon. The helper owns the `SleepDisabled` baseline and lease, executes only fixed `/usr/bin/pmset` operations, verifies every state change, and restores the baseline when the app releases or loses its XPC connection.

**Tech Stack:** Swift 6, SwiftUI, Foundation, Observation, ServiceManagement (`SMAppService`), `NSXPCConnection`, `Process`, XcodeGen, XCTest, macOS 14+.

**Spec:** User-provided Closed-Lid Keep Awake plan in the referenced “睡眠工具规划” conversation and attachment `/Users/kaoru/.codex/attachments/5ab2fb8c-fa2a-4bda-9cc7-ac2da3151134/pasted-text.txt`.

## Global Constraints

- Minimum platform remains macOS 14.
- Existing `WakeMode` remains exactly `system` and `display`; lid awake is a modifier, never a third mode.
- Existing `WakeSessionManager`, IOKit assertions, timer semantics, finite Quiet Ring, and indefinite `∞` presentation remain behaviorally unchanged.
- Lid awake is independent of the Wake Session: do not start it automatically with a Session and do not stop it automatically when a Session ends.
- The helper may only read `pmset -g` and set `pmset -a disablesleep 1` or `pmset -a disablesleep 0`.
- Do not expose `execute(command:)`, `runShell`, `run(arguments:)`, arbitrary command strings, or arbitrary argument arrays through XPC or the helper implementation.
- Every write must be followed by a real state read; unknown or unparseable state is an error, never an enabled/disabled guess.
- Preserve the pre-existing `SleepDisabled` baseline. Kipless may restore only a change it made itself.
- No onboarding, permission explanation page, warning sheet, battery/temperature policy, notification, automation rule, closed-lid detector, reboot recovery, or complex status UI in this change.
- The existing uncommitted layout changes must be preserved: no central divider, left panel 180pt, right panel 204pt, total popover width 384pt.
- Do not launch Kipless automatically during implementation or verification. Real closed-lid behavior remains an explicit manual test.
- Do not commit or push changes unless the user explicitly asks; use `git diff`, tests, and checkpoints for review in this session.

## File Map

Create the following focused modules:

- `Kipless/Shared/SleepOverrideModels.swift` — state codes and typed errors shared by the app and helper.
- `Kipless/Shared/KiplessSleepHelperProtocol.swift` — the Objective-C-compatible XPC interface with only `getState`, `acquireSleepOverride`, and `releaseSleepOverride`.
- `Kipless/Services/PMSetSleepOverrideDriver.swift` — fixed-path `/usr/bin/pmset` adapter; no shell and no caller-supplied arguments.
- `Kipless/Services/SleepOverrideController.swift` — helper-side baseline ownership and lease state machine.
- `KiplessSleepHelper/main.swift` — LaunchDaemon entry point and XPC listener setup.
- `KiplessSleepHelper/SleepHelperService.swift` — XPC exported object and connection-specific lease cleanup.
- `Kipless/Services/PrivilegedHelperClient.swift` — `SMAppService` registration and typed XPC client facade.
- `Kipless/Services/LidAwakeManager.swift` — app-facing observable state and operation serialization.
- `Kipless/Resources/LaunchDaemons/com.kaoru.kipless.sleep-helper.plist` — embedded LaunchDaemon definition.

Modify:

- `project.yml` — shared sources, helper target, app embedding, LaunchDaemon plist copy phase, and target dependency.
- `Kipless.xcodeproj/project.pbxproj` — regenerate from `project.yml`; do not hand-edit generated structure.
- `Kipless/KiplessApp.swift` — inject the singleton `LidAwakeManager`.
- `Kipless/AppDelegate.swift` — release the lid lease during normal termination.
- `Kipless/Views/KiplessPopoverView.swift` — add the minimal Toggle while preserving existing mode/duration locking and layout.
- `Kipless/Localization/KiplessStrings.swift` — semantic localization keys with English fallback text.
- `Kipless/Resources/Localizable.xcstrings` — add the new user-visible strings.
- `KiplessTests/` — controller, manager, protocol/client fakes, and opt-in real-helper integration tests.
- `scripts/test-integration.sh` — include the opt-in helper/XPC integration path without running it in Fast CI.
- `docs/testing-plan.md` — document the new test commands, release blockers, and manual closed-lid test.

## Task 1: Define shared state and fixed driver seam

**Files:**

- Create: `Kipless/Shared/SleepOverrideModels.swift`
- Create: `Kipless/Shared/KiplessSleepHelperProtocol.swift`
- Create: `Kipless/Services/PMSetSleepOverrideDriver.swift`
- Create: `KiplessTests/SleepOverrideSystemStateTests.swift`
- Create: `KiplessTests/PMSetSleepOverrideDriverTests.swift`
- Modify: `project.yml`

**Interfaces:**

- `SleepOverrideSystemState: Int, Codable, Sendable` with `.disabled`, `.enabled`, and `.unknown`.
- `SleepOverrideOwnership: Equatable, Sendable` with `baselineWasDisabled: Bool` and `modifiedByKipless: Bool`.
- `SleepOverrideDriving` with `readState() throws -> Bool`, `enable() throws`, and `disable() throws`.
- `SleepOverrideStateParser.parse(_:) -> SleepOverrideSystemState`.
- `KiplessSleepHelperProtocol` exposes only the three callback methods required by the plan.
- `PMSetSleepOverrideDriver` conforms to `SleepOverrideDriving` and internally owns a fixed operation runner; callers cannot provide a command or arguments.

- [ ] **Step 1: Add parser tests for all three state outcomes.**

  Test exact `pmset -g` fragments containing `SleepDisabled 0` and `SleepDisabled 1`, plus missing, malformed, and conflicting values. The parser must return `.unknown` for every non-unambiguous input.

  ```swift
  func testParsesSleepDisabledZero() {
      XCTAssertEqual(
          SleepOverrideStateParser.parse("System-wide power settings:\\n SleepDisabled 0\\n"),
          .disabled
      )
  }

  func testParsesSleepDisabledOne() {
      XCTAssertEqual(
          SleepOverrideStateParser.parse("System-wide power settings:\\n SleepDisabled 1\\n"),
          .enabled
      )
  }

  func testMalformedOutputIsUnknown() {
      XCTAssertEqual(SleepOverrideStateParser.parse("SleepDisabled yes"), .unknown)
      XCTAssertEqual(SleepOverrideStateParser.parse(""), .unknown)
  }
  ```

- [ ] **Step 2: Run the parser tests and verify they fail for missing types or behavior.**

  Run:

  ```bash
  xcodebuild test -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS' -only-testing:KiplessTests/SleepOverrideSystemStateTests
  ```

  Expected: compile/test failure because the new parser and state types do not exist yet.

- [ ] **Step 3: Implement the shared state model and strict parser.**

  Use a single unambiguous `SleepDisabled` match. Reject values other than exactly `0` or `1`; do not infer state from command exit status or unrelated `pmset` output.

- [ ] **Step 4: Add driver tests around a fixed operation seam.**

  Inject a fake internal command runner that records an operation enum, not a string or argument list. Assert that `readState()` requests only `.readState`, `enable()` only `.enable`, and `disable()` only `.disable`; assert non-zero exit and unknown output become typed errors.

  ```swift
  enum FixedPMSetOperation: Equatable {
      case readState
      case enable
      case disable
  }

  func testEnableUsesOnlyFixedEnableOperation() throws {
      let runner = RecordingPMSetRunner(output: "SleepDisabled 1")
      let driver = PMSetSleepOverrideDriver(runner: runner)

      try driver.enable()

      XCTAssertEqual(runner.operations, [.enable])
  }
  ```

- [ ] **Step 5: Implement `PMSetSleepOverrideDriver`.**

  Run `/usr/bin/pmset` directly with these exact argument sets:

  ```text
  readState → -g
  enable    → -a disablesleep 1
  disable   → -a disablesleep 0
  ```

  Capture stdout/stderr, treat a non-zero exit as failure, parse state after every write, and expose no shell or arbitrary command API. Keep the recording runner initializer internal so production callers still see only `SleepOverrideDriving`.

- [ ] **Step 6: Run the focused tests and project validation.**

  Run:

  ```bash
  xcodegen generate
  xcodebuild test -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS' -only-testing:KiplessTests/SleepOverrideSystemStateTests -only-testing:KiplessTests/PMSetSleepOverrideDriverTests
  git diff --check
  ```

  Expected: focused tests pass, generated project includes the shared files, and the existing layout changes remain in the diff.

## Task 2: Implement baseline ownership and lease controller

**Files:**

- Create: `Kipless/Services/SleepOverrideController.swift`
- Create: `KiplessTests/SleepOverrideControllerTests.swift`

**Interfaces:**

- `SleepOverrideController(driver: any SleepOverrideDriving)`.
- `currentState() throws -> SleepOverrideSystemState`.
- `acquireOverride() throws`.
- `releaseOverride() throws`.
- `hasLease: Bool` and `ownership: SleepOverrideOwnership?`.

- [ ] **Step 1: Write failing tests for disabled baseline acquisition and release.**

  Start from `false`, acquire once, assert one enable operation, `hasLease == true`, `modifiedByKipless == true`, then release and assert one disable operation plus a final disabled read.

- [ ] **Step 2: Write failing tests for an already-enabled baseline.**

  Start from `true`, acquire and release, assert no enable and no disable operation, and assert the final state remains enabled.

- [ ] **Step 3: Write failing tests for idempotency and failures.**

  Cover repeated acquire/release, read failure, enable failure, disable failure, post-write verification returning the wrong state, and post-write verification becoming unknown. A failed acquire must not expose a lease; a failed release must retain enough state for a retry and must never claim that the baseline was restored.

- [ ] **Step 4: Run the controller tests and verify the expected failures.**

  Run:

  ```bash
  xcodebuild test -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS' -only-testing:KiplessTests/SleepOverrideControllerTests
  ```

- [ ] **Step 5: Implement the controller state machine.**

  Acquisition must:

  1. Return immediately for an existing lease.
  2. Read the current state.
  3. Record `baselineWasDisabled = true` and avoid writing when already enabled.
  4. Otherwise execute enable, read again, and require enabled.
  5. Set `modifiedByKipless = true` only after verification succeeds.

  If a write succeeds but verification fails, make a best-effort restore to the original disabled baseline, clear the lease, and throw the original typed error with cleanup information preserved in diagnostics.

  Release must write disabled and verify only when `modifiedByKipless == true`. For a pre-existing enabled baseline it must do nothing. Releasing without a lease is idempotent.

- [ ] **Step 6: Run controller tests and the existing XCTest suite.**

  ```bash
  xcodebuild test -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS' -only-testing:KiplessTests/SleepOverrideControllerTests
  xcodebuild test -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS'
  ```

## Task 3: Add the helper target and embedded LaunchDaemon packaging

**Files:**

- Create: `KiplessSleepHelper/main.swift`
- Create: `KiplessSleepHelper/SleepHelperService.swift`
- Create: `Kipless/Resources/LaunchDaemons/com.kaoru.kipless.sleep-helper.plist`
- Modify: `project.yml`
- Regenerate: `Kipless.xcodeproj/project.pbxproj`

**Interfaces:**

- Product target: `KiplessSleepHelper`, macOS command-line tool, bundle identifier `com.kaoru.kipless.sleep-helper`.
- The App target embeds the helper product at `Contents/Resources/KiplessSleepHelper`.
- The App target copies the plist to `Contents/Library/LaunchDaemons/com.kaoru.kipless.sleep-helper.plist`.
- The helper target includes shared protocol/model files and helper-only implementation files, but not the App UI or `WakeSessionManager`.

- [ ] **Step 1: Add the helper target and verify project generation fails only for missing files.**

  Add the target and `Kipless/Shared` source inclusion to `project.yml`. XcodeGen’s wrapper destination is the bundle root in this project, so add the helper with `Contents/Resources` as the subpath and the plist with `Contents/Library/LaunchDaemons` as the subpath.

  ```yaml
  dependencies:
    - target: KiplessSleepHelper
      embed: true
      copy:
        destination: wrapper
        subpath: Contents/Resources
  ```

  Run:

  ```bash
  xcodegen generate
  ```

  Expected: project generation succeeds after the referenced files are created; generated project shows the helper dependency and copy phase.

- [ ] **Step 2: Add a minimal LaunchDaemon plist with fixed identity and Mach service.**

  Use label `com.kaoru.kipless.sleep-helper`, `BundleProgram = Contents/Resources/KiplessSleepHelper`, and a matching relative `ProgramArguments` entry. Set `RunAtLoad = true`, `ProcessType = Background`, and one Mach service with the same label. Do not add shell commands, user-controlled arguments, or unrelated privileges. The final archive must contain the helper under `Contents/Resources` and the plist under `Contents/Library/LaunchDaemons`.

- [ ] **Step 3: Add the helper entry point and a build-only listener skeleton.**

  Start an `NSXPCListener` using the Mach service name and keep the process alive through the listener run loop. Export no methods until Task 4 supplies the protocol-backed service. This step only proves the target, bundle layout, and signing/build graph are valid.

- [ ] **Step 4: Build and inspect the embedded helper without launching the App.**

  ```bash
  xcodebuild build -quiet -project Kipless.xcodeproj -scheme KiplessSleepHelper -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
  xcodebuild build -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
  APP_PATH="$(xcodebuild -showBuildSettings -project Kipless.xcodeproj -scheme Kipless -configuration Debug | awk -F' = ' '/ TARGET_BUILD_DIR / {print $2; exit}')/Kipless.app"
  test -x "$APP_PATH/Contents/Resources/KiplessSleepHelper"
  test -f "$APP_PATH/Contents/Library/LaunchDaemons/com.kaoru.kipless.sleep-helper.plist"
  plutil -lint "$APP_PATH/Contents/Library/LaunchDaemons/com.kaoru.kipless.sleep-helper.plist"
  ```

## Task 4: Implement XPC helper service and typed client

**Files:**

- Modify: `Kipless/Shared/KiplessSleepHelperProtocol.swift`
- Modify: `KiplessSleepHelper/SleepHelperService.swift`
- Modify: `KiplessSleepHelper/main.swift`
- Create: `Kipless/Services/PrivilegedHelperClient.swift`
- Create: `KiplessTests/PrivilegedHelperClientTests.swift`

**Interfaces:**

- XPC protocol remains limited to:

  ```swift
  @objc protocol KiplessSleepHelperProtocol {
      func getState(withReply reply: @escaping (Int, String?) -> Void)
      func acquireSleepOverride(withReply reply: @escaping (Bool, String?) -> Void)
      func releaseSleepOverride(withReply reply: @escaping (Bool, String?) -> Void)
  }
  ```

- `PrivilegedHelperClient` exposes typed app-facing methods:

  ```swift
  func connect() throws
  func getSleepOverrideState() async throws -> SleepOverrideSystemState
  func enableSleepOverride() async throws
  func disableSleepOverride() async throws
  func invalidate()
  ```

- [ ] **Step 1: Add client tests with a fake XPC proxy.**

  Assert typed conversion of disabled/enabled/unknown state codes, helper error conversion, connection invalidation behavior, and that the client has no method accepting a command or arguments. Keep the fake at the protocol seam; do not test through private `NSXPCConnection` internals.

- [ ] **Step 2: Run the client tests and verify they fail before implementation.**

  ```bash
  xcodebuild test -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS' -only-testing:KiplessTests/PrivilegedHelperClientTests
  ```

- [ ] **Step 3: Implement the helper service around one shared controller.**

  The helper process owns one `SleepOverrideController`. Each accepted XPC connection receives a service object tied to that connection. `acquireSleepOverride` and `releaseSleepOverride` call the controller; `getState` returns the real parsed state. Encode unknown as the shared state code and return a non-empty error message when an operation cannot be verified.

- [ ] **Step 4: Add connection invalidation cleanup.**

  On each accepted connection, install an invalidation/interruption handler that calls `releaseOverride()` for that connection’s lease. Cleanup must be idempotent. Since the first version supports one Kipless client, a second connection must not create a second independent lease or overwrite the first baseline.

- [ ] **Step 5: Implement `SMAppService` registration and XPC connection.**

  Use `SMAppService.daemon(plistName: "com.kaoru.kipless.sleep-helper.plist")`. Register only when necessary, establish `NSXPCConnection(machServiceName:)`, set the remote object interface to `KiplessSleepHelperProtocol`, and map connection errors to typed client errors. Do not add a custom authorization dialog; macOS/system settings owns approval.

- [ ] **Step 6: Run build and focused tests.**

  ```bash
  xcodegen generate
  xcodebuild test -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS' -only-testing:KiplessTests/PrivilegedHelperClientTests
  xcodebuild build -quiet -project Kipless.xcodeproj -scheme KiplessSleepHelper -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
  xcodebuild build -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
  ```

## Task 5: Add `LidAwakeManager` and app lifecycle cleanup

**Files:**

- Create: `Kipless/Services/LidAwakeManager.swift`
- Create: `KiplessTests/LidAwakeManagerTests.swift`
- Modify: `Kipless/AppDelegate.swift`
- Modify: `Kipless/KiplessApp.swift`

**Interfaces:**

```swift
@MainActor
@Observable
final class LidAwakeManager {
    static let shared = LidAwakeManager()

    private(set) var isEnabled = false
    private(set) var isAvailable = false
    private(set) var errorMessage: String?

    func refresh()
    func enable()
    func disable()
}
```

- [ ] **Step 1: Write manager tests with a fake typed helper client.**

  Cover initial disabled state, successful enable, failed enable rollback, successful disable, failed disable preserving the correct state, refresh synchronization, unavailable helper state, and serialization of repeated enable/disable requests.

- [ ] **Step 2: Run the manager tests and verify failure.**

  ```bash
  xcodebuild test -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS' -only-testing:KiplessTests/LidAwakeManagerTests
  ```

- [ ] **Step 3: Implement the manager as the only App-side lid state source.**

  Keep the manager `@MainActor`. Public methods start serialized asynchronous work internally, set `isEnabled` only after helper confirmation, clear errors after a successful operation, and set `isAvailable` from connection/refresh results. A failed enable always leaves `isEnabled == false`; a failed disable does not claim that the system is restored.

- [ ] **Step 4: Wire normal termination without making termination depend on an unbounded wait.**

  Add a bounded cleanup path in `AppDelegate`: on normal termination, request lease release and wait only for the XPC reply needed to confirm cleanup; if the process is killed, helper connection invalidation remains the fallback. Do not block the app indefinitely on a hung helper; log the failure and let the helper’s invalidation path perform cleanup.

- [ ] **Step 5: Inject the singleton into the SwiftUI environment.**

  Keep `WakeSessionManager.shared` as the existing session source and add `LidAwakeManager.shared` as a separate environment object. Do not create an `AppState` wrapper or move existing session state.

- [ ] **Step 6: Run all unit tests and build targets.**

  ```bash
  xcodebuild test -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS'
  xcodebuild build -quiet -project Kipless.xcodeproj -scheme KiplessSleepHelper -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
  ```

## Task 6: Add the minimal localized Toggle without changing the existing layout

**Files:**

- Modify: `Kipless/Views/KiplessPopoverView.swift`
- Modify: `Kipless/Localization/KiplessStrings.swift`
- Modify: `Kipless/Resources/Localizable.xcstrings`
- Modify: `KiplessTests/LocalizationTests.swift`
- Modify: `KiplessTests/KiplessLayoutTests.swift` only if a measured layout contract needs a new assertion

- [ ] **Step 1: Add localization tests for semantic keys and English fallback.**

  Add a key such as `options.stayAwakeWithLidClosed.title` with fallback `Stay awake with lid closed`. Assert the Swift source references the semantic key, not a raw English key, and the String Catalog contains the English fallback.

- [ ] **Step 2: Run the localization tests and verify the new key is absent.**

  ```bash
  xcodebuild test -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS' -only-testing:KiplessTests/LocalizationTests
  ```

- [ ] **Step 3: Add the Toggle to the existing options panel.**

  Render one concise row using `LidAwakeManager`. Bind the visual state to `isEnabled`, invoke `enable()`/`disable()` from the Toggle action, and show the existing error presentation if the helper rejects the operation. Keep the Toggle disabled when the manager is unavailable or while the existing Session configuration lock is active; do not introduce a new card, onboarding surface, warning sheet, or layout redesign.

- [ ] **Step 4: Preserve and verify the current panel geometry.**

  Do not reintroduce the removed center divider or change the 180pt left / 204pt right split. If the new row requires vertical budget, reduce only local row spacing or helper text within the right panel; never compress the left panel or alter finite/indefinite visual modes.

- [ ] **Step 5: Run unit tests, String Catalog validation, and a non-launching build.**

  ```bash
  xcodebuild test -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS'
  python3 -m json.tool Kipless/Resources/Localizable.xcstrings >/dev/null
  xcodebuild build -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
  ```

## Task 7: Add opt-in real XPC/integration coverage

**Files:**

- Create: `KiplessTests/LidAwakeIntegrationTests.swift`
- Modify: `scripts/test-integration.sh`
- Modify: `docs/testing-plan.md`

- [ ] **Step 1: Add integration tests guarded by an explicit environment variable.**

  The real tests must skip unless `KIPLESS_RUN_LID_AWAKE_INTEGRATION=1` is present, so Fast CI never changes the developer machine’s power policy. Before each test, read and record the baseline; after each test, restore it and assert the final state.

- [ ] **Step 2: Cover the real helper/XPC scenarios.**

  Implement these cases through the real `PrivilegedHelperClient` and embedded LaunchDaemon:

  ```text
  baseline disabled → acquire → state enabled → release → state disabled
  baseline enabled  → acquire → release → state remains enabled
  acquire → acquire → release → release → baseline restored
  acquire → invalidate the client connection → baseline restored
  ```

  Any test that cannot prove baseline restoration must fail and attempt cleanup before reporting the failure.

- [ ] **Step 3: Add the integration command without making CI run it.**

  Extend `scripts/test-integration.sh` with an explicit opt-in branch:

  ```bash
  KIPLESS_RUN_LID_AWAKE_INTEGRATION=1 \
    xcodebuild test -project Kipless.xcodeproj -scheme Kipless \
    -destination 'platform=macOS' \
    -only-testing:KiplessTests/LidAwakeIntegrationTests
  ```

  The script must refuse to run this branch without the environment variable and must print that it can modify `SleepDisabled` temporarily.

- [ ] **Step 4: Run the non-power integration checks.**

  ```bash
  bash -n scripts/*.sh
  ./scripts/test-integration.sh
  ```

  Expected: existing IOKit integration tests pass; lid integration tests remain skipped unless explicitly opted in.

## Task 8: Add release/build guards and manual hardware verification documentation

**Files:**

- Modify: `.github/workflows/ci.yml` if needed for the target name/build graph
- Modify: `scripts/preflight.sh` if needed for helper packaging checks
- Modify: `docs/testing-plan.md`
- Modify: `README.md` or `CHANGELOG.md` only when the feature is ready for a new release, not as part of the unreleased implementation checkpoint

- [ ] **Step 1: Add cheap CI checks for the new target and scripts.**

  CI must build the helper target without signing and validate every shell script:

  ```bash
  xcodebuild build -scheme KiplessSleepHelper -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
  bash -n scripts/*.sh
  ```

  Fast CI must not run real `pmset -a disablesleep` operations.

- [ ] **Step 2: Add archive assertions.**

  For a Release archive, assert that:

  ```text
  Kipless.app/Contents/Resources/KiplessSleepHelper exists and is executable
  Kipless.app/Contents/Library/LaunchDaemons/com.kaoru.kipless.sleep-helper.plist exists
  plist label and Mach service equal com.kaoru.kipless.sleep-helper
  no helper source or arbitrary command tool is copied into the App’s user-visible resources
  ```

  Keep the existing universal binary, bundle identifier, hardened runtime, and signing checks intact.

- [ ] **Step 3: Document the only manual hardware test.**

  Record this sequence in `docs/testing-plan.md`:

  ```text
  1. Confirm the current baseline and connect the Mac to power.
  2. Start a long-running task.
  3. Enable Stay awake with lid closed.
  4. Close the lid for 3–5 minutes.
  5. Reopen the lid and verify the task continued.
  6. Disable the Toggle and confirm the baseline is restored.
  7. Close the lid again and verify normal sleep behavior returns.
  ```

  Also document that this feature intentionally does not implement battery, thermal, charger, closed-lid detection, or reboot recovery policies.

- [ ] **Step 4: Run archive/build checks without launching the App.**

  ```bash
  xcodebuild archive -quiet -project Kipless.xcodeproj -scheme Kipless \
    -configuration Release -archivePath /tmp/Kipless-closed-lid.xcarchive \
    CODE_SIGNING_ALLOWED=NO
  test -x /tmp/Kipless-closed-lid.xcarchive/Products/Applications/Kipless.app/Contents/Resources/KiplessSleepHelper
  test -f /tmp/Kipless-closed-lid.xcarchive/Products/Applications/Kipless.app/Contents/Library/LaunchDaemons/com.kaoru.kipless.sleep-helper.plist
  ```

## Task 9: Final verification and handoff

- [ ] **Step 1: Run the complete non-destructive verification suite.**

  ```bash
  xcodegen generate
  xcodebuild test -quiet -project Kipless.xcodeproj -scheme Kipless -destination 'platform=macOS'
  xcodebuild build -quiet -project Kipless.xcodeproj -scheme KiplessSleepHelper -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
  bash -n scripts/*.sh
  python3 -m json.tool Kipless/Resources/Localizable.xcstrings >/dev/null
  git diff --check
  ```

- [ ] **Step 2: Inspect the final diff and working tree.**

  Confirm that the existing 384pt layout work is still present, no HTML prototype was changed, no secret or authorization material was added, and no App launch command was run.

- [ ] **Step 3: Run the real lid integration tests only when explicitly authorized for the local Mac.**

  ```bash
  KIPLESS_RUN_LID_AWAKE_INTEGRATION=1 ./scripts/test-integration.sh
  ```

  Confirm that the final `SleepDisabled` value equals the baseline before the test suite exits.

- [ ] **Step 4: Report remaining manual work.**

  Report unit/build status, whether real helper integration was run, whether physical closed-lid verification remains, and the exact files changed. Do not claim the feature is release-ready until the physical test and a signed/notarized archive have passed.

## Plan Self-Review

- The plan covers the user-provided phases: driver/state parsing, ownership controller, helper target, `SMAppService`, XPC, `LidAwakeManager`, minimal UI, lifecycle cleanup, unit tests, integration tests, and manual closed-lid verification.
- No task introduces a third `WakeMode`, automatic Session coupling, arbitrary root command execution, or unrequested safety/onboarding UX.
- All public module seams are typed and narrow; tests cross the same interfaces used by production callers.
- The plan keeps the existing uncommitted layout changes in scope as preserved state, not as a redesign target.
- The only intentionally local/manual step is real hardware power behavior; Fast CI remains non-destructive.
