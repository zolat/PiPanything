# Retro: 2026-05-11 10:40
Session: cd59735d-558b-448d-9221-c862e7a79187
Topic: retro-review-pipanything
Branch: main
CWD: /Users/zolat/projects/PiPanything
Duration: ~10 min
Key files: PiPanything/CLAUDE.md (proposed edits, not yet applied)

## Context
Ran `/retros:retro` over 8 unprocessed PiPanything retros. Clustered into one big "PiPanything feature work" body plus a `/lgtm` workflow singleton, surfaced three patterns, and queued two CLAUDE.md edits for approval before the session was interrupted.

## Learnings
- Two separate retros (picker-above-pip, picker-window-polish) flagged `PIP_OPEN_PICKER=1` as undocumented — same complaint, different sessions. The duplicate is itself signal that the env-knob list in CLAUDE.md is the canonical surface and missing entries get felt immediately.
- The `awk '/BUILT_PRODUCTS_DIR/ {print $3}'` line in CLAUDE.md's build snippet is documented-and-broken: a prior session already diagnosed it (status-bar retro) but the fix never landed in the doc. Retros catch this kind of fact-vs-doc drift cleanly.

## Conventions and decisions
- Walked the patterns one-at-a-time per the skill guidance rather than dumping all three plus diffs in one turn. Felt right; the user can redirect cheaply between patterns.
- Bundled the awk fix with the `PIP_OPEN_PICKER` doc add because they touch the same file in adjacent sections — one diff, one approval beat.

## What would have helped at the start
- Knowing the retros dir already had an `archive/` subdir would have saved a beat — I noticed it in `ls` output and confirmed it matches the skill's Step 5 archive flow, but only after grouping.

## Capability gaps
- Gap: no way to tell from the retro files alone whether a "suggested unblock" (e.g. `PIP_TEST_CROP`, `tools/grab-window.swift`) was already attempted and reverted vs never tried.
  - Workaround: relied on the retro author's own framing ("Reverted the hook to keep the diff scoped").
  - Suggested unblock: a lightweight "status" line per suggested-unblock — `attempted/reverted`, `not tried`, `landed` — so cross-retro pattern review can tell live gaps from settled ones.

## Processed: 2026-05-11

### Actions taken
- None — the two CLAUDE.md edits this retro queued (`PIP_OPEN_PICKER` env-knob doc, `awk` build-snippet fix) had already landed in `PiPanything/CLAUDE.md` by the time this retro was reviewed.

### Items discussed but not acted on
- "Capability-gap status line" suggestion (attempted/reverted/landed markers on retro entries). Single-vote signal; revisit if it recurs.
