# PiPanything — Claude project notes

This file is read by Claude Code at session start. It captures stable
knowledge about the project so a fresh session (yours, mine, a sibling
running in parallel) can be productive immediately.

Companion docs:
- `BACKLOG.md` — live cross-session task board. Read this to find work.
- `~/.claude/plans/i-think-we-proven-purrfect-scone.md` — long-form plan
  with the *why*. Read this before re-planning a Phase D track.

## What this app is

PiPanything is a Mac picture-in-picture overlay that floats over
*other apps' full-screen Spaces*. It captures any window via
`ScreenCaptureKit` when the source is on the active Space, and via a
`dlsym`-loaded `CGWindowListCreateImage` polling fallback when the
source is on a different Space (e.g. a fullscreen Safari YouTube tab
while the user is in a different fullscreen app).

Headline use case: keep a YouTube tab visible across Spaces.

## Build / run

```sh
xcodegen generate                                       # rebuild .xcodeproj from project.yml
xcodebuild -scheme PiPanything -configuration Debug build
APP=$(xcodebuild -showBuildSettings -scheme PiPanything 2>/dev/null \
  | awk '/BUILT_PRODUCTS_DIR/ {print $3}')
"$APP/PiPanything.app/Contents/MacOS/PiPanything"       # run
```

`.xcodeproj` is **gitignored** — regenerate from `project.yml` after a clone.

Environment knob for headless verification:
- `PIP_AUTO_CAPTURE=1` — auto-pick the largest non-self window at launch.

Permissions on first launch (TCC will prompt; binary path inside the
`.app` bundle is stable, so the grant survives rebuilds):
1. Screen Recording — required.
2. Accessibility — required for the AX-minimized filter and global
   modifier monitor.

## Architecture

```
PiPanything/
├── project.yml                 xcodegen spec; single app target
├── PiPanything/
│   ├── Info.plist              LSUIElement, NSScreenCaptureDescription
│   └── Sources/
│       ├── App/
│       │   ├── PiPanythingApp.swift    @main, MainActor.assumeIsolated bootstrap
│       │   └── AppDelegate.swift       Top-level glue / orchestration
│       ├── Capture/
│       │   ├── CaptureManager.swift    SCStream + polling pipeline, CaptureMode enum
│       │   ├── CGCompat.swift          dlsym CGWindowListCreateImage + downsample
│       │   └── AccessibilityHelpers.swift  _AXUIElementGetWindow, minimizedWindowIDs
│       ├── Overlay/
│       │   ├── OverlayWindow.swift     Borderless NSWindow w/ rightMouseDown hook
│       │   ├── IdleView.swift          Gradient + clock idle state
│       │   ├── CaptureView.swift       Dual-layer renderer + crop frame translate
│       │   └── ResizeHandle.swift      Bottom-right corner grip
│       ├── Picker/
│       │   ├── SourceList.swift        SCShareableContent + filter pipeline
│       │   ├── SourcePickerMenu.swift  NSMenu population (right-click context)
│       │   └── PickerRowView.swift     Custom NSMenuItem.view w/ thumbnail
│       └── Features/
│           ├── SourceVisibility.swift  Auto show/hide on NSWorkspace activation
│           ├── ClickThrough.swift      ⌥-hover ignoreMouseEvents + base alpha
│           └── CropRegion.swift        Marquee selection view
```

Single ownership chain: `PiPanythingApp` → `AppDelegate` (the only
`@MainActor` orchestrator) → `OverlayWindow`, `CaptureManager`, the
three feature controllers, and the views.

`CaptureManager` exposes its layers (`displayLayer`, `imageLayer`)
publicly so `CaptureView` can render them; everything else is callbacks
(`onFirstFrame`, `onModeChange`, `onError`).

## Cross-cutting gotchas

These are the bits that bit us; check them before re-implementing
similar pieces.

1. **`AVSampleBufferDisplayLayer.contentsRect` is ignored for video.**
   Setting it has no effect on the displayed frame. Use the
   layer-frame translate trick instead: scale the layer's frame to
   `bounds / cropSize` and offset by `-cropOrigin × scaledSize`, with
   `captureView.layer.masksToBounds = true` clipping. See
   `CaptureView.updateLayerFrames`.

2. **`CGWindowListCreateImage` is `__API_UNAVAILABLE` in the macOS 15
   SDK** but the symbol still ships in CoreGraphics. Load it via
   `dlsym` against the CoreGraphics framework path. See
   `Capture/CGCompat.swift`. This is the only public path for capturing
   windows on a non-active Space.

3. **`isMovableByWindowBackground = true` swallows drags.** Any subview
   that needs `mouseDown` / `mouseDragged` (resize handle, crop
   selection view, future picker overlays) MUST override
   `mouseDownCanMoveWindow` to return `false`, otherwise the window's
   drag-to-move steals the gesture before the view sees it.

4. **`isOnScreen` conflates "minimized" with "on a non-current Space".**
   Filtering by it makes cross-Space sources disappear from the picker.
   Use the AX-based `AXMinimized` check via
   `_AXUIElementGetWindow` instead. See `Picker/SourceList.swift`.

5. **`CGWindowListCreateImage` returning nil is the right filter for
   "this source can't actually be captured right now".** The picker
   generates a thumbnail per candidate window during refresh and hides
   any source that returns nil — covers minimized, hardware-rendered,
   and (most importantly) DRM-protected content silently.

6. **Top-level Swift code ≠ `@MainActor`.** The bootstrap uses
   `MainActor.assumeIsolated { … }` to run the AppKit init on the main
   actor without making the file's top-level code formally isolated.
   Keep that pattern; don't `@main` the AppDelegate directly.

7. **`NSEvent.modifierFlags` over accumulated `.flagsChanged` state.**
   The global modifier-monitor occasionally drops release events when
   the cursor crosses app boundaries. Always read
   `NSEvent.modifierFlags` directly inside the event handler instead of
   tracking key-down/key-up bookkeeping. See
   `Features/ClickThrough.swift`.

## Conventions

- **Files are small and single-purpose.** If a file exceeds ~200 lines,
  split it. We came in from a 593-line `main.swift`; don't go back.
- **`@MainActor` only on `AppDelegate` and the feature controllers.**
  `CaptureManager` is `@MainActor` because it owns AppKit-typed layers
  and the run loop's polling timer; everything below it is plain Swift.
- **Logging.** All NSLog lines start with `PiPanything: ` so they're
  greppable in `/tmp/pipanything.log` (the convention used in the dev
  loop).
- **Public state on managers is `private(set)`.** External code reads
  `captureManager.cropRect`, `…isCapturing`, `…capturedSourceBundle`,
  but only the manager itself can write.

## Distribution status

Currently **ad-hoc signed**. Builds and runs on the dev machine, but
Gatekeeper will block when copied to a different Mac. Real distribution
is gated on the *Developer-ID signing + notarization* track in
`BACKLOG.md`.

App Store sandbox is **not** a target — the `dlsym` `CGWindowListCreateImage`
path and the AX-private `_AXUIElementGetWindow` symbol both block App
Store review. Direct distribution only.
