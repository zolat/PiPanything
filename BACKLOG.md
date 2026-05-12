# PiPanything backlog

Cross-session task board. Companion to the long-form plan at
`~/.claude/plans/i-think-we-proven-purrfect-scone.md` (which captures the
*why* and the architecture). This doc tracks the *what's next* in flight,
and which sibling session is on what.

## How to use this doc

1. Read this file + the plan file.
2. Pick a 🟢 **open** track. Prefer ones with no blockers listed.
3. Update its status to 🟡 **claimed**, add a one-line session note (date,
   approach), commit on a feature branch.
4. Plan-mode the track in your session, implement, verify per the
   **Acceptance** line, commit.
5. Move the row to the **Done** section at the bottom with the commit SHA.

## Status legend

| | |
|---|---|
| 🟢 | open — anyone can claim |
| 🟡 | claimed — taken, not yet implementing |
| 🔵 | in progress — work landing |
| ⛔ | blocked — waiting on a dependency |
| ✅ | done — merged to `main` |

## Quick parallel-fitness summary

| Track | Status | Parallel-safe? |
|---|---|---|
| Global hotkeys | 🔵 | yes |
| **Agent-control surface (socket + CLI + MCP shim)** | 🔵 | yes |
| **Menu-driver helper for end-to-end verification** (high priority) | 🟢 | yes |
| **Headless verification toolkit** (medium priority) | 🟢 | yes |
| Per-PIP media-key forwarding (research) | 🟢 | yes |
| Safari extension + URL deep link | 🟢 | yes |
| `sampleBufferRenderer` deprecation cleanup | 🟢 | yes |
| Resize aspect-lock fidelity debug | 🟢 | yes |
| Developer-ID signing + notarization | 🟢 | yes (logistical) |
| DRM video workaround (research only) | 🟢 | yes |
| Auto-hide per-window precision | ⛔ | no — wait for in-session window-identity helper |

---

## Tracks

### Global hotkeys (start/stop, hide, cycle source)

**Status:** 🔵 in progress · **Parallel-safe:** yes · **Depends on:** none.
**Touches:** new `Features/Hotkeys.swift`, plus small additions to `App/AppDelegate.swift` and `Features/SourceVisibility.swift`. Carbon `RegisterEventHotKey` directly (no MASShortcut dependency).
**Scope:** three defaults — `⌃⌥P` toggle capture (stop / restart last source within session), `⌃⌥H` toggle overlay visibility, `⌃⌥N` cycle sources from the current picker list. No customization UI yet; constants in code. `⌃⌥P`'s "last" is in-memory only — persistence was deliberately dropped (window content is too dynamic to make on-disk identity reliable).
**Acceptance:** shortcuts fire even when other apps are frontmost; do not steal keys when typing in a text field elsewhere; on `applicationWillTerminate`, hotkeys are unregistered cleanly.

### Agent-control surface (socket + CLI + MCP shim)

