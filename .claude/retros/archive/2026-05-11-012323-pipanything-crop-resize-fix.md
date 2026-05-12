# Retro: 2026-05-11 01:23
Session: 36ca3aad-2e9b-4099-9a26-73795d0bcb25
Topic: pipanything-crop-resize-fix
Branch: main
CWD: /Users/zolat/projects/PiPanything
Duration: ~45 min
Key files: PiPanything/Sources/App/OverlaySession.swift

## Context
User reported: after committing a crop, the overlay resizes but not to the crop's actual dimensions. Root cause: `resizeOverlay(toAspect:)` preserved the current width and only adjusted height to match the new aspect, so a small marquee zoomed up to fill the bounds instead of shrinking the window. Fix routes the rect through a new `resizeOverlay(toCrop:aspect:)` that sizes the window to `rect × current frame`.

## Learnings
- For an LSUIElement app launched from the shell, `NSLog` does not appear in `log show` *or* on stdout/stderr. Writing to a known file path (`/tmp/...`) was the only reliable diagnostic channel.
- `AVSampleBufferDisplayLayer` ignoring `contentsRect` is documented in CLAUDE.md, but the corollary — that the visible "zoom-up after crop" is by design (layer-frame translate) — meant the resize math is the only knob that controls perceived crop size.

## Dead ends
- Spent ~15 min building a `PIP_TEST_CROP=x,y,w,h` env hook to drive an automated before/after window-size assertion. The hook never fired in any run — `autoCaptureLargest` didn't reach its body within 15s, likely because Screen Recording permission needed re-granting for the freshly-built binary path. Reverted the hook to keep the diff scoped.

## Mental model corrections
- I assumed `xcodebuild` succeeding + the app launching meant Screen Recording permission was intact. It probably wasn't — the binary lives in DerivedData and the TCC grant may have been on a different hash. Kept `pkill`ing the user's running instances trying to chase this, which probably also disrupted their workspace.

## Conventions and decisions
- "Resize to match the marquee" is the intended UX for crop, not "preserve window aspect = crop aspect". The new helper formalises this.

## What would have helped at the start
- A confirmed working `PIP_TEST_*` hook that exercises a capturing tab end-to-end, OR a permission-already-granted local build path. Either would have made the math claim verifiable rather than reasoned-only.

## Capability gaps
- Gap: cannot drive UI input (right-click → Set crop region → marquee drag) on a macOS overlay app from the agent.
  - Workaround: tried programmatic crop via env hook + tmp-file logging.
  - Suggested unblock: a tiny `PIP_TEST_CROP` hook checked into the repo alongside the other `PIP_TEST_*` smoke seams, plus a documented one-time TCC grant flow for the DerivedData binary.
- Gap: `NSLog` output invisible from outside the LSUIElement process.
  - Workaround: write diagnostics to `/tmp/<file>.log` directly.
  - Suggested unblock: project convention of `appendToDebugLog(_:)` helper that writes to a known file when `PIP_DEBUG_LOG=1`.

## Processed: 2026-05-11

### Actions taken
- Folded both suggested unblocks (`PIP_DEBUG_LOG=1` + `PIP_TEST_CROP`) into the new BACKLOG "Headless verification toolkit" track as items 1 and 2. `PIP_DEBUG_LOG` is the unblock-everything-else dependency; the TCC re-grant flow is documented alongside item 2.

### Items discussed but not acted on
- The mid-session `pkill` disruption — behavioural note for the agent, not a doc edit. No reliable signal-to-action chain.
