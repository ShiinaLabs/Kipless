# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0]

### Added

- Keep System Awake and Keep Display Awake modes, backed by IOKit power
  assertions.
- Timed wake sessions of 15 minutes, 30 minutes, 1 hour and 2 hours, plus an
  indefinite session.
- Menu bar interface with a popover for starting and stopping sessions and
  showing the time remaining.
- Launch at Login, via `SMAppService`.
- Menu bar icon that distinguishes active from inactive.

[Unreleased]: https://github.com/ShiinaLabs/Kipless/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ShiinaLabs/Kipless/releases/tag/v1.0.0
