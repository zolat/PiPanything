# Roadmap

**Current:** ✅ Done — ready for review on `feat/tabs`

- [x] Phase 0 — Worktree + ROADMAP
- [x] Phase 1 — Extract OverlayTab (pure refactor; tabs.count == 1)
- [x] Phase 2 — N tabs + tab strip UI (3 SCStreams concurrent in 1 session, strip auto-hides)
- [x] Phase 3 — Menu integration ("Add tab here…" + "Other tabs ▸" submenu, closeTab dispatch verified)
- [x] Phase 4 — Tear-out + move-to (tearOutTab dispatch verified — sessions 1→2 with same source)
- [x] Phase 5 — ⌃⌥N cycle tabs (cycles tabs in tabbed primary, falls through to source-cycle otherwise)
- [x] Phase 6 — Final verification (build clean, single-overlay regression, multi-window regression, multi-tab smoke, dispatch chains, natural-hover strip reveal verified, clean SIGTERM teardown)

Post-advisor fixes:
- SourceVisibility.applyState now short-circuits on `!enabled` (was forcing window visible from inactive controllers).
- TabStripView and TabPillView override `mouseDownCanMoveWindow` so clicks don't drag the window.
- Tab strip's NSTrackingArea now installed on the superview (whole overlay area), not on the strip itself — was only firing in the invisible top sliver.

Plan: `~/.claude/plans/serialized-finding-meadow.md`. Branch: `feat/tabs`.

Multi-overlay roadmap (now landed on main as commits 74b70ec + 4ead384) is archived — reference the merged commits if needed.
