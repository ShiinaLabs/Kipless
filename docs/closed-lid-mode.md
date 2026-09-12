# Kipless — Closed Lid Mode

Closed Lid is the third mutually exclusive `WakeMode` in Kipless. It is not a
standalone toggle or a modifier that can outlive a wake Session.

| Mode | Idle system sleep | Display sleep | Lid-close sleep |
| --- | --- | --- | --- |
| `System` | Prevented | Allowed | Allowed |
| `Display` | Prevented | Prevented | Allowed |
| `Closed Lid` | Prevented | Allowed | Prevented |

## Session lifecycle

Every mode uses the same duration, Start, Stop, timeout, and termination
lifecycle. `Closed Lid` starts in two steps:

1. Acquire the normal `PreventUserIdleSystemSleep` assertion.
2. Acquire the helper-owned `SleepDisabled` lease.

The Session is marked active only after both resources succeed. If the helper
step fails, the assertion is released and the Session remains idle.

Stop, timeout, replacement, quit, and partial-start rollback release the
Closed Lid lease and the IOKit assertion through the same manager. Helper
release is serialized as a transition so a new Session cannot race a previous
lease cleanup.

## Privileged boundary

`PrivilegedHelperClient` is the app-side `LidSleepOverrideClient`. The embedded
`KiplessSleepHelper` LaunchDaemon owns the lease and uses the existing
`SleepOverrideController` to preserve the pre-existing `SleepDisabled` state.
It exposes only state, acquire, and release operations over XPC; it does not
accept arbitrary commands or shell arguments.

## UI

The mode picker presents exactly three choices:

```text
System
Keep Mac awake. Display may turn off.

Display
Keep Mac and display awake.

Closed Lid
Keep Mac awake when the lid is closed.
```

Mode and duration remain locked for the entire Running/transition state. The
existing finite ring and indefinite `∞` presentation are unchanged.

## Verification boundary

The user has already verified the core sleep behavior on the target Mac. This
change keeps the existing helper/unit infrastructure buildable, but does not
expand the new feature with another test suite or claim that a real closed-lid
hardware run was performed here.
