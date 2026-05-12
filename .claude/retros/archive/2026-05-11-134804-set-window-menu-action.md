# Retro: 2026-05-11 13:48
Session: 9bdc373f-8f1a-4a83-ad87-65844d39ea7f
Topic: set-window-menu-action
Branch: feat/set-window
CWD: /Users/zolat/projects/PiPanything-set-window
Duration: ~45m
Key files: PiPanything/Sources/App/OverlaySession.swift, PiPanything/Sources/Picker/SourcePickerMenu.swift, PiPanything/Sources/App/AppDelegate.swift

## Context
Added a **Set window…** right-click action that swaps the active tab's source in place — no new tab, no new overlay. Plan mode first (one Explore agent, one clarifying question), then implement-in-worktree. Net +53 / -1 across three files.

## Learnings
- `CaptureManager.start(window:)` already calls `await stop()` at the top — calling `OverlayTab.start` on a live capturing tab is already a clean swap, no new sequencing primitive needed. Spotted on the second read of CaptureManager.swift; the in-Plan-phase advisor call wasn't needed because the existing code paths composed cleanly.
- The `PIP_TEST_*` env-hook convention in `autoCaptureLargest` is the right way to verify menu-dispatch features without a real picker click. Adding one for the new path took ~15 lines and proved the swap end-to-end (`capturedWindowID 21829 → 5874, tabs 1→1`).

## Mental model corrections
- Initially assumed a stop()/start() race when swapping a live tab. Wrong — CaptureManager owns the serialization. Reading the file in full caught it before I added unnecessary sequencing.

## Conventions and decisions
- Gated **Set window…** on `focused.isCapturing` only. Idle case is already covered by **Add tab here…** (fills idle tabs) and **Pick window…** (fills idle sessions). Keeping the gating prevents a 3rd "fill idle" entry point that would just duplicate behaviour.
- Per-tab variant ("Set source…" inside *Other tabs ▸*) explicitly deferred — would need a new `OverlayMenuTag.Action` case + per-tab dispatch. Asked the user up front rather than building it speculatively.

## Capability gaps
- Gap: can't drive an actual right-click → picker-modal → click-cell flow headlessly. The `PIP_TEST_*` hook simulates the *callback*, not the menu/modal UI.
  - Workaround: hook calls `setActiveSource` directly, same code path the picker callback would invoke.
  - Suggested unblock: this is the same wall called out in BACKLOG.md's "consolidated headless-verification hook" item — when that lands, menu-driven features get real UI-level coverage instead of the per-feature env-var sprawl currently in `autoCaptureLargest`.

## Processed: 2026-05-11 (auto)

### Items discussed but not acted on
- `PIP_TEST_*` env-hook convention is already documented in `BACKLOG.md` (under the "Headless verification toolkit" track), and the active direction there is *replacement* by a menu-driver helper rather than reinforcement. Re-recording it in `CLAUDE.md` would conflict with that direction; no change.
- CaptureManager already-serializes-stop()-before-start() learning is encoded in the implementation itself (`CaptureManager.start(window:)`). No durable note needed.
- `Set window…` gated on `focused.isCapturing` — local feature decision, lives in the code/PR. No durable note.
- Headless-coverage gap for right-click → modal → click-cell — already tracked in `BACKLOG.md`. No new action.
