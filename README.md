# Kipless

A lightweight macOS menu bar utility for controlling system and display sleep.

Sometimes you need your Mac to stay awake — a long download, a build, a render,
a server you are running locally — without changing how your Mac sleeps for
good. Kipless sits in the menu bar, holds that state for exactly as long as you
ask, and gets out of the way.

## Wake modes

| Mode | What stays awake |
| --- | --- |
| **System** | The Mac. The display may still turn off on its own schedule. |
| **Display** | The Mac and the display — for dashboards, reading, presentations. |
| **Closed Lid** | The Mac, even with the lid shut. |

Sessions run for 15 minutes, 30 minutes, 1 hour, 2 hours, or until you stop
them. Quitting Kipless ends the session too.

## Install

Download `Kipless.dmg` from the [latest release][releases], open it, and drag
Kipless to Applications. Builds are signed with a Developer ID and notarized by
Apple.

[releases]: https://github.com/ShiinaLabs/Kipless/releases/latest

## Closed Lid needs your approval

Keeping the Mac awake with the lid shut is a system setting, so macOS only lets
a background helper change it with your consent. The first time you start a
Closed Lid session, Kipless asks you to allow it under System Settings ›
General › Login Items. The helper accepts no commands beyond the three fixed
`pmset` operations that mode needs, and the setting is restored when the session
ends.

Outside a session Kipless changes nothing about how your Mac sleeps.

## Requirements

macOS 14 (Sonoma) or later. Localized in English, 简体中文, 繁體中文, 日本語,
한국어, Deutsch, Français, Español, Italiano and Português (Brasil).

## Privacy

No account, no analytics, no telemetry, no crash reporting, no update check, and
no network connections. Nothing about you or your Mac leaves the machine.

## Development

The native `Kipless.xcodeproj` is the single source of truth — make project
changes in Xcode so the checked-in project stays that way.

```sh
xcodebuild -project Kipless.xcodeproj -scheme Kipless test
```

Two scripts cover what unit tests cannot. `./scripts/test-integration.sh` checks
the real IOKit power assertions, and `./scripts/preflight.sh` is the release
gate: tests, Release build, assertions, app smoke test, bundle metadata and
signature checks. Both run on a Mac, and the closed-lid integration tests use
the signed helper.

User-facing copy lives in the String Catalog at
`Kipless/Resources/Localizable.xcstrings`.

## License

[Mozilla Public License 2.0](LICENSE).
