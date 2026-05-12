# Retro: 2026-05-11 09:30
Session: c1d8da85-d5d7-4c1c-9c8b-3da5cf3d2b23
Topic: picker-above-pip-overlays
Branch: main
CWD: /Users/zolat/projects/PiPanything
Duration: ~25 min
Key files: PiPanything/Sources/Picker/PickerWindow.swift

## Context
User reported the window picker rendering behind PiP overlays. Root cause: overlays sit at `.screenSaver` (1000) for cross-Space rendering, picker panel was at `.floating` (3). One-line fix — raise the picker to `.screenSaver` and rely on within-level ordering.

## Learnings
- `NSPanel.makeKeyAndOrderFront` doesn't override window level — level dominates z-order regardless of activation. `NSApp.activate(ignoringOtherApps:)` was a red herring.
- Within the same level, last-`orderFront` wins. So matching the overlay's named level + relying on draw order is cleaner than picking a higher raw value.
- The codebase has a `PIP_OPEN_PICKER=1` env var that opens the picker on launch — perfect for headless layering verification when combined with `PIP_AUTO_CAPTURE=1`.

## Mental model corrections
- I initially worried the right-click NSMenu had the same bug. It doesn't — macOS renders NSMenus via the system menu service outside the normal window z-order. The PickerPanel (NSPanel) was the only thing that needed fixing.

## Conventions and decisions
- When a panel needs to sit above PiP overlays, match the overlay's *named* level rather than picking a higher raw value. Keeps the two coupled if overlay level ever moves.

## What would have helped at the start
- Knowing about `PIP_OPEN_PICKER=1` upfront. I burned a couple of minutes figuring out how to trigger the picker from a shell-driven test before grepping AppDelegate.

## Capability gaps
- Gap: no programmatic way to inspect NSWindow z-order from outside the app to *prove* layering.
  - Workaround: two-shot screenshot comparison (overlay-only vs overlay+picker) — overlay visibly disappeared behind the picker.
  - Suggested unblock: a tiny debug command (env-flag or hidden hotkey) that dumps every PiPanything NSWindow's level + order to the log. Would turn future "is X above Y?" checks into a one-line grep.

## Processed: 2026-05-11

### Actions taken
- Added `PIP_OPEN_PICKER=1` to the project `CLAUDE.md` "Environment knob for headless verification" list — directly addresses the "what would have helped at the start" item.
- Folded the z-order dump suggestion into the new BACKLOG "Headless verification toolkit" track as item 4 (`PIP_DUMP_WINDOWS=1`).