**Status:** 🔵 in progress · **Parallel-safe:** yes (net-new files; one small wiring point in `AppDelegate`) · **Depends on:** none for Phase 1–2. Phase 3 (`show_url`) overlaps the Safari extension track's WKWebView player and should land after it (or share that work). Plan file at `~/.claude/plans/jazzy-strolling-meerkat.md`.
**Session note (2026-05-11):** Phase 1 (socket + Rust CLI, no MCP shim) landing in worktree `agent-control-phase-1`. Env-gated behind `PIP_CONTROL_SERVER=1` for first ship.
**Touches:** new `Server/{ControlServer,ControlProtocol,ControlHandlers}.swift` in the app target; new **Rust** `pipanythingctl/` subdir (Cargo workspace, `cargo build` driven by a Run Script build phase in `project.yml`); `App/AppDelegate.swift` wiring (~6 lines, env-gated); new `tools/build-cli.sh`, `tools/publish-cli-mirror.sh`; new `docs/agent-control.md`; small `CLAUDE.md` note.
**Why:** PiPanything's headline value — surfacing something from another Space — is exactly the situation a fullscreen Claude Code terminal puts the user in. A programmable surface lets Claude show a build window, a PR tab, a chart, or a generated image without the user switching Spaces. Same-user local IPC, so the security model is "no auth needed beyond default socket perms" (Claude Code already has shell on the account).
**Architecture:** Swift GUI app exposes a Unix domain socket (`~/Library/Application Support/PiPanything/control.sock`, mode 0600), NDJSON wire format. A separate **Rust** `pipanythingctl` binary speaks the socket and is also Claude's MCP server (`pipanythingctl mcp` subcommand → stdio MCP). Single ~2MB static binary, ships inside `PiPanything.app/Contents/Resources/pipanythingctl` (lipo'd universal). CLI auto-launches the GUI with `open -ga PiPanything` if the socket is absent.
**Repo layout:** monorepo for dev (atomic wire-protocol PRs touch `ControlProtocol.swift` and `pipanythingctl/src/protocol.rs` together). Standalone mirror repo via `git subtree split --prefix=pipanythingctl/` for homebrew tap / `cargo install --git`. One-way sync, monorepo is source of truth.
**Phasing:** (1) Socket + minimal CLI (`list`, `show`, `hide`, `list_overlays`, `geom`, `crop`, `opacity`, `click_through`, `auto_hide`, `ping`) — validates the wire and unblocks scripted feature testing too. Opt-in via `PIP_CONTROL_SERVER=1` env gate. (2) `pipanythingctl mcp` shim → stdio MCP server with one tool per socket command. (3) `show_url` — requires the WKWebView player from the Safari track. (4) Event stream (socket push for `overlay_closed` / `source_quit`) surfaced as MCP notifications.
**Acceptance (Phase 1):** with the app running, `pipanythingctl list` prints the same capturable windows the right-click picker shows; `pipanythingctl show "<title-substring>"` opens an overlay; `pipanythingctl overlays` lists it with a stable `overlay_id`; `pipanythingctl hide <id>` closes it. **Phase 2:** registering `pipanythingctl mcp` in a local Claude Code instance and asking it to "show me Finder in PiP" opens the overlay end-to-end.
**Origin:** 2026-05-11 chat with user — confirmed low-security same-user IPC, the socket+CLI+MCP-shim split, **Rust** for the CLI, and subtree-mirror repo layout.

### Menu-driver helper for end-to-end verification

**Status:** 🟢 open · **Priority:** high · **Parallel-safe:** yes · **Depends on:** none (Accessibility grant the app already requires is sufficient).
**Touches:** new `tools/menu-driver.sh` (or `.applescript`); a short note under "Build / run" in `CLAUDE.md` pointing future agents at it.
**Why:** the multi-overlay track had to ship a `PIP_TEST_STOP_INDEX` env hook to verify menu dispatch because there was no way to programmatically click an item in the right-click overlay menu (or a future status-bar menu). Same gap will block live verification of auto-hide, source-quit handling, and any future menu-driven feature. Per-feature `PIP_TEST_*` knobs don't scale and bleed test paths into production code.
**Scope:** small CLI wrapper that, given a menu-item title (or path like `Source › Stop`), uses `osascript` + `System Events` UI scripting to click that item in PiPanything's frontmost menu. No `cliclick` dependency required. Should also support opening the right-click overlay menu (synthesise a right-click at a point inside an overlay's bounds, then click an item). Add a one-paragraph CLAUDE.md note documenting the script and the convention "prefer the menu-driver over adding a new `PIP_TEST_*` env hook for menu verification".
**Acceptance:** from a shell, `tools/menu-driver.sh "Stop"` (or equivalent) closes the running overlay end-to-end against a live build; verifiable by tailing `/tmp/pipanything.log` and seeing the same `handleOverlayMenu` log line that the synthesised env-hook produced.
**Origin:** captured in retro `2026-05-10-224048-multi-overlay-pip-sessions.md` under "Capability gaps".

### Headless verification toolkit

**Status:** 🟢 open · **Priority:** medium · **Parallel-safe:** yes · **Depends on:** none. Complements the Menu-driver track (which targets NSMenu UI scripting); this one targets internal app state, layers, and gestures.
**Touches:** new `Features/DebugLog.swift`, additional `PIP_TEST_*` env hooks in existing feature modules, new `tools/grab-window.swift`; optionally a small `DebugDump` helper for window-state dumps.
**Why:** five retros (`crop-resize-fix`, `overlay-resize-bounds`, `picker-above-pip-overlays`, `picker-window-polish`, `media-key-forwarder`) each hit the same wall — there's no programmatic way to verify UI/state changes in an LSUIElement screen-capture overlay from outside the process. `NSLog` is invisible to `log show` for LSUIElement; `screencapture -l <wid>` fails at the lock screen; `NSWindow` z-order isn't externally observable; the resize handle's aspect-preserving drag has no synth path; and HID-level media-key routing can't be confirmed via `cgEvent.post`. Each retro proposed a single-purpose hook — consolidating them avoids per-feature env-var sprawl and gives future sessions one place to look.

