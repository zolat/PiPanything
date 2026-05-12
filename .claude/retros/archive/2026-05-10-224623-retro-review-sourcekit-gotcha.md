# Retro: 2026-05-10 22:46
Session: f1bf690b-1ada-467f-a327-b74d53d3d86e
Topic: retro-review-sourcekit-gotcha
Branch: main
CWD: /Users/zolat/projects/PiPanything
Duration: ~5 min
Key files: (none modified — proposed CLAUDE.md edit awaiting user confirm)

## Context
Ran `/retros:retro` over the two unprocessed PiPanything retros. Both standalone — one tiny ops note, one substantive multi-overlay session. Drove to the strongest actionable signal (CLAUDE.md gotcha for stale SourceKit diagnostics post-`xcodegen generate`) and proposed the edit. User hasn't confirmed yet, so nothing applied.

## Learnings
- Two-retro backlogs don't need a grouping ceremony — just walk them. The skill's grouping pass is overhead at this volume; lead with the punchiest finding directly.

## Conventions and decisions
- Picked one pattern with conviction (SourceKit noise) instead of enumerating all candidates from the multi-overlay retro. The capability gap (menu-driver helper) and the NSMenu.identifier learning are real but second-order; mentioning them as a buffet would have diluted the ask.

## Capability gaps
- Gap: can't tell from the retro alone whether the SourceKit noise hits any LSP-driven *agent* tool I have, or only the human's IDE. Wrote the gotcha to cover both, but didn't verify.
  - Workaround: phrased the bullet as "IDE and any LSP-driven agent tools" — covers both without overclaiming.
  - Suggested unblock: when the LSP tool is loaded, do a quick post-`xcodegen` smoke (touch a known-good symbol, see if LSP flags it) and tighten the wording.

## Processed: 2026-05-10

### Actions taken
- Cleaned up the stale `BACKLOG.md` entry: moved "Multiple simultaneous overlays" from the ⛔ blocked tracks list into the **Done (v1)** table with commit `74b70ec`. Removed it from the parallel-fitness summary too.

### Items discussed but not acted on
- The "two-retro backlogs don't need a grouping ceremony" learning — meta-process observation about the `/retros:retro` skill itself; valid but doesn't merit a skill edit on a single data point. Worth revisiting if the same friction shows up across more retros.
- The capability-gap hedge about LSP vs IDE — phrased the CLAUDE.md gotcha to cover both deliberately; a tighter wording would only help once we verify against the actual LSP tool, and that verification didn't happen this session.
