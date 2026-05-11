# PiPanything

**Cross-Space picture-in-picture overlays for macOS.** Pin any window — a YouTube tab, a video call, a terminal — on top of any other app, including full-screen Spaces.

PiPanything is the missing companion to macOS full-screen mode and Spaces. When you go full-screen into one app and want a small live view of another window stuck in the corner, it puts it there — and keeps it there even when the source window's Space isn't currently on screen.

The headline use case: keeping a YouTube tab visible while you work full-screen in another app.

## What you can do

- **Pin any window** as a floating PiP — Safari tab, video player, Slack call, terminal, anything macOS will let you record.
- **Stays visible across Spaces**, including full-screen apps. Switch into full-screen Xcode and your YouTube tab is still in the corner.
- **Run multiple overlays at once** (up to four), cascaded down-and-right.
- **Crop** to just the part of the window you care about — the player area, the chat panel, the speaker tile.
- **Click-through latch** (right-click → Click-through, or `⌥T` / `⌃⌥T`) makes the overlay transparent to mouse input and dims it down to as low as 10%, so you can keep working in the app behind it.
- **Auto-hide** when the source app loses focus, either per-overlay or as a default for new overlays.
- **Adjust opacity** to taste, per overlay or globally.
- **Global hotkeys** for show/hide, stop/restart, and cycling source.

## Status

Alpha. Builds from source on macOS 13+. Currently ad-hoc signed — works fine on the machine that built it, but Gatekeeper will block it on any other Mac. Distributable Developer-ID-signed and notarised builds are on the roadmap.

App Store distribution is intentionally not pursued: the cross-Space capture path relies on private and legacy framework calls that App Review wouldn't accept. Direct distribution only.

## Build & run

One-time: install [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
```

Then, from the repo root:

```sh
xcodegen generate
xcodebuild -scheme PiPanything -configuration Debug build
APP=$(xcodebuild -showBuildSettings -scheme PiPanything 2>/dev/null \
  | awk '/ BUILT_PRODUCTS_DIR/ {print $3}')
open "$APP/PiPanything.app"
```

The Xcode project is regenerated from `project.yml` each time, so feel free to delete `PiPanything.xcodeproj` and re-run `xcodegen generate` if anything looks stale.

## Permissions on first launch

macOS will prompt for two things. Both are required.

1. **Screen Recording** — to capture the contents of the source window.
2. **Accessibility** — to detect minimised windows and listen for global hotkeys.

The app's code signature is stable across rebuilds, so the permission grants survive recompilation.

## Using it

Look for the **rectangle-on-rectangle icon in the menu bar**. From there:

- **Pick window…** — opens a grid of every capturable window. Click to pin; `⌥`-click to pin and immediately drop into crop mode.
- **Active overlays** are listed at the top of the menu with per-overlay submenus (stop, crop, auto-hide, transparency).
- **Stop all** kills every overlay in one go.
- **Default opacity**, **max overlay size**, **click-through opacity** (10–100%), **auto-hide new overlays**, and **launch at login** are global preferences for new overlays.

### On an overlay itself

- **Drag** anywhere to move it.
- **Resize** from the bottom-right corner.
- **Right-click** for the same per-overlay menu (stop, crop, opacity, auto-hide, click-through).
- **Click-through latch** dims the overlay (configurable, default 70%, down to 10%) and lets the mouse pass through to whatever is underneath. Toggle via the right-click menu, `⌥T` (the overlay under the cursor), or `⌃⌥T` (every overlay at once).

### Global hotkeys

| Shortcut | Effect |
|---|---|
| `⌃⌥P` | Toggle capture — panic-stop every overlay, or restart the most recent if nothing is capturing. |
| `⌃⌥H` | Show / hide all overlays without stopping them. |
| `⌃⌥N` | Cycle the primary overlay through other capturable windows. |
| `⌥T` | Toggle click-through latch on the overlay under the cursor. |
| `⌃⌥T` | Toggle click-through latch on every overlay (any on → all off; else all on). |

## License

GPLv3. See [`LICENSE`](LICENSE). PiPanything is a standalone end-user app, so reciprocity is the desired default — modifications and derivative works stay open.
