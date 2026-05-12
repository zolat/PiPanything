# Retro: 2026-05-10 23:28
Session: 223bc73d-1db9-4082-9d40-059397dbd51e
Topic: pipanything-gplv3-license
Branch: main
CWD: /Users/zolat/projects/PiPanything
Duration: ~10 min
Key files: LICENSE

## Context
User asked for a license for PiPanything (standalone Mac app), favouring GPL over MIT. Discussed the split (GPL for apps, MIT for libs), flagged AGPL for network-exposed projects, then dropped canonical GPLv3 at the project root.

## Learnings
- WebFetch summarises rather than returning verbatim text — wrong tool for fetching license text. `curl -fsSL` to a file is the right call when byte-exactness matters.

## Conventions and decisions
- Single `LICENSE` at repo root is legally sufficient; per-file FSF headers are optional and skipped by default to avoid touching every Swift file. Offered as a follow-up.
- Source of truth: `https://www.gnu.org/licenses/gpl-3.0.txt` over HTTPS, 674 lines.

## What would have helped at the start
- Knowing the WebFetch summarisation behaviour up front would have skipped one tool-selection beat.

## Processed: 2026-05-11

### Actions taken
- Added "Fetching verbatim text" Ground Rule to `~/.claude/CLAUDE.md` codifying `WebFetch` summarises / use `curl -fsSL` for byte-exactness.

### Items discussed but not acted on
- Per-file FSF headers — out of scope, retro itself flagged them as deferred.
