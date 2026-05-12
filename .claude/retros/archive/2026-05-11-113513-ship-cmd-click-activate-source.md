# Retro: 2026-05-11 11:35
Session: 3e069443-a644-4944-8ba3-1a830de78364
Topic: ship-cmd-click-activate-source
Branch: main
CWD: /Users/zolat/projects/PiPanything
Duration: ~5 min
Key files: PiPanything/Sources/App/OverlaySession.swift, PiPanything/Sources/Capture/AccessibilityHelpers.swift, PiPanything/Sources/Overlay/OverlayWindow.swift, PiPanything/Sources/Features/SourceActivator.swift, BACKLOG.md, CLAUDE.md

## Context
Pure shipping session. Picked up an in-progress working tree (⌘-click activate-source feature + BACKLOG / CLAUDE doc updates already written), split it into two logical commits, pushed to `origin/main`. No code written, no verification beyond a status check.

## Conventions and decisions
- "Commit the staged current work" with nothing actually `git add`ed reads as "commit what's pending" — interpret accordingly, don't bounce back asking.
- Two commits beat one even for tiny ships: feature in one, unrelated doc edits in another. Reviewers can read either independently.
- `.claude/` (retros, worktrees) stays untracked — it's local agent state, not repo content. Don't reflexively `git add .`.

## Capability gaps
- Gap: no way to confirm the ⌘-click feature actually works without manually launching the app and ⌘-clicking a PIP — the diff alone can't tell me whether AX raise + `NSRunningApplication.activate` produces the intended Space switch in practice.
  - Workaround: shipped on the assumption the implementing session verified it.
  - Suggested unblock: this is exactly what the "Headless verification toolkit" backlog entry (committed in this session) is for — `PIP_DUMP_WINDOWS` + a synth `⌘-leftMouseDown` env hook would let a future session run the check from a shell.

## Processed: 2026-05-11

### Actions taken
- Codified "Split shipping commits by intent" as a new bullet in `PiPanything/CLAUDE.md` Shipping section — captures the two-commit pattern this retro session actually executed (`1d3a392` docs + `406bfa7` feature).

### Items discussed but not acted on
- Headless-verification gap for ⌘-click activate-source — already tracked as the "Headless verification toolkit" entry in `BACKLOG.md`; no duplicate action needed.
