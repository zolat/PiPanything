# Agent control surface

PiPanything exposes a Unix-domain control socket that lets external
processes script the overlay. The companion binary `pipanythingctl`
ships inside the .app and speaks that socket; in Phase 2 it will also
expose the same surface as an MCP server over stdio for Claude Code.

```
┌──────────────┐    AF_UNIX NDJSON     ┌──────────────────────┐
│ PiPanything  │ ◄───────────────────► │ pipanythingctl       │ ◄── stdio MCP ──► Claude Code   (Phase 2)
│ (Swift GUI)  │                       │ (Rust: CLI+MCP shim) │ ◄── shell args ── you
└──────────────┘                       └──────────────────────┘
```

## Status

| Phase | Status | What it gives you |
|---|---|---|
| 1 — socket + CLI | ✅ this doc | Scriptable from a shell. `pipanythingctl list / show / hide / geom / crop / …` |
| 2 — MCP shim | 🚧 | `pipanythingctl mcp` exposes the same surface to Claude Code over stdio. |
| 3 — `show_url` | ⏳ | WKWebView player so agents can drop any URL into PiP. Folded into the Safari extension track. |
| 4 — event stream | ⏳ | Server-pushed `overlay_closed` / `source_quit` notifications. |

## First-ship opt-in

The control server is **off by default**. To enable, launch the app
with `PIP_CONTROL_SERVER=1`:

```sh
PIP_CONTROL_SERVER=1 open -ga PiPanything
# or
/Applications/PiPanything.app/Contents/MacOS/PiPanything   # with env in your shell
```

`pipanythingctl` sets that env var automatically when it auto-launches
the app, so if you just run `pipanythingctl list` cold it'll bring the
app up correctly. Once the surface has baked, this gate will be removed
and the server will be on by default.

## Socket

`~/Library/Application Support/PiPanything/control.sock`, mode `0600`.
Stale paths from a crashed app are unlinked on start. Same-user only —
same security model as any other Unix socket in your home directory.

## Wire format

Newline-delimited JSON over an AF_UNIX SOCK_STREAM. One request line in,
one response line out, per call.

**Request:**

```json
{"id": "req-1", "cmd": "show", "args": {"query": "Finder"}}
```

- `id` (optional, opaque) — echoed back so the client can correlate.
- `cmd` — see the command catalog below.
- `args` — per-command payload (may be omitted for commands that take none).

**Response (success):**

```json
{"id": "req-1", "ok": true, "result": {"overlay_id": "...", "tab_id": "..."}}
```

**Response (failure):**

```json
{"id": "req-1", "ok": false, "error": "no window matched 'NoSuchApp'"}
```

The Rust types in `pipanythingctl/src/protocol.rs` and the Swift types
in `PiPanything/Sources/Server/ControlProtocol.swift` are the source of
truth — they change in lockstep.

## Identity model

- **Overlay** — `overlay_id`, a UUID string. Stable for the overlay's
  lifetime; safe to cache across commands.
- **Tab** — `tab_id`, a UUID string. Stable for the tab's lifetime.
- **Window (capturable source)** — `window_id`, a `CGWindowID`
  (`uint32`). Only valid until the source app closes that window —
  re-run `list_windows` before relying on a previously-seen ID.

## Command catalog

| Command | Args | Returns |
|---|---|---|
| `ping` | — | `{version, pid}` |
| `list_windows` | `{refresh?: bool}` | `[{window_id, app_name, bundle_id, pid, title, width, height}]` |
| `list_overlays` | — | `[{overlay_id, label, is_capturing, captured_window_id?, frame, opacity, click_through, auto_hide, manually_hidden, tabs}]` |
| `show` | `{window_id?, query?, overlay_id?, new_overlay?, new_tab?, crop?}` | `{overlay_id, tab_id}` |
| `hide` | `{overlay_id, mode?: "hide"\|"stop"\|"remove"}` | `{}` |
| `hide_all` | — | `{}` |
| `geom` | `{overlay_id, x?, y?, w?, h?}` | `{frame}` |
| `crop` | `{overlay_id, tab_id?, rect?: {x,y,w,h}}` | `{}` |
| `opacity` | `{overlay_id, alpha: 0…1}` | `{}` |
| `click_through` | `{overlay_id, enabled: bool}` | `{}` |
| `auto_hide` | `{overlay_id, enabled: bool}` | `{}` |

### Window matching (`show`)

- `window_id` exact match.
- `query` — case-insensitive substring against `"{app_name} — {title}"`. First match wins.
- Neither → `missing arg: 'show' requires window_id or query`.

