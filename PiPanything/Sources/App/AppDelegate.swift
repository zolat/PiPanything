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
    private var statusBar: StatusBarController?
    private var controlServer: ControlServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launch with one always-present idle overlay — it's the entry point
        // for the right-click menu and keeps the on-screen UX of v1.
        let entry = coordinator.add()
        applyDefaults(to: entry)
        attachContextMenuBuilder(to: entry)
        setupHotkeys()
        statusBar = StatusBarController(appDelegate: self)
        startControlServerIfEnabled()

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
        controlServer?.stop()
    }

    /// Add a fresh overlay session and bring it to the same configured
    /// state as the entry-point overlay (defaults applied, context-menu
    /// builder attached). Used by the control surface and any future
    /// caller that needs a new overlay outside the picker flow.
    func addConfiguredSession() -> OverlaySession {
        let session = coordinator.add()
        applyDefaults(to: session)
        attachContextMenuBuilder(to: session)
        return session
    }

    private func startControlServerIfEnabled() {
        guard ProcessInfo.processInfo.environment["PIP_CONTROL_SERVER"] == "1" else { return }
        let server = ControlServer()
        server.appDelegate = self
        do {
            try server.start()
            controlServer = server
        } catch {
            NSLog("PiPanything: control server failed to start: \(error)")
        }
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
        hotkeysController.onToggleClickThrough = { [weak self] in
            self?.toggleClickThroughViaHotkey()
        }
        hotkeysController.onToggleClickThroughUnderCursor = { [weak self] in
            self?.toggleClickThroughUnderCursorViaHotkey()
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
                addTabAction: #selector(openPickerForAddTab(_:)),
                setWindowAction: #selector(openPickerForSetWindow(_:)),
                overlayAction: #selector(handleOverlayMenu(_:)),
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
        // Skip minimized sessions — those are parked deliberately; opening
        // the picker shouldn't unintentionally fill them and lose the parked
        // tabs. Spawn a fresh overlay instead.
        if let idle = coordinator.sessions.last(where: { !$0.isCapturing && !$0.isMinimized }) {
            return idle
        }
        let fresh = coordinator.add()
        applyDefaults(to: fresh)
        attachContextMenuBuilder(to: fresh)
        return fresh
    }

    /// Apply user-configured starting values from `Settings` to a freshly
    /// minted session. Existing sessions are intentionally left alone — the
    /// status menu's "Default opacity / Auto-hide" entries are *defaults*, not
    /// global toggles, so changing them shouldn't yank live overlays around.
    private func applyDefaults(to session: OverlaySession) {
        session.opacity = CGFloat(Settings.shared.defaultOpacityPercent) / 100.0
        session.autoHide = Settings.shared.autoHideDefault
    }

    private func pickInto(_ target: OverlaySession, window: SCWindow, cropImmediately: Bool = false) {
        // Newly-picked overlay should not stay panic-hidden if the user had
        // toggled the global hide off-screen.
        target.visibility.setManualHide(globalManuallyHidden)
        target.start(window: window, cropImmediately: cropImmediately)
    }

    // MARK: - Picker modal

    @objc func openPicker() {
        // Default flow: pick → fill an idle session, or spawn a new one.
        openPickerWithCallback { [weak self] window, cropImmediately in
            guard let self = self else { return }
            self.pickInto(self.targetForNewCapture(), window: window, cropImmediately: cropImmediately)
        }
    }

    /// Right-click → "Add tab here…": opens the picker scoped to a specific
    /// session. The selected window joins that session as a tab via
    /// `OverlaySession.addTab`. The session ID rides on the menu item's
    /// `representedObject`.
    @objc func openPickerForAddTab(_ sender: NSMenuItem) {
        guard let sessionID = sender.representedObject as? OverlayID,
              let session = coordinator.session(id: sessionID) else { return }
        openPickerWithCallback { [weak session] window, cropImmediately in
            session?.addTab(window: window, cropImmediately: cropImmediately)
        }
    }

    /// Right-click → "Set window…": opens the picker scoped to a specific
    /// session. The selected window replaces the active tab's source in
    /// place via `OverlaySession.setActiveSource` — no new tab, no new
    /// overlay. The session ID rides on the menu item's `representedObject`.
    @objc func openPickerForSetWindow(_ sender: NSMenuItem) {
        guard let sessionID = sender.representedObject as? OverlayID,
              let session = coordinator.session(id: sessionID) else { return }
        openPickerWithCallback { [weak session] window, cropImmediately in
            session?.setActiveSource(window: window, cropImmediately: cropImmediately)
        }
    }

    /// Internal: open the picker with a per-show `onPick` callback. Avoids
    /// the singleton-callback-set-once trap so different call sites can
    /// route picks to different destinations (default flow vs add-tab).
    private func openPickerWithCallback(_ callback: @escaping (SCWindow, Bool) -> Void) {
        let controller = pickerController ?? PickerWindowController()
        pickerController = controller
        controller.onPick = callback   // overwrite each show
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
        // For tabbed overlays, flatten across tabs so the picker shows the
        // bullet on every source any tab is currently capturing.
        var ids: Set<CGWindowID> = []
        for session in coordinator.sessions {
            for tab in session.tabs {
                if let id = tab.capturedWindowID { ids.insert(id) }
            }
        }
        return ids
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
        case .toggleClickThrough:
            session.clickThroughLatched.toggle()
        case .setOpacity(let pct):
            let clamped = max(10, min(100, pct))
            session.opacity = CGFloat(clamped) / 100.0
        case .closeTab(let tabID):
            session.closeTab(tabID)
        case .switchTab(let tabID):
            session.switchTo(tabID)
        case .tearOutTab(let tabID):
            tearOutTab(tabID, from: session)
        case .moveTabTo(let tabID, let targetSessionID):
            moveTab(tabID, from: session, to: targetSessionID)
        case .bringSourceToFront:
            session.activateActiveSource()
        case .minimize:
            session.minimize()
        case .restoreFromMinimized:
            // Refresh the source list before resolving so just-opened source
            // windows are findable. The session's own restore call handles
            // missing-source fallback (status message + idle view).
            Task { [weak self, weak session] in
                guard let self = self, let session = session else { return }
                await self.refreshSources()
                session.restoreFromMinimized(windows: self.sources.windows) { missing in
                    NSLog("PiPanything: restore — source not found for \(missing)")
                }
            }
        }
    }

    /// Pop a tab out of its session into a brand-new overlay window. Mirrors
    /// the "Pick" flow: stop the tab in the source session, spawn a new
    /// session via the coordinator's cascade, and start the same source on
    /// the new session's first tab.
    private func tearOutTab(_ tabID: OverlayTabID, from source: OverlaySession) {
        guard let tab = source.tabs.first(where: { $0.id == tabID }),
              let windowID = tab.capturedWindowID,
              let scWindow = sources.windows.first(where: { $0.windowID == windowID }) else {
            NSLog("PiPanything: tearOut — tab \(tabID) not found or its source is gone")
            return
        }
        source.closeTab(tabID)
        let fresh = coordinator.add()
        applyDefaults(to: fresh)
        attachContextMenuBuilder(to: fresh)
        fresh.addTab(window: scWindow)
    }

    /// Move a tab from one session to another. Same restart pattern as
    /// tear-out — the SCStream re-binds in the destination session.
    private func moveTab(_ tabID: OverlayTabID, from source: OverlaySession, to targetID: OverlayID) {
        guard let target = coordinator.session(id: targetID), target.id != source.id,
              let tab = source.tabs.first(where: { $0.id == tabID }),
              let windowID = tab.capturedWindowID,
              let scWindow = sources.windows.first(where: { $0.windowID == windowID }) else {
            NSLog("PiPanything: moveTab — invalid source/target/tab combination")
            return
        }
        source.closeTab(tabID)
        target.addTab(window: scWindow)
    }

    /// Push a new max-dimension cap to every live session so a settings
    /// change takes effect immediately — including shrinking any overlay
    /// already larger than the new cap.
    func applyMaxDimensionToAllSessions(_ dimension: Int) {
        for session in coordinator.sessions {
            session.applyMaxDimension(dimension)
        }
    }

    /// Push the new click-through opacity to every live session so any
    /// currently-latched overlay re-applies its alpha at the new factor.
    /// Idempotent for un-latched sessions (alpha = baseAlpha * 1.0 either
    /// way), so no need to filter.
    func applyClickThroughOpacityToAllSessions() {
        for session in coordinator.sessions {
            session.clickThrough.reapply()
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

    /// `⌃⌥T` — flip every overlay's click-through latch to a uniform state.
    /// If any are on, turn them all off; otherwise turn them all on. Same
    /// "any on → all off" shape as `toggleCaptureViaHotkey`.
    private func toggleClickThroughViaHotkey() {
        let anyOn = coordinator.sessions.contains(where: { $0.clickThroughLatched })
        let target = !anyOn
        for session in coordinator.sessions {
            session.clickThroughLatched = target
        }
    }

    /// `⌥T` — toggle the latch on the topmost overlay under the cursor.
    /// Walks `NSApp.orderedWindows` front-to-back so overlapping overlays
    /// resolve cleanly. No-op if the cursor isn't over one of our overlays.
    private func toggleClickThroughUnderCursorViaHotkey() {
        let mouse = NSEvent.mouseLocation
        for window in NSApp.orderedWindows {
            guard window.isVisible, window.frame.contains(mouse) else { continue }
            if let session = coordinator.sessions.first(where: { $0.window === window }) {
                session.clickThroughLatched.toggle()
                return
            }
        }
        NSLog("PiPanything: ⌥T pressed but cursor isn't over any overlay")
    }

    /// `⌃⌥N` — multi-purpose cycler tied to the primary session:
    ///   • If primary is tabbed (≥2 tabs), switch to the next tab.
    ///   • Otherwise, cycle the active capture's source to the next pickable
    ///     window (v1's behavior).
    /// Picks into primary specifically (not adding a new overlay) — this
    /// hotkey is for "flip what I'm watching," not "spawn another."
    private func cycleSourceViaHotkey() {
        let primary = coordinator.sessions.first ?? targetForNewCapture()
        if primary.tabs.count >= 2 {
            // Cycle through tabs.
            let activeIdx = primary.tabs.firstIndex(where: { $0.id == primary.activeTabID }) ?? 0
            let next = primary.tabs[(activeIdx + 1) % primary.tabs.count]
            primary.switchTo(next.id)
            return
        }
        Task {
            await refreshSources()
            guard !sources.windows.isEmpty else {
                NSLog("PiPanything: ⌃⌥N pressed but no capturable windows")
                return
            }
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

        if let raw = ProcessInfo.processInfo.environment["PIP_TEST_ADD_TABS"],
           let extra = Int(raw),
           extra > 0,
           let primary = coordinator.sessions.first {
            // Wait for the first auto-capture to settle, then add `extra`
            // tabs to the primary session — same code path Phase 3's
            // "Add tab here…" picker callback will use.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let candidates = Array(largest.dropFirst(picks.count).prefix(extra))
            for win in candidates {
                NSLog("PIP_TEST_ADD_TABS: adding tab \(win.owningApplication?.applicationName ?? "?") to primary session")
                primary.addTab(window: win)
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            NSLog("PIP_TEST_ADD_TABS: primary now has \(primary.tabs.count) tabs")
        }

        // Test hook: close tab at 1-based index in primary via the menu
        // dispatch chain (OverlayMenuTag.closeTab → handleOverlayMenu →
        // session.closeTab) — same path the right-click menu's "Other tabs →
        // Close" item takes.
        if let raw = ProcessInfo.processInfo.environment["PIP_TEST_CLOSE_TAB"],
           let idx = Int(raw),
           let primary = coordinator.sessions.first,
           idx >= 1, idx <= primary.tabs.count {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let target = primary.tabs[idx - 1]
            let preCount = primary.tabs.count
            NSLog("PIP_TEST_CLOSE_TAB: closing tab at index \(idx) (id=\(target.id))")
            let item = NSMenuItem(title: "Close", action: #selector(handleOverlayMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = OverlayMenuTag(primary.id, .closeTab(target.id))
            handleOverlayMenu(item)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let postCount = primary.tabs.count
            NSLog("PIP_TEST_CLOSE_TAB: dispatch complete. tabs \(preCount) → \(postCount). still has tab id=\(target.id)? \(primary.tabs.contains(where: { $0.id == target.id }))")
        }

        // Test hook: tear-out tab at 1-based index in primary into a new
        // session via the menu dispatch chain.
        if let raw = ProcessInfo.processInfo.environment["PIP_TEST_TEAR_OUT_TAB"],
           let idx = Int(raw),
           let primary = coordinator.sessions.first,
           idx >= 1, idx <= primary.tabs.count {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let target = primary.tabs[idx - 1]
            let preSessions = coordinator.sessions.count
            let preTabs = primary.tabs.count
            NSLog("PIP_TEST_TEAR_OUT_TAB: tearing out tab \(idx) (id=\(target.id)) from primary")
            let item = NSMenuItem(title: "Tear", action: #selector(handleOverlayMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = OverlayMenuTag(primary.id, .tearOutTab(target.id))
            handleOverlayMenu(item)
            try? await Task.sleep(nanoseconds: 700_000_000)
            NSLog("PIP_TEST_TEAR_OUT_TAB: dispatch complete. sessions \(preSessions) → \(coordinator.sessions.count). primary tabs \(preTabs) → \(primary.tabs.count)")
        }

        // Test hook: switch to a specific tab in primary by 1-based index.
        if let raw = ProcessInfo.processInfo.environment["PIP_TEST_SWITCH_TAB"],
           let idx = Int(raw),
           let primary = coordinator.sessions.first,
           idx >= 1, idx <= primary.tabs.count {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let target = primary.tabs[idx - 1]
            NSLog("PIP_TEST_SWITCH_TAB: switching primary's active tab to index \(idx) (id=\(target.id))")
            primary.switchTo(target.id)
            try? await Task.sleep(nanoseconds: 300_000_000)
            NSLog("PIP_TEST_SWITCH_TAB: now active=\(primary.activeTabID?.description ?? "nil") capturedWindowID=\(primary.capturedWindowID.map(String.init) ?? "nil")")
        }

        // Test hook: replace the primary session's active source with the
        // Nth-largest window via the same call path the right-click "Set
        // window…" picker callback uses. Verifies the in-place swap (prior
        // SCStream torn down, new one started, no extra tab spawned).
        if let raw = ProcessInfo.processInfo.environment["PIP_TEST_SET_WINDOW_INDEX"],
           let idx = Int(raw),
           let primary = coordinator.sessions.first,
           idx >= 1, idx <= largest.count {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let target = largest[idx - 1]
            let preWindowID = primary.capturedWindowID
            let preTabCount = primary.tabs.count
            NSLog("PIP_TEST_SET_WINDOW: swapping active source to index \(idx) (windowID=\(target.windowID) \(target.owningApplication?.applicationName ?? "?") — \(target.title ?? ""))")
            primary.setActiveSource(window: target)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let postWindowID = primary.capturedWindowID
            NSLog("PIP_TEST_SET_WINDOW: dispatch complete. capturedWindowID \(preWindowID.map(String.init) ?? "nil") → \(postWindowID.map(String.init) ?? "nil"). tabs \(preTabCount) → \(primary.tabs.count) (should be unchanged)")
        }

        // Test hook: force the tab strip visible (skip the hover requirement)
        // so we can screenshot it for verification.
        if ProcessInfo.processInfo.environment["PIP_TEST_FORCE_STRIP"] == "1",
           let primary = coordinator.sessions.first {
            try? await Task.sleep(nanoseconds: 500_000_000)
            primary.tabStrip.alphaValue = 1
            primary.tabStrip.isHidden = false
            NSLog("PIP_TEST_FORCE_STRIP: strip alpha forced to 1 (tabs=\(primary.tabs.count))")
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
