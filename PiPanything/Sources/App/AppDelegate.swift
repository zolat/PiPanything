//  PiPanything — cross-Space Mac PiP overlay
//  Copyright (C) 2026 Thomas Zola
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.

import Cocoa
import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let coordinator = OverlayCoordinator()
    private(set) var sources = SourceList()
    private var thumbnails: [CGWindowID: NSImage] = [:]
    private var pickerController: PickerWindowController?

    /// Most recent successful capture's windowID *across any session*. Powers
    /// `⌃⌥P` "restart last." Survives stop / session removal — only changes
    /// when a new capture's first frame lands.
    private var lastCapturedWindowID: CGWindowID?

    /// Latched panic-hide state for `⌃⌥H`. Toggled by the hotkey and applied
    /// uniformly to every session so all overlays land in the same hidden /
    /// shown state instead of swapping piecewise.
    private var globalManuallyHidden = false

    private var hotkeysController: HotkeysController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launch with one always-present idle overlay — it's the entry point
        // for the right-click menu and keeps the on-screen UX of v1.
        attachContextMenuBuilder(to: coordinator.add())
        setupHotkeys()

        // Request Accessibility permission so we can detect minimized windows.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        Task {
            await refreshSources()
            if ProcessInfo.processInfo.environment["PIP_AUTO_CAPTURE"] == "1" {
                await autoCaptureLargest()
            }
            if ProcessInfo.processInfo.environment["PIP_OPEN_PICKER"] == "1" {
                openPicker()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeysController?.unregister()
    }

    /// Wires every per-session callback AppDelegate cares about. Called once
    /// per session: at launch (for the entry-point overlay) and inside
    /// `pickWindow` whenever we add a new sibling.
    private func attachContextMenuBuilder(to session: OverlaySession) {
        session.contextMenuBuilder = { [weak self, weak session] event in
            guard let self = self, let session = session else { return }
            self.showContextMenu(for: event, on: session)
        }
        session.onCaptureSucceeded = { [weak self] windowID in
            self?.lastCapturedWindowID = windowID
        }
    }

    private func setupHotkeys() {
        hotkeysController = HotkeysController()
        hotkeysController.onToggleCapture = { [weak self] in
            self?.toggleCaptureViaHotkey()
        }
        hotkeysController.onToggleVisibility = { [weak self] in
            self?.toggleVisibilityViaHotkey()
        }
        hotkeysController.onCycleSource = { [weak self] in
            self?.cycleSourceViaHotkey()
        }
    }

    private static let sessionMenuIDPrefix = "pip.session."

    private func showContextMenu(for event: NSEvent, on session: OverlaySession) {
        guard let view = session.window.contentView else { return }
        let menu = NSMenu()
        // Stash the focused session ID in the menu identifier so menuNeedsUpdate
        // can route to the session-scoped builder without a separate parameter.
        menu.identifier = NSUserInterfaceItemIdentifier(
            rawValue: "\(Self.sessionMenuIDPrefix)\(session.id.value.uuidString)"
        )
        menu.delegate = self
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func focusedSession(for menu: NSMenu) -> OverlaySession? {
        guard let raw = menu.identifier?.rawValue,
              raw.hasPrefix(Self.sessionMenuIDPrefix),
              let uuid = UUID(uuidString: String(raw.dropFirst(Self.sessionMenuIDPrefix.count))) else {
            return nil
        }
        return coordinator.sessions.first(where: { $0.id.value == uuid })
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
        Task {
            await refreshSources()
            rebuildMenu(menu)
        }
    }

    private func refreshSources() async {
        var newSources = await SourceList.refresh()
        if newSources.permissionDenied {
            sources = newSources
            thumbnails = [:]
            broadcastIdleStatus("Screen Recording permission needed — System Settings → Privacy & Security")
            return
        }

        // Generate thumbnails off-main; windows that can't produce one are
        // hidden from the picker (they're not actually capturable right now).
        // Downsample so we don't keep 60 full-resolution CGImages alive.
        let candidateIDs = newSources.windows.map { $0.windowID }
        let target = CGSize(width: 296, height: 168)
        let newThumbs: [CGWindowID: NSImage] = await Task.detached {
            var result: [CGWindowID: NSImage] = [:]
            for id in candidateIDs {
                guard let cg = legacyCaptureWindow(id) else { continue }
                guard cg.width > 1, cg.height > 1 else { continue }
                let downsampled = downsampledCGImage(cg, fittingIn: target) ?? cg
                let displaySize = NSSize(
                    width: CGFloat(downsampled.width) / 2,
                    height: CGFloat(downsampled.height) / 2
                )
                result[id] = NSImage(cgImage: downsampled, size: displaySize)
            }
            return result
        }.value

        newSources.windows = newSources.windows.filter { newThumbs.keys.contains($0.windowID) }
        sources = newSources
        thumbnails = newThumbs

        let axNote = sources.axTrusted ? "" : " · grant Accessibility to hide minimized"
        broadcastIdleStatus("\(sources.windows.count) capturable windows · right-click for menu\(axNote)")

        // If the picker modal is open, push the fresh list/thumbnails through
        // so the grid reflows as windows appear or disappear.
        if let picker = pickerController, picker.isVisible {
            picker.update(
                sources: sources,
                thumbnails: thumbnails,
                capturedWindowIDs: currentlyCapturedWindowIDs(),
                isAtSoftCap: coordinator.isAtSoftCap
            )
        }
    }

    /// Update every currently-idle session's idle-view text. Capturing sessions
    /// don't show the idle view, so they're ignored.
    private func broadcastIdleStatus(_ message: String) {
        for session in coordinator.sessions where !session.isCapturing {
            session.setIdleStatus(message)
        }
    }

    private func rebuildMenu(_ menu: NSMenu) {
        let activeOverlays = coordinator.sessions.map { $0.menuModel() }
        if let focused = focusedSession(for: menu) {
            SourcePickerMenu.populateSessionScoped(
                menu,
                focusedID: focused.id,
                activeOverlays: activeOverlays,
                target: self,
                openPickerAction: #selector(openPicker),
                overlayAction: #selector(handleOverlayMenu(_:)),
                stopAllAction: #selector(stopAll),
                quitAction: #selector(quit)
            )
        } else {
            SourcePickerMenu.populate(
                menu,
                activeOverlays: activeOverlays,
                target: self,
                openPickerAction: #selector(openPicker),
                overlayAction: #selector(handleOverlayMenu(_:)),
                stopAllAction: #selector(stopAll),
                quitAction: #selector(quit)
            )
        }
    }

    // MARK: - Pick semantics

    /// Picking always *adds* a new overlay — except when an idle overlay is
    /// already present, in which case the most-recently-added idle one is
    /// filled. This lets the launch experience feel single-window while every
    /// subsequent pick spawns alongside.
    ///
    /// Resolves the session that should host a new pick: prefer a free idle
    /// session, otherwise spawn a fresh one (cascade-positioned).
    private func targetForNewCapture() -> OverlaySession {
        if let idle = coordinator.sessions.last(where: { !$0.isCapturing }) {
            return idle
        }
        let fresh = coordinator.add()
        attachContextMenuBuilder(to: fresh)
        return fresh
    }

    private func pickInto(_ target: OverlaySession, window: SCWindow, cropImmediately: Bool = false) {
        // Newly-picked overlay should not stay panic-hidden if the user had
        // toggled the global hide off-screen.
        target.visibility.setManualHide(globalManuallyHidden)
        target.start(window: window, cropImmediately: cropImmediately)
    }

    // MARK: - Picker modal

    @objc func openPicker() {
        let controller = pickerController ?? PickerWindowController()
        if pickerController == nil {
            controller.onPick = { [weak self] window, cropImmediately in
                guard let self = self else { return }
                self.pickInto(self.targetForNewCapture(), window: window, cropImmediately: cropImmediately)
            }
            pickerController = controller
        }
        controller.show(
            sources: sources,
            thumbnails: thumbnails,
            capturedWindowIDs: currentlyCapturedWindowIDs(),
            isAtSoftCap: coordinator.isAtSoftCap
        )
        // Kick a fresh refresh so thumbnails update under the user as the
        // window list moves (e.g., they switched apps just before opening).
        Task { await refreshSources() }
    }

    private func currentlyCapturedWindowIDs() -> Set<CGWindowID> {
        Set(coordinator.sessions.compactMap { $0.capturedWindowID })
    }

    // MARK: - Per-overlay action dispatch

    @objc func handleOverlayMenu(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? OverlayMenuTag,
              let session = coordinator.session(id: tag.id) else { return }
        switch tag.action {
        case .stop:
            // Stopping the only session returns it to idle (it's the entry
            // point — closing it would orphan the user). Stopping any other
            // session removes it entirely so dead windows don't pile up.
            if coordinator.sessions.count == 1 {
                session.stop()
            } else {
                coordinator.remove(tag.id)
            }
        case .setCrop:
            session.beginCropSelection()
        case .clearCrop:
            session.clearCrop()
        case .toggleAutoHide:
            session.autoHide.toggle()
        case .setOpacity(let pct):
            let clamped = max(10, min(100, pct))
            session.opacity = CGFloat(clamped) / 100.0
        }
    }

    @objc func stopAll() {
        // Stop everything; remove sibling sessions, leave the entry-point one
        // standing so the user can still right-click it.
        let primaryID = coordinator.sessions.first?.id
        for session in coordinator.sessions {
            session.stop()
        }
        for session in coordinator.sessions where session.id != primaryID {
            coordinator.remove(session.id)
        }
    }

    @objc func quit() { NSApp.terminate(nil) }

    // MARK: - Hotkey handlers

    /// `⌃⌥P` — if anything is capturing anywhere, panic-stop everything (same
    /// semantics as menu's "Stop all"). Otherwise restart the most recent
    /// capture into the primary slot. Multi-overlay extension of v1's
    /// "stop / restart last" toggle.
    private func toggleCaptureViaHotkey() {
        if coordinator.sessions.contains(where: { $0.isCapturing }) {
            stopAll()
            return
        }
        guard let id = lastCapturedWindowID,
              let win = sources.windows.first(where: { $0.windowID == id }) else {
            NSLog("PiPanything: ⌃⌥P pressed but no in-session source to restore")
            return
        }
        pickInto(targetForNewCapture(), window: win)
    }

    /// `⌃⌥H` — panic show/hide every overlay at once. Tracks one app-level
    /// flag and applies it to each session so partial-state UIs (one hidden,
    /// one shown) collapse into the same state on each press.
    private func toggleVisibilityViaHotkey() {
        globalManuallyHidden.toggle()
        for session in coordinator.sessions {
            session.visibility.setManualHide(globalManuallyHidden)
        }
    }

    /// `⌃⌥N` — cycle the primary session's source to the next pickable window.
    /// Picks into primary specifically (not adding a new overlay) — this hotkey
    /// is for "I want to flip the channel I'm watching", not "spawn another."
    private func cycleSourceViaHotkey() {
        Task {
            await refreshSources()
            guard !sources.windows.isEmpty else {
                NSLog("PiPanything: ⌃⌥N pressed but no capturable windows")
                return
            }
            let primary = coordinator.sessions.first ?? targetForNewCapture()
            let next: SCWindow
            if let current = primary.capturedWindowID,
               let idx = sources.windows.firstIndex(where: { $0.windowID == current }) {
                next = sources.windows[(idx + 1) % sources.windows.count]
            } else {
                next = sources.windows[0]
            }
            pickInto(primary, window: next)
        }
    }

    // MARK: - Auto-capture (env var hook for smoke tests)

    /// `PIP_AUTO_CAPTURE=1` picks the largest window. Set
    /// `PIP_AUTO_CAPTURE_COUNT=N` to spawn the N largest as separate overlays
    /// — useful for multi-overlay smoke verification. Set
    /// `PIP_TEST_STOP_INDEX=k` to additionally invoke the `Stop` overlay
    /// action on session at index `k` (0-based) ~3s after spawn, exercising
    /// the `OverlayMenuTag → handleOverlayMenu → coordinator.remove` chain.
    private func autoCaptureLargest() async {
        let countEnv = ProcessInfo.processInfo.environment["PIP_AUTO_CAPTURE_COUNT"]
        let count = max(1, Int(countEnv ?? "") ?? 1)
        let largest = sources.windows.sorted(by: { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height })
        guard !largest.isEmpty else {
            NSLog("PiPanything: PIP_AUTO_CAPTURE set but no windows available")
            return
        }
        // Distinct windows by ID (defensive).
        var seen = Set<CGWindowID>()
        let picks = largest.filter { seen.insert($0.windowID).inserted }.prefix(count)
        for win in picks {
            NSLog("PiPanything: auto-capturing \(win.owningApplication?.applicationName ?? "?") — \(win.title ?? "")")
            // Route through the same pickWindow path so cascade + add-vs-fill
            // semantics are exercised exactly as the user's clicks would.
            pickInto(targetForNewCapture(), window: win)
            // Small gap so the first capture's first-frame resize lands before
            // the next session spawns next to it.
            try? await Task.sleep(nanoseconds: 600_000_000)
        }

        if let raw = ProcessInfo.processInfo.environment["PIP_TEST_STOP_INDEX"],
           let idx = Int(raw),
           coordinator.sessions.indices.contains(idx) {
            // Wait for the spawned sessions to settle, then synthesize the
            // Stop click as if it came from a menu item — same code path the
            // user's click uses.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let target = coordinator.sessions[idx]
            let preCount = coordinator.sessions.count
            NSLog("PIP_TEST_STOP: stopping session at index \(idx) (id=\(target.id), capturing windowID=\(target.capturedWindowID.map(String.init) ?? "nil"))")
            let item = NSMenuItem(title: "Stop", action: #selector(handleOverlayMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = OverlayMenuTag(target.id, .stop)
            handleOverlayMenu(item)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let postCount = coordinator.sessions.count
            NSLog("PIP_TEST_STOP: dispatch complete. sessions \(preCount) → \(postCount). still has session id=\(target.id)? \(coordinator.session(id: target.id) != nil)")
        }
    }
}
