# Retro: 2026-05-11 00:10
Session: 93cf494b-25db-4168-beb4-91ac7ea1945d
Topic: pipanything-status-bar-menu
Branch: main
CWD: /Users/zolat/projects/PiPanything
Duration: ~50 min
Key files: PiPanything/Sources/Features/StatusBarController.swift, PiPanything/Sources/Features/Settings.swift, PiPanything/Sources/Picker/SourcePickerMenu.swift, PiPanything/Sources/App/AppDelegate.swift

## Context
Added a macOS status-bar (top-bar) surface to PiPanything: an `NSStatusItem`, an inline settings block (default opacity, auto-hide default, launch-at-login), and a "Pick window…" entry that reuses the existing picker. No persisted-settings layer existed before, so this also introduced a small `Settings` singleton over `UserDefaults` plus `SMAppService` for login-item registration.

## Learnings
- `populate()` in `SourcePickerMenu` was already shaped right for full-tree reuse — the only change needed was an optional trailing `extraSection:` closure. Cheaper than a parallel builder.
- For an `LSUIElement` app, AX exposes the status item under `menu bar 1`, not `menu bar 2`. Saved a wrong assumption mid-verification.
- `xcodebuild -showBuildSettings | awk '/BUILT_PRODUCTS_DIR/'` is fragile because other settings (`COMMAND_MODE = YES`, etc.) leak into `$3`. Anchored the regex to `^[[:space:]]+BUILT_PRODUCTS_DIR = ` instead.

## Conventions and decisions
- Status-menu settings are *defaults*, not global toggles — changing them does not retroactively touch live overlays. Implemented via a one-shot `applyDefaults(to:)` on session creation.
- `Settings.launchAtLogin` reads `SMAppService.mainApp.status` directly rather than caching a UserDefaults bool, so the checkmark can't lie when registration silently fails on ad-hoc-signed builds.

## What would have helped at the start
- Knowing CLAUDE.md already documented the SourceKit-stale-after-xcodegen pitfall — would have skipped the reflex to investigate the diagnostic noise. (It does; I just needed to read it sooner.)

## Capability gaps
- Gap: couldn't safely toggle "Launch at login" end-to-end — it modifies the user's system Login Items, and ad-hoc signing makes registration flaky anyway.
  - Workaround: verified the action wiring is identical to the auto-hide toggle (which I did exercise) and that the getter reflects truth.
  - Suggested unblock: Developer-ID signing + notarization (already in BACKLOG.md) would make `SMAppService` register reliably and the toggle safe to flip in a verification harness.

## Processed: 2026-05-11

### Actions taken
- Fixed the fragile `awk` line in project `CLAUDE.md`'s build snippet (`/BUILT_PRODUCTS_DIR/ {print $3}` → anchored to `^[[:space:]]+BUILT_PRODUCTS_DIR = `).

### Items discussed but not acted on
- "Launch at login" verification gap — already covered by the existing BACKLOG "Developer-ID signing + notarization" track.
- AX `menu bar 1` vs `menu bar 2` for LSUIElement — too low-frequency to formalize; left in the retro as evidence for next time.
