# Retro: 2026-05-11 13:50
Session: 0057e8b9-084d-4a8d-b5ed-987c6adf5fa0
Topic: mcp-overlay-control
Branch: main
CWD: /Users/zolat/projects/PiPanything
Duration: ~10 min
Key files: (none — exploratory discussion only)

## Context
Exploratory chat about adding MCP to PiPanything so Claude can drive the overlay (show a window/URL, set geometry, hide) while the user is heads-down in a fullscreen terminal. Landed on a socket + CLI shim architecture: GUI app exposes a Unix domain socket with a simple line/JSON protocol, a separate `pipanythingctl` binary speaks stdio MCP and forwards. No code written; offered to write it up as a `BACKLOG.md` track next.

## Learnings
- Stdio MCP and a long-lived GUI app are a poor fit — stdio servers are spawned per-session, GUIs aren't. A short-lived CLI shim is the natural seam.
- Same-user local IPC barely moves the security needle when the caller (Claude Code) already has shell on the account. Worth not over-modeling.

## Conventions and decisions
- For programmable surfaces on this app, prefer GUI ↔ Unix socket ↔ CLI shim over embedding an MCP/HTTP server in the AppKit process. Keeps the internal protocol decoupled from MCP spec churn and gives a scriptable CLI for free.

## What would have helped at the start
- Nothing — the user framed it as "what do you think" and the right move was a short take, not research.

## Capability gaps
- Gap: Can't sanity-check current MCP transport state-of-the-art (stdio vs streamable HTTP recommendations) without context7/web access — both MCP servers disconnected mid-session.
  - Workaround: Reasoned from prior knowledge of how Claude Code wires stdio MCP servers.
  - Suggested unblock: Keep context7 in the default MCP set for this project, or accept that exploratory chats about external specs need a quick `WebFetch` to a known-good URL before committing to architecture.

## Processed: 2026-05-11 (auto)

### Deferred for human review
- BACKLOG.md track for MCP overlay control (socket + CLI shim architecture) — the user offered to write this up but the session ended before it was filed. `BACKLOG.md` edits are out of the auto-apply safe set. See `auto-retro-2026-05-11-135500.md` for the drafted track.
- Tooling/infrastructure: context7 MCP availability flake during exploratory chats. Out of safe set. See summary file.
