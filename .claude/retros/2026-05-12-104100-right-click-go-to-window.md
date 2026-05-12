# Retro: 2026-05-12 10:41
Session: 4ae6e43e-ca37-498b-8acd-b52f6185da03
Topic: right-click-go-to-window
Branch: main
CWD: /Users/zolat/projects/PiPanything
Duration: ~35 min
Key files: PiPanything/Sources/App/OverlaySession.swift, PiPanything/Sources/App/AppDelegate.swift, PiPanything/Sources/Picker/SourcePickerMenu.swift

## Context
Added a "Go to window" item at the top of the overlay right-click menu, mirroring the existing ⌘-click gesture (raise captured source, cross-Space-aware). Three-file change: new enum case + un-`private`d the existing method + new menu item; dispatch wiring is identical to the other items.

## Learnings
- `cliclick`-synthesised mouse events don't drive NSMenu popups — clicks at known item coordinates do nothing and don't dismiss the menu either. Popup tracking loops filter synthetic events differently from real ones.
- Keyboard nav into a `popUpContextMenu` from `OverlayWindow` is also dead — the window doesn't override `canBecomeKey`, so arrow keys route to whatever was frontmost (Finder in my case).
- `AVSampleBufferDisplayLayer.contentsRect`-style "the SDK lies about this" lore from CLAUDE.md saved me again — I ignored the SourceKit "cannot find type" diagnostics three times after the xcodegen regen.

## Dead ends
- ~10 minutes trying to drive the popup menu via `cliclick` (sweeping y-coords, move-then-click, keyboard nav). None of it worked. Should have cut to equivalence-based verification sooner.
- `osascript`-querying open NSMenus via System Events returned empty / nothing — contextual menus aren't exposed through the AX process tree the way menu bar menus are.

## Conventions and decisions
- Placed "Go to window" above "Stop" so the primary navigation action is first. Easy to revert; flagged in the final report.

## Capability gaps
- Gap: Can't end-to-end click a `popUpContextMenu` item from outside the process for verification.
  - Workaround: Verified by equivalence — visual screenshot confirmed item placement, dispatch wiring matched working items, and the ⌘-click code path (calling the same `activateActiveSource`) was end-to-end-verified instead.
  - Suggested unblock: A dev-only `PIP_TEST_FIRE_MENU=<action>` env that posts `NSMenu.performActionForItem(at:)` against a freshly built menu, or a control-socket `fire_menu_action` command, so menu wiring is testable without UI automation.