**Scope (in priority order — item 1 unblocks the rest):**

1. **`PIP_DEBUG_LOG=1` writes-to-file helper** (`Features/DebugLog.swift`). `appendToDebugLog(_:)` writes timestamped lines to `/tmp/pipanything.log`. Survives the LSUIElement NSLog blackhole; all subsequent test seams write through it.
2. **`PIP_TEST_CROP=x,y,w,h` env hook.** Drives the marquee-crop pipeline programmatically against `autoCaptureLargest`. Document the one-time TCC re-grant flow for the DerivedData binary alongside it (the crop-resize-fix retro lost ~15 min to a silently-revoked grant).
3. **`PIP_TEST_DRAG_RESIZE=w,h` env hook.** Synthesizes `mouseDown` / `mouseDragged` / `mouseUp` on the resize handle and logs the resulting frame. The only path that exercises the handle's aspect-preserving clamping (AX `set size` skips the handle).
4. **`PIP_DUMP_WINDOWS=1` debug dump.** On launch (or hidden hotkey), logs every PiPanything `NSWindow`'s `level`, `frame`, and `orderedIndex` via `appendToDebugLog`. Turns "is X above Y?" into a one-line grep instead of a two-shot screenshot comparison.
5. **`tools/grab-window.swift`.** Small CLI mirroring `CGCompat.legacyCaptureWindow` so headless verification has a working window-grab path even when `screencapture` is blocked (lock screen, hardware-rendered surfaces, DRM).
6. **HID-level consumer-usage event helper** (`tools/hid-media-key.swift` or `hidutil` wrapper). Posts a real consumer-usage event at the IOKit/driver layer, indistinguishable from a physical keypress, to close the MediaKeyForwarder's last verification gap (`cgEvent.post` exercises every code path inside the forwarder but doesn't prove HID-level routing).

**Convention:** all `PIP_TEST_*` hooks share a gate shape — fire only when the env var is set and `PIP_AUTO_CAPTURE=1` (or `PIP_OPEN_PICKER=1`) has produced the state to test against. Hooks live in the feature module they exercise, log their before/after via `appendToDebugLog`, and never bleed into production code paths.

**Acceptance:** each retro's "could not verify X" gap collapses to a one-line shell invocation against a fresh build. Specifically: a `PIP_TEST_DRAG_RESIZE` run writes a before/after frame line to `/tmp/pipanything.log`; a `PIP_DUMP_WINDOWS` run writes a tabular `(window, level, ordered_index)` dump; `tools/grab-window.swift <wid> out.png` produces a PNG with the display locked; the HID helper posts an `F8` that the existing `MediaKeyForwarder` event tap observes as an inbound `NX_SYSDEFINED`.

**Origin:** consolidated from retros `2026-05-11-{012323-pipanything-crop-resize-fix, 004606-overlay-resize-bounds, 093048-picker-above-pip-overlays, 101513-picker-window-polish, 103806-pipanything-media-key-forwarder}.md` under their respective "Capability gaps" sections. Item 1 is the unblock-everything-else; items 2–6 are independent and can land in any order.

### Safari extension + URL deep link → WKWebView player

**Status:** 🟢 open · **Parallel-safe:** yes (separate target) · **Depends on:** **gated** for distribution by the Developer-ID track, but the code can be written first.
**Touches:** new Xcode app-extension target `PiPanythingSafari/`, new `Features/PlayerWindow.swift`, new URL handler in `App/AppDelegate.swift`, `Info.plist` URL scheme registration (`pipanything://`).
**Scope:** Safari extension reads the active YouTube tab URL, opens `pipanything://watch?url=…`. Main app spawns a `WKWebView`-based player inside the existing `OverlayWindow` shell — bypasses the screen-capture pipeline entirely for the YouTube case (no chrome cropping, no polling CPU).
**Acceptance:** toggle the extension in Safari Settings → Extensions; clicking its toolbar button on a YouTube tab opens a player overlay with audio + video; persists across Spaces; ⌥-click in our picker should still work for non-Safari sources.
**Gotchas:** Safari extensions require the App Sandbox. Cannot share a target with the main app's screen-capture pipeline. Two-target arrangement is correct: extension sandboxed, main app stays unsandboxed.

