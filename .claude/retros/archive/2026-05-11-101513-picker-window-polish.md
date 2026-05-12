# Retro: 2026-05-11 10:15
Session: 3f469db4-1f54-40fd-9596-8398d09a1b39
Topic: picker-window-polish
Branch: main
CWD: /Users/zolat/projects/PiPanything
Duration: ~30 min
Key files: PiPanything/Sources/Picker/PickerWindow.swift, PiPanything/Sources/Picker/PickerCell.swift

## Context
User shared a screenshot of the "Pick a window" modal with two flaws: title bar overlapping the search field, and thumbnails feeling lost in grey letterbox. Fixed by dropping `.fullSizeContentView` from the panel style mask and rewriting `PickerCell` as a layer-backed edge-to-edge tile with a gradient caption overlay.

## Learnings
- `.fullSizeContentView` + `titlebarAppearsTransparent = false` is a footgun — the opaque title bar paints over the content view's top edge. Either drop the flag or pad content for the title bar height.
- `NSImageView` has no aspect-fill — for a Mission-Control-style tile you need a `CALayer` with `contentsGravity = .resizeAspectFill` directly.
- The project's dlsym `CGWindowListCreateImage` path captures windows even when the display is locked, where `screencapture -l <wid>` returns "could not create image from window".

## Conventions and decisions
- The picker's hover/selection treatment now lives on the card's `CALayer.borderColor/borderWidth` rather than a drawn inset rect — matches the edge-to-edge tile language. `HoverView`'s `onDraw` hook is now unused.

## What would have helped at the start
- Knowing the `PIP_OPEN_PICKER=1` env var existed — I grep'd for it after first launching with `PIP_AUTO_CAPTURE=1`. Worth surfacing in CLAUDE.md alongside the auto-capture knob.

## Capability gaps
- Gap: couldn't visually verify with `screencapture` once the macOS lock screen kicked in mid-session.
  - Workaround: wrote a 25-line Swift script using the project's own dlsym CGWindowListCreateImage to grab the window directly.
  - Suggested unblock: a tiny `tools/grab-window.swift` helper checked into the repo (mirrors `CGCompat.legacyCaptureWindow`) so future headless verification doesn't reinvent it each time.

## Processed: 2026-05-11

### Actions taken
- Added `PIP_OPEN_PICKER=1` to the project `CLAUDE.md` "Environment knob for headless verification" list — same "would have helped" item as the picker-above-pip retro.
- Folded the `tools/grab-window.swift` suggestion into the new BACKLOG "Headless verification toolkit" track as item 5.
