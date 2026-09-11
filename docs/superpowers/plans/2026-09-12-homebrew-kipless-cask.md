# Homebrew Kipless Cask Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Kipless to the `ShiinaLabs/apps` Homebrew tap and automatically open updates when a new stable Kipless GitHub Release is published.

**Architecture:** Add a native `kipless` Cask that downloads the stable `Kipless.dmg` asset from the Kipless GitHub Release. Keep WiFi Lens unchanged; add a separate scheduled/manual updater workflow that follows the existing tap pattern: resolve a stable Release, download the DMG, calculate SHA-256, update the Cask, and open an update PR.

**Tech Stack:** Homebrew Cask Ruby DSL, Bash, GitHub Actions, GitHub CLI, `jq`, `curl`, `shasum`.

**Spec:** Current user request: add Kipless to the ShiinaLabs private Homebrew tap and make the tap update automatically like WiFi Lens.

## Global Constraints

- Use the existing tap name `ShiinaLabs/apps` and repository `ShiinaLabs/homebrew-apps`.
- Use the fixed Release asset name `Kipless.dmg`; do not put a version in the DMG filename.
- Use stable SemVer tags only (`vX.Y.Z`); do not update from drafts or prereleases.
- Do not modify the WiFi Lens application repository or its existing updater script/workflow.
- Do not add Sparkle or mark Kipless as `auto_updates true`; Kipless has no in-app updater.
- Do not store tokens, passwords, or other secrets in the repository or knowledge base.

---

### Task 1: Add the Kipless Cask and release resolver

**Files:**
- Create: `/Users/kaoru/Developer/homebrew-apps/Casks/kipless.rb`
- Create: `/Users/kaoru/Developer/homebrew-apps/scripts/update-kipless-cask.sh`

**Interfaces:**
- The Cask exposes `ShiinaLabs/apps/kipless` and installs `Kipless.app` from `https://github.com/ShiinaLabs/Kipless/releases/download/v#{version}/Kipless.dmg`.
- The updater accepts an optional tag argument; without it, it reads the latest stable Kipless Release; it updates exactly one `version` and one `sha256` stanza.

- [x] Create `kipless.rb` with version `1.0.0`, the verified SHA-256 for the current `Kipless.dmg`, the GitHub download URL, macOS Sonoma dependency, and `app "Kipless.app"`.
- [x] Create the updater by adapting the existing tap validation flow to `ShiinaLabs/Kipless` and the `Kipless.dmg` asset, including stable tag and published-release checks.
- [x] Run `bash -n scripts/update-kipless-cask.sh` and `scripts/update-kipless-cask.sh v1.0.0`; verify the generated checksum matches the published asset and the Cask diff is empty after the first update.
- [x] Run `brew audit --cask --strict --online --tap ShiinaLabs/apps` and `brew style --cask ShiinaLabs/apps/kipless` after registering the local tap.

### Task 2: Add automatic updates and audit coverage

**Files:**
- Create: `/Users/kaoru/Developer/homebrew-apps/.github/workflows/update-kipless-cask.yml`
- Modify: `/Users/kaoru/Developer/homebrew-apps/.github/workflows/audit.yml`
- Modify: `/Users/kaoru/Developer/homebrew-apps/README.md`

**Interfaces:**
- The updater workflow runs every six hours and supports manual `tag` input; it opens one PR per Kipless version using a deterministic branch name.
- The audit workflow validates both `wifi-lens` and `kipless` without changing either Cask.

- [x] Add the scheduled/manual workflow with `contents: write`, `pull-requests: write`, local tap registration, updater invocation, change detection, and idempotent PR creation.
- [x] Extend audit to run strict online audit and style checks for `ShiinaLabs/apps/kipless`.
- [x] Document install and upgrade commands for Kipless using `brew tap ShiinaLabs/apps` and `brew install --cask ShiinaLabs/apps/kipless`.
- [x] Run `actionlint` against all tap workflows and `git diff --check`.

### Task 3: Publish the tap change and record the integration

**Files:**
- Modify: `/Users/kaoru/Documents/Obsidian Vault/ShiinaLabs/Kipless 索引.md`
- Modify: `/Users/kaoru/Documents/Obsidian Vault/技术/Git与部署/Mac App 发布手册.md`

- [x] Review the tap diff, confirm only the intended Homebrew repository files changed, and verify the Kipless repository remains unchanged.
- [x] Commit the tap changes with an imperative message and push `ShiinaLabs/homebrew-apps` `main`.
- [x] Record the tap name, Cask name, fixed DMG filename, updater workflow, and any remaining manual verification in the Kipless knowledge note without recording secrets.
- [x] Recheck the tap repository is clean and report the tap install command plus the automation behavior.