### Overlay routing (`show`)

- `overlay_id` + `new_tab: true` → `addTab` on that session.
- `overlay_id` only → replace the active tab's source.
- No `overlay_id`, `new_overlay: true` → always spawn a new overlay (respects the 4-overlay soft cap).
- No `overlay_id`, primary is idle → fill the primary (mirrors the right-click picker's "fill idle" default).
- No `overlay_id`, primary busy → spawn a new overlay (respects soft cap).

### Hide modes

| Mode | Effect |
|---|---|
| `hide` | Toggle the manual-hide latch on every tab — overlay's window orders out until toggled back. |
| `stop` | Stop every tab; session returns to idle. The window stays as an idle entry point. |
| `remove` | Tear the session down completely. **Not valid for the primary** — it always survives. |

**Default mode:** `stop` for the primary overlay, `remove` for secondaries. Mirrors the existing right-click "Stop" menu.

### Geometry and crop coordinate systems

- `geom.{x,y,w,h}` — screen-coordinate points, bottom-left origin (`NSWindow.setFrame`). Missing fields preserve the current value.
- `crop.rect.{x,y,w,h}` — normalized `[0, 1]`, bottom-left origin. `rect` omitted → clear the crop.

### Known limitation: `show` + crop

`crop` passed inside `show` is accepted on the wire but **not honored**
in Phase 1. `applyCropProgrammatic` no-ops until `sourceAspect` settles
on first frame. Workaround: call `show` to start capture, then call
`crop` separately once `list_overlays` reports `is_capturing: true`.

## CLI reference

```
pipanythingctl ping
pipanythingctl list                              # capturable windows
pipanythingctl overlays                          # active overlays
pipanythingctl show "Finder"                     # by query
pipanythingctl show --window-id 12345            # by exact ID
pipanythingctl show "Finder" --new-overlay
pipanythingctl show "Safari" --overlay <UUID> --new-tab
pipanythingctl hide <UUID>                       # default mode
pipanythingctl hide <UUID> --mode hide|stop|remove
pipanythingctl hide --all
pipanythingctl geom <UUID> --x 100 --y 100 --w 640 --h 360
pipanythingctl geom <UUID> --x 200 --y 200       # move only (preserve size)
pipanythingctl crop <UUID> --rect 0.25,0.25,0.5,0.5
pipanythingctl crop <UUID> --clear
pipanythingctl opacity <UUID> 0.8
pipanythingctl click-through <UUID> on|off
pipanythingctl auto-hide <UUID> on|off
```

Global flags:

- `--socket <path>` — override the control socket path.
- `--no-launch` — don't auto-launch PiPanything if the socket is unreachable.

### Auto-launch

If the socket can't be reached, the CLI shells out to
`open -ga <bundle-path> --env=PIP_CONTROL_SERVER=1`, then polls the
socket every 100ms for up to 5s. The bundle path is resolved from the
CLI's own location via `current_exe`, so the worktree's CLI launches
the worktree's app, not whichever bundle LaunchServices most recently
registered.

## MCP server (Phase 2, not yet implemented)

```sh
pipanythingctl mcp        # planned subcommand
```

Speaks JSON-RPC 2.0 over stdio per the Model Context Protocol spec.
Each socket command becomes one tool (`pip_show`, `pip_list_windows`,
etc.); `pipanything://windows` and `pipanything://overlays` are exposed
as resources.

Once shipped, register in Claude Code:

```json
{
  "mcpServers": {
    "pipanything": {
      "command": "/Applications/PiPanything.app/Contents/Resources/pipanythingctl",
      "args": ["mcp"]
    }
  }
}
```

## Building from source

```sh
rustup target add aarch64-apple-darwin x86_64-apple-darwin   # one time
xcodegen generate                                            # if not already
xcodebuild -scheme PiPanything -configuration Debug build
```

The Xcode build invokes `tools/build-cli.sh` which compiles the Rust
crate at `pipanythingctl/` and copies the resulting binary into the
.app bundle's `Contents/Resources/`. Debug builds use the host arch
only; Release builds produce a `lipo`'d universal binary.

## Standalone CLI distribution (planned)

`git subtree split --prefix=pipanythingctl/ …` will publish the CLI
subdir to a separate mirror repo that a homebrew tap can point at.
Until then, install via the symlink trick:

```sh
ln -s "/Applications/PiPanything.app/Contents/Resources/pipanythingctl" \
      /usr/local/bin/pipanythingctl
```
