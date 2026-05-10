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
| Persistent picker | 🟢 | yes |
| Global hotkeys | 🟢 | yes |
| Safari extension + URL deep link | 🟢 | yes |
| `sampleBufferRenderer` deprecation cleanup | 🟢 | yes |
| Resize aspect-lock fidelity debug | 🟢 | yes |
| Developer-ID signing + notarization | 🟢 | yes (logistical) |
| DRM video workaround (research only) | 🟢 | yes |
| Auto-hide per-window precision | ⛔ | no — wait for persistent picker |
| Multiple simultaneous overlays | ⛔ | no — architectural; do last |

---

## Tracks

### Persistent picker

**Status:** 🟢 open · **Parallel-safe:** yes · **Depends on:** none.
**Touches:** new `Features/SourcePersistence.swift`, `App/AppDelegate.swift` hooks on first frame and on stop.
**Scope:** persist source bundleID + window-title hash to `UserDefaults`. On launch, if a saved source maps to a currently-capturable window in the picker list, kick off the capture automatically. Adds an "Auto-restore last source" toggle in the right-click menu (default **off** to avoid surprise on launch; opt-in).
**Acceptance:** quit while a source is active, relaunch, capture resumes within 2 s if the source is still capturable; silent fallback to idle if not.

### Global hotkeys (start/stop, hide, cycle source)

**Status:** 🟢 open · **Parallel-safe:** yes · **Depends on:** none.
**Touches:** new `Features/Hotkeys.swift`. Use `Carbon.HotKey` API directly or vendor `MASShortcut` (single-file copy is fine).
**Scope:** three defaults — `⌃⌥P` toggle capture (stop / restart last), `⌃⌥H` toggle overlay visibility, `⌃⌥N` cycle sources from the current picker list. No customization UI yet; constants in code.
**Acceptance:** shortcuts fire even when other apps are frontmost; do not steal keys when typing in a text field elsewhere; on `applicationWillTerminate`, hotkeys are unregistered cleanly.

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

**Status:** ⛔ blocked on **Persistent picker** (so we can stably store a window identity over time) · **Parallel-safe:** no.
**Touches:** `Features/SourceVisibility.swift`.
**Scope:** narrow the auto-hide check to require *focused-window-ID match* on the source's app, not just bundleID match. Earlier B1 attempt with `AXFocusedWindow` + `_AXUIElementGetWindow` was buggy in practice; redo against a test matrix (Safari host + fullscreen video, Finder windows across Spaces, Xcode workspace + assistant editor).
**Acceptance:** capturing the fullscreen-video Safari window and switching to a *different* Safari window (e.g. the host tab) does NOT hide the overlay; capturing the host and switching to the host DOES hide it.

### Multiple simultaneous overlays

**Status:** ⛔ blocked on **Persistent picker** + **Auto-hide per-window precision** · **Parallel-safe:** no — architectural.
**Touches:** large refactor of `AppDelegate` from a single `(OverlayWindow, CaptureManager, CaptureView)` triple to a coordinator over many; menu structure becomes per-overlay submenus.
**Scope:** support 2–3 concurrent overlays (YouTube + Slack + Slack thread). Each independently auto-hides on its source. Each gets its own crop / opacity.
**Acceptance:** two captures running, both render, quit one source → that overlay swaps to idle while the other keeps streaming.

### Developer-ID signing + notarization

**Status:** 🟢 open (logistical, not feature work) · **Parallel-safe:** yes · **Depends on:** user has Apple Developer Program membership and a Developer ID Application certificate.
**Touches:** `project.yml` signing config, new `entitlements.plist`, new `tools/notarize.sh`, `README.md` distribution section.
**Scope:** flip ad-hoc → Developer-ID Application; turn on hardened runtime; write `tools/notarize.sh` wrapping `notarytool submit --wait` + `stapler staple`.
**Acceptance:** copying the built `.app` to a separate Mac launches without Gatekeeper blocking.

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