### `sampleBufferRenderer` deprecation cleanup

**Status:** 🟢 open · **Parallel-safe:** yes · **Depends on:** bumping deployment target to macOS 14 — **confirm with user** first.
**Touches:** `Capture/CaptureManager.swift` only.
**Scope:** swap `displayLayer.enqueue(_:)` → `displayLayer.sampleBufferRenderer.enqueue(sampleBuffer:)`, `displayLayer.isReadyForMoreMediaData` → `…sampleBufferRenderer.isReadyForMoreMediaData`. Pure refactor.
**Acceptance:** zero deprecation warnings; capture behavior unchanged.

### Resize aspect-lock fidelity debug

**Status:** 🟢 open · **Parallel-safe:** yes · **Depends on:** reproducible repro from user.
**Touches:** `Overlay/ResizeHandle.swift`, `App/AppDelegate.swift` (`handleFirstFrame`, `clampToOverlayBounds`).
**Symptom:** overlay observed at wrong aspect (square-ish, captured content letterboxed) without `ResizeHandle.mouseDown` firing. Likely candidates: AppKit's auto content-view resize fighting `setFrame` for borderless windows, or `handleFirstFrame` re-firing on a second `onFirstFrame`.
**Scope:** add NSLog at `handleFirstFrame` (input size, computed clampedSize, applied window frame) and at `onFirstFrame` callsite. Have user reproduce. Fix root cause; if it's AppKit auto-resize, force-set `captureView.autoresizingMask` and verify; if it's re-firing, gate with `firstFrameApplied` flag.
**Acceptance:** the wrong-aspect state cannot be reached without dragging the handle.

### Auto-hide per-window precision

**Status:** ⛔ blocked on a per-session window-identity helper (in-memory mapping from `(bundleID, title)` → `CGWindowID` that survives a `NSWorkspace.didActivateApplicationNotification`) · **Parallel-safe:** no.
**Touches:** `Features/SourceVisibility.swift`.
**Scope:** narrow the auto-hide check to require *focused-window-ID match* on the source's app, not just bundleID match. Earlier B1 attempt with `AXFocusedWindow` + `_AXUIElementGetWindow` was buggy in practice; redo against a test matrix (Safari host + fullscreen video, Finder windows across Spaces, Xcode workspace + assistant editor). On-disk persistence was previously contemplated but is no longer required — solve identity in-memory.
**Acceptance:** capturing the fullscreen-video Safari window and switching to a *different* Safari window (e.g. the host tab) does NOT hide the overlay; capturing the host and switching to the host DOES hide it.

### Developer-ID signing + notarization

**Status:** 🟢 open (logistical, not feature work) · **Parallel-safe:** yes · **Depends on:** user has Apple Developer Program membership and a Developer ID Application certificate.
**Touches:** `project.yml` signing config, new `entitlements.plist`, new `tools/notarize.sh`, `README.md` distribution section.
**Scope:** flip ad-hoc → Developer-ID Application; turn on hardened runtime; write `tools/notarize.sh` wrapping `notarytool submit --wait` + `stapler staple`.
**Acceptance:** copying the built `.app` to a separate Mac launches without Gatekeeper blocking.

### Per-PIP media-key forwarding (research)

**Status:** 🟢 open (research / blocked on a delivery primitive) · **Parallel-safe:** yes · **Depends on:** verifying a private-API path before any user-facing work.
**Touches:** would resurrect / replace deleted `Features/MediaKeyForwarder.swift` (commit history has the abandoned attempt); AppDelegate wiring.
**Use case (real but secondary):** Music *and* a YouTube PIP playing at the same time, hover the PIP and press ⏯ to pause *the video specifically* without surfacing Safari. With only one media source on the machine, macOS's native routing already gets the key to YouTube — the feature is purely a multi-source disambiguation.

