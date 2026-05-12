# Retro: 2026-05-10 22:40
Session: 8ed8212b-c428-473e-a5e9-e9b8a74696bb
Topic: multi-overlay-pip-sessions
Branch: main
CWD: /Users/zolat/projects/PiPanything
Duration: ~2h
Key files: PiPanything/Sources/App/{OverlaySession,OverlayCoordinator,AppDelegate}.swift, PiPanything/Sources/Picker/SourcePickerMenu.swift, ROADMAP.md, ~/.claude/plans/serialized-finding-meadow.md

## Context
Planned and implemented multi-overlay support for PiPanything (a single-PiP app) end-to-end in a worktree. Plan-mode produced a phased plan; advisor review caught three blind spots before exit; implementation extracted `OverlaySession` + `OverlayCoordinator`, restructured the picker menu, and shipped per-overlay right-click menus. Verified via env-var-driven smoke runs (PIP_AUTO_CAPTURE_COUNT=3/5) and a synthesized Stop dispatch.

## Learnings
- SCStream allows N concurrent streams on the same SCWindow — empirically verified, no exclusion. Removed a whole branch of "what if start fails" picker logic.
- `NSMenu.identifier` is the right place to stash routing metadata for `menuNeedsUpdate` — `representedObject` doesn't exist on NSMenu (only NSMenuItem). Cost me one build cycle.

## Mental model corrections
- I assumed `OverlayWindow` set an autosave name and would collide; reading the file directly disproved that. Lesson: confirm "facts" from explorer summaries before letting them shape the plan.
- I treated `[weak self]` inside `OverlaySession.close()` as harmless because that's the AppDelegate idiom — but OverlaySession is no longer a singleton, so `self` deallocs before the Task runs and the SCStream leaks. The advisor caught it; I would not have.

## Conventions and decisions
- Single `@objc handleOverlayMenu(_:)` selector + `OverlayMenuTag` payload via `representedObject` beats minting one selector per (session × action). Scales cleanly.
- Stop is asymmetric *by design*: closes siblings, returns the only-remaining session to idle (preserves the right-click entry point since there's no NSStatusItem). Documented inline + in the report.

## What would have helped at the start
- A note in CLAUDE.md that `xcodebuild` is the source of truth and SourceKit's "Cannot find type" diagnostics are stale-index noise post-`xcodegen generate`. I learned to ignore them, but it took ~3 cycles of doubt.

## Capability gaps
- Gap: couldn't programmatically click a status-bar/right-click menu item to verify dispatch interactively.
  - Workaround: added `PIP_TEST_STOP_INDEX=k` env hook that synthesizes the same menu item the user would click, invokes `handleOverlayMenu` directly, logs pre/post coordinator state.
  - Suggested unblock: a tiny "menu-driver" helper (AppleScript or `cliclick` wrapper) that opens the status menu and clicks an item by title — would also unblock auto-hide and source-quit live verification.

## Processed: 2026-05-10

### Actions taken
- Added gotcha #8 to `CLAUDE.md`: `xcodebuild` is the source of truth, ignore stale SourceKit/LSP "Cannot find type" diagnostics after `xcodegen generate`. Targets the explicit "What would have helped at the start" ask.
- Added new high-priority track **"Menu-driver helper for end-to-end verification"** to `BACKLOG.md` (parallel-fitness summary + full track entry). Captures the capability gap so the next session that needs end-to-end menu verification can pick it up rather than minting another `PIP_TEST_*` env hook.

### Items discussed but not acted on
- The `OverlaySession.close()` `[weak self]` SCStream-leak lesson — already in the code as fixed and the more general lesson ("singleton-era idioms don't survive de-singleton-ing") is too narrow to merit a CLAUDE.md slot.
- The `NSMenu.identifier` vs `representedObject` correction — project-specific code knowledge that's now embodied in the codebase; no separate note needed.
- Stale `BACKLOG.md` entry: "Multiple simultaneous overlays" is still listed as ⛔ blocked but actually shipped in commit `74b70ec` (this very session). Worth cleaning up but out of scope for this retro — flagged as a follow-up.
