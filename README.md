# Kipless

Kipless is a lightweight macOS utility for controlling system and display sleep.

Sometimes you need your Mac to stay awake — a long download, a build, a render,
a server you are running locally — without permanently changing how your Mac
sleeps. Kipless sits in the menu bar and holds that state only for as long as
you ask it to.

## Features

- **Let the screen turn off** — keeps your Mac working while the display may
  turn off on its own schedule, so a long download can finish with the screen
  dark.
- **Keep the screen on** — keeps both the Mac and display awake for dashboards,
  reference material, reading and presentations.
- **Timed wake sessions** — 15 minutes, 30 minutes, 1 hour, 2 hours, or
  indefinitely.
- **Lightweight menu bar interface** — no Dock icon, no main window, no
  onboarding.
- **Fully offline** — no account, no network, no telemetry.

## What Kipless does not do

Kipless does not replace your Mac's power management, and it deliberately stays
out of the way when you ask the machine to sleep:

- It does not keep your Mac running with the lid closed.
- It does not block sleep you start yourself (Apple menu › Sleep, or
  `pmset sleepnow`).
- It does not change your permanent power settings, and never touches `pmset`.
- It does not need administrator rights.

Stopping a session, or quitting Kipless, releases everything immediately.

## Requirements

macOS 14 (Sonoma) or later.

## Installation

Download `Kipless.dmg` from the [latest release][releases], open it, and
drag Kipless to Applications. Builds are signed with a Developer ID and
notarized by Apple, so they open without a Gatekeeper warning.

[releases]: https://github.com/ShiinaLabs/Kipless/releases/latest

## Build

```sh
git clone https://github.com/ShiinaLabs/Kipless.git
cd Kipless
open Kipless.xcodeproj
```

Then build and run the `Kipless` scheme. On first launch a bolt appears in the
menu bar.

`Kipless.xcodeproj` is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and checked in, so you only
need XcodeGen if you change the project structure:

```sh
brew install xcodegen
xcodegen generate
```

Run the tests with `⌘U` in Xcode, or:

```sh
xcodebuild -project Kipless.xcodeproj -scheme Kipless test
```

### Automated testing

The repository provides three test layers:

```sh
# Fast deterministic unit tests (the CI equivalent)
xcodebuild test -project Kipless.xcodeproj -scheme Kipless -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# Local integration run against real macOS power assertions
./scripts/test-integration.sh

# Release gate: tests, Release build, real power assertions, app smoke test,
# bundle metadata, signature, and final assertion leak check
./scripts/preflight.sh
```

The integration and preflight scripts run on a local Mac because they inspect
real IOKit power assertions with `pmset`. They do not wait for real sleep or
long session durations. The test helper is a separate executable and is never
packaged into `Kipless.app`.

The app icon is generated from `scripts/make-icon.py` into the asset catalog:

```sh
python3 scripts/make-icon.py
```

User-facing copy uses semantic localization keys with English fallback values.
The String Catalog lives at `Kipless/Resources/Localizable.xcstrings`; add
future languages there without changing the sleep-control implementation.

## Privacy

Kipless makes no network connections. There is no account, no analytics, no
telemetry, no crash reporting and no update check. Nothing about you, your Mac
or how you use the app leaves the machine — there is nowhere for it to go.

## License

[Mozilla Public License 2.0](LICENSE).