**Why v1 was abandoned:** the obvious implementation — `CGEventTap` on `NX_SYSDEFINED`, hover-detect the topmost PIP overlay under the cursor, `CGEvent.postToPid(<source app PID>)` — *technically* works (the event arrives at Safari's input queue, log line confirms it), but **does not trigger MediaSession / MPRemoteCommandCenter** in any modern browser. Modern WebKit/Chromium MediaSession is fed by Apple's private MediaRemote IPC, not by NSEvent delivery. Posting `NX_SYSDEFINED` to the PID is exactly the path BeardedSpice et al. used pre-MediaSession; it's stale.

Worse: swallowing the key at our session-level tap is sufficient to block the OS's native MediaRemote routing too (verified live), so a naive forwarder is a **regression** for the single-source case — the OS would have delivered to YouTube correctly if we'd stayed out of the way.

**Workaround paths considered and rejected (or deferred):**
- *MediaRemote private framework with per-app targeting.* `MRMediaRemoteSendCommand(cmd, userInfo)` is well-known but addresses the currently-active media app, not a specific bundle ID. A per-app/per-PID targeting symbol may exist on macOS 15 / 26 (e.g. `MRMediaRemoteSendCommandToApp`-style); **verify by dumping symbols from `/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote` before committing to this path**. If it exists, this is the project-native answer (the project already uses dlsym for `CGWindowListCreateImage`, so the precedent is set).
- *AppleScript `do JavaScript "..." in current tab of window 1`.* Per-browser (Safari / Chrome / Arc / Brave each different), requires the user to enable "Allow JavaScript from Apple Events" in each browser, and "current tab of window 1" targets the *frontmost* tab — which is exactly *not* the PIP'd tab in the headline use case. Mapping `SCWindow.windowID` to AppleScript tab is non-trivial.
- *Activate target app, post key, restore focus.* `NSRunningApplication.activate` is observable as a window-cycling flash. Jarring on a feature whose whole point is invisibility.

**Reusable infrastructure** (lives in the abandoned forwarder for reference): cursor-over-topmost-overlay walk via `NSApp.orderedWindows` + `window.frame.contains(NSEvent.mouseLocation)` (already proven in `AppDelegate.toggleClickThroughUnderCursorViaHotkey`); `CGEventTap` at `.cgSessionEventTap` with `.headInsertEventTap` + `.defaultTap` against mask `1 << 14` (NX_SYSDEFINED) installs cleanly under the existing Accessibility grant; the system disables a slow tap with `kCGEventTapDisabledByTimeout` and the callback must re-arm.

**Acceptance (when revisited):** with Apple Music actively playing AND a YouTube tab in a PIP overlay actively playing, hover the YouTube PIP and press ⏯ — *only* YouTube toggles. Cursor away from the PIP — Music handles the key as today. No visible app-activation flash. No per-browser permission prompts the user has to chase down.

**Origin:** explored 2026-05-11; primary evidence in the abandoned `MediaKeyForwarder.swift` commit and the user-testing transcript ("if i'm not hovered over our PIP, it does play/pause the video. however = nothing").

### DRM-protected video workaround (research only)

**Status:** 🟢 open · **Parallel-safe:** yes · **Depends on:** none.
**Touches:** TBD — depends on findings; possibly new `docs/drm-video-investigation.md`.
**Scope:** investigate whether `AVPictureInPictureController` against an `AVPlayer` pointed at the same HLS stream as Safari's tab can substitute for screen capture for Apple TV+ / Netflix-premium content. If a public-API path exists, plan integration; if not, document the limitation under `docs/` and close.
**Acceptance:** either a working capture path for at least one DRM service, or a definitive writeup of why it isn't possible via public API.

---

## Done (v1)

| Track | Phase | Commit |
|---|---|---|
| Structural refactor + Xcode project shell | A | `3ea79f7` |
| Auto show/hide on source frontmost | B1 | `3ea79f7` |
| Resizable overlay with aspect lock | B2 | `3ea79f7` (caveat tracked above) |
| ⌥-hover click-through | B3 | `3ea79f7` |
| Manual region crop | C1 | `3ea79f7` |
| User-controlled transparency | off-plan | `3ea79f7` |
| ⌥-click pick-and-crop shortcut | off-plan | `3ea79f7` |
| Multiple simultaneous overlays | D | `74b70ec` |
