import Cocoa
import ScreenCaptureKit

/// Stable identity for a single overlay across its lifetime. NSObject so it
/// bridges cleanly into `NSMenuItem.representedObject`.
final class OverlayID: NSObject {
    let value: UUID
    init(_ value: UUID = UUID()) { self.value = value }
    override var hash: Int { value.hashValue }
    override func isEqual(_ object: Any?) -> Bool {
        (object as? OverlayID)?.value == value
    }
    override var description: String { "OverlayID(\(value.uuidString.prefix(8)))" }
}

/// Payload attached to per-overlay `NSMenuItem.representedObject`. A single
/// `@objc handleOverlayMenu(_:)` selector on `AppDelegate` unpacks this and
/// dispatches to the right session + action — keeps us from minting a separate
/// selector per (session × action).
final class OverlayMenuTag: NSObject {
    enum Action: Equatable {
        case stop
        case setCrop
        case clearCrop
        case toggleAutoHide
        case setOpacity(Int)
        // Tab-targeting actions (Phase 3).
        case closeTab(OverlayTabID)
        case switchTab(OverlayTabID)
        case tearOutTab(OverlayTabID)
        case moveTabTo(OverlayTabID, OverlayID)
    }
    let id: OverlayID
    let action: Action
    init(_ id: OverlayID, _ action: Action) {
        self.id = id
        self.action = action
    }
}

/// One PiP overlay window. Owns the window + a list of `OverlayTab`s that
/// share it; window-level state (frame, opacity, click-through, auto-hide,
/// idle view, tab strip) lives here, while per-capture state lives on
/// `OverlayTab`. A session with 1 tab renders no strip and behaves exactly
/// like the v1 single-overlay; with N tabs the strip shows on hover and only
/// the active tab's CaptureView is visible at a time.
@MainActor
final class OverlaySession {
    let id: OverlayID
    let window: OverlayWindow
    let idleView: IdleView
    let clickThrough: ClickThroughController
    let containerView: NSView
    let tabStrip: TabStripView

    static let overlayMinSize = NSSize(width: 240, height: 160)
    static let overlayMaxSize = NSSize(width: 720, height: 540)
    static let overlayIdleSize = NSSize(width: 380, height: 230)

    /// Tabs in display order. Always at least 1 (the launch entry-point tab).
    private(set) var tabs: [OverlayTab] = []

    /// Stable pointer to the currently visible tab.
    private(set) var activeTabID: OverlayTabID?

    var activeTab: OverlayTab? {
        guard let id = activeTabID else { return tabs.first }
        return tabs.first(where: { $0.id == id }) ?? tabs.first
    }

    /// Window-level auto-hide setting. Stored on the session and applied to
    /// the *active* tab's visibility controller. On tab switch, we re-apply.
    private var _autoHide: Bool = true
    var autoHide: Bool {
        get { _autoHide }
        set {
            _autoHide = newValue
            updateActiveTabVisibility()
        }
    }

    var opacity: CGFloat = 1.0 {
        didSet { clickThrough.baseAlpha = opacity }
    }

    var opacityPercent: Int { Int((opacity * 100).rounded()) }

    /// Whether the window's aspect has been set by the first successful
    /// capture. Once true, subsequent captures don't auto-resize the window —
    /// they fit-aspect into the current frame instead.
    private var windowAspectEstablished: Bool = false

    /// Convenience pass-throughs to the active tab — keeps existing
    /// AppDelegate/menu code working with minimal churn.
    var capturedWindowID: CGWindowID? { activeTab?.capturedWindowID }
    var isCapturing: Bool { tabs.contains(where: { $0.isCapturing }) }
    var hasCrop: Bool { activeTab?.hasCrop ?? false }
    var sessionLabel: String { activeTab?.sessionLabel ?? "Idle" }
    var lastCapturedWindowID: CGWindowID? { activeTab?.lastCapturedWindowID }

    /// Window-level visibility shim — `AppDelegate.toggleVisibilityViaHotkey`
    /// calls `session.visibility.setManualHide(_:)`. We forward to **every**
    /// tab's controller so the manual hide latch is consistent across tabs.
    var visibility: SessionVisibilityProxy { SessionVisibilityProxy(session: self) }

    /// AppDelegate sets this so the app-level "last captured anywhere" pointer
    /// updates whenever any tab in this session captures successfully.
    var onCaptureSucceeded: ((CGWindowID) -> Void)? {
        didSet { rewireTabCallbacks() }
    }

    /// Right-click context menu builder — assigned by AppDelegate.
    var contextMenuBuilder: ((NSEvent) -> Void)?

    func menuModel() -> OverlaySessionMenuModel {
        let tabModels = tabs.compactMap { tab -> OverlayTabMenuModel? in
            // Only include capturing tabs in the per-tab submenu — idle tabs
            // (e.g., the leftover entry-point slot) aren't useful targets.
            guard tab.isCapturing else { return nil }
            let label = tab.sessionLabel == "Idle" ? "Idle" : tab.sessionLabel
            return OverlayTabMenuModel(
                id: tab.id,
                displayLabel: label,
                isActive: tab.id == activeTabID,
                capturedWindowID: tab.capturedWindowID
            )
        }
        return OverlaySessionMenuModel(
            id: id,
            displayLabel: sessionLabel,
            isCapturing: isCapturing,
            capturedWindowID: capturedWindowID,
            hasCrop: hasCrop,
            autoHide: autoHide,
            opacityPercent: opacityPercent,
            tabs: tabModels
        )
    }

    init(id: OverlayID = OverlayID(), initialFrame: NSRect) {
        self.id = id
        self.window = OverlayWindow(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let containerSize = NSRect(origin: .zero, size: initialFrame.size)
        self.containerView = NSView(frame: containerSize)
        containerView.wantsLayer = true
        containerView.autoresizingMask = [.width, .height]
        window.contentView = containerView

        self.idleView = IdleView(frame: containerSize)
        idleView.autoresizingMask = [.width, .height]
        containerView.addSubview(idleView)

        self.tabStrip = TabStripView()
        let stripFrame = NSRect(x: 0, y: containerSize.size.height - TabStripView.height,
                                width: containerSize.size.width, height: TabStripView.height)
        tabStrip.frame = stripFrame
        tabStrip.autoresizingMask = [.width, .minYMargin]
        containerView.addSubview(tabStrip)

        self.clickThrough = ClickThroughController(overlayWindow: window)
        window.orderFrontRegardless()

        // Always start with one tab — the entry-point. Same as v1 launch UX.
        let initialTab = OverlayTab(overlayWindow: window,
                                    frame: containerSize)
        tabs.append(initialTab)
        activeTabID = initialTab.id
        wireTab(initialTab)

        // Tab strip event handlers
        tabStrip.onSwitch = { [weak self] tabID in self?.switchTo(tabID) }
        tabStrip.onClose = { [weak self] tabID in self?.closeTab(tabID) }
        tabStrip.onRightClick = { [weak self] tabID, event in
            // Switch to the right-clicked tab so the context menu reflects
            // its state, then re-fire the standard session-scoped builder.
            self?.switchTo(tabID)
            self?.contextMenuBuilder?(event)
        }
        rebuildTabStrip()

        window.onContextMenu = { [weak self] event in
            self?.contextMenuBuilder?(event)
        }
    }

    func setIdleStatus(_ message: String) {
        idleView.setStatus(message)
    }

    /// Phase 1 entry point preserving v1 semantics: AppDelegate.pickWindow
    /// calls this when the destination is "fill idle session". Routes into
    /// the (only) tab.
    func start(window source: SCWindow, cropImmediately: Bool = false) {
        guard let tab = activeTab else { return }
        startTab(tab, source: source, cropImmediately: cropImmediately)
    }

    /// Phase 2 + Phase 3 entry point: add a new capture as a tab in this
    /// session. If an idle tab is already present, fills it; otherwise
    /// appends a new tab and switches to it.
    @discardableResult
    func addTab(window source: SCWindow, cropImmediately: Bool = false) -> OverlayTabID {
        let target: OverlayTab
        if let idle = tabs.last(where: { !$0.isCapturing }) {
            target = idle
        } else {
            let containerSize = containerView.bounds.size
            let new = OverlayTab(overlayWindow: window,
                                 frame: NSRect(origin: .zero, size: containerSize))
            tabs.append(new)
            wireTab(new)
            target = new
        }
        switchTo(target.id)
        startTab(target, source: source, cropImmediately: cropImmediately)
        rebuildTabStrip()
        updateActiveTabVisibility()
        return target.id
    }

    /// Switch the visible tab. Updates contentView, visibility wiring, and
    /// the resize-handle aspect lock (locked for single tab; free for N).
    func switchTo(_ tabID: OverlayTabID) {
        guard tabs.contains(where: { $0.id == tabID }) else { return }
        let prevID = activeTabID
        activeTabID = tabID
        // Disable previous active tab's visibility (it's no longer driving
        // window auto-hide). Re-enable the new active tab's visibility per
        // the session's autoHide setting.
        if let prev = tabs.first(where: { $0.id == prevID }) {
            prev.visibility.enabled = false
        }
        updateActiveTabVisibility()
        // Swap the visible captureView (or idle view).
        showActiveContent()
        rebuildTabStrip()
    }

    /// Close one tab. If it's the last tab, return the session to idle (do
    /// not remove the entry-point tab — the user needs something to right-
    /// click). Otherwise drop the tab and switch active to the previous one.
    func closeTab(_ tabID: OverlayTabID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let tab = tabs[idx]
        if tabs.count == 1 {
            // Last tab — preserve it as the always-present entry point but
            // stop its capture, returning the session to idle (mirrors the
            // multi-overlay rule: stopping the only session goes to idle,
            // not removal).
            tab.stop()
            activeTabID = tab.id
            showActiveContent()
            rebuildTabStrip()
            updateActiveTabVisibility()
            return
        }
        // Drop the tab. Pick a sensible new active.
        tab.close()
        tabs.remove(at: idx)
        if activeTabID == tabID {
            // Prefer the prior tab; fall back to the new last.
            let newActive = tabs[max(0, idx - 1)]
            activeTabID = newActive.id
        }
        showActiveContent()
        rebuildTabStrip()
        updateActiveTabVisibility()
    }

    func stop() {
        // "Stop" on a session = stop every tab (return to idle). Mirrors the
        // v1 single-capture stop behavior; with multiple tabs it's the
        // panic-stop-this-window action.
        for tab in tabs { tab.stop() }
        showActiveContent()
        rebuildTabStrip()
    }

    func beginCropSelection() {
        activeTab?.beginCropSelection()
    }

    func clearCrop() {
        activeTab?.clearCrop()
    }

    /// Tear down. Closes every tab (each releases its SCStream + observers).
    func close() {
        for tab in tabs { tab.close() }
        window.orderOut(nil)
    }

    /// Snapshot for the tab strip + per-tab menus. Built fresh on every
    /// change.
    func tabModels() -> [TabStripModel] {
        tabs.map { tab in
            TabStripModel(
                id: tab.id,
                appName: tab.sourceApp?.applicationName ?? "Idle",
                title: tab.sessionLabel == "Idle" ? "" : tab.sessionLabel,
                icon: tab.sourceApp.flatMap { runningAppIcon(pid: $0.processID) },
                isActive: tab.id == activeTabID
            )
        }
    }

    // MARK: - Tab wiring

    private func startTab(_ tab: OverlayTab, source: SCWindow, cropImmediately: Bool) {
        let appName = source.owningApplication?.applicationName ?? "source"
        // For the active tab, show the "starting…" idle state immediately.
        // For a non-active tab being filled in the background, just kick off
        // start without disturbing the visible content.
        if tab.id == activeTabID {
            swapActiveToIdle(message: "Starting capture of \(appName)…")
        }
        tab.start(
            window: source,
            cropImmediately: cropImmediately,
            onStartFailure: { [weak self, weak tab] msg in
                guard let self = self, let tab = tab else { return }
                if tab.id == self.activeTabID {
                    self.swapActiveToIdle(message: "Capture failed: \(msg)")
                }
                self.rebuildTabStrip()
            },
            onSafetyNetTimeout: { [weak self, weak tab] name in
                guard let self = self, let tab = tab else { return }
                if tab.id == self.activeTabID {
                    self.swapActiveToIdle(message: "\(name) didn't produce frames — try another window")
                }
                self.rebuildTabStrip()
            }
        )
    }

    /// Wires a tab's upward callbacks to the session's window-level handlers.
    private func wireTab(_ tab: OverlayTab) {
        tab.onFirstFrame = { [weak self, weak tab] size in
            guard let self = self, let tab = tab else { return }
            self.handleFirstFrame(size: size, for: tab)
        }
        tab.onError = { [weak self, weak tab] _ in
            guard let self = self, let tab = tab else { return }
            if tab.id == self.activeTabID {
                self.swapActiveToIdle(message: "Capture stream error")
            }
        }
        tab.onModeChange = { [weak tab] mode in
            tab?.captureView.showMode(mode)
        }
        tab.onSourceTerminated = { [weak self, weak tab] in
            guard let self = self, let tab = tab else { return }
            // Active tab terminated → close it (which may swap to idle for
            // the last tab, or remove it for siblings). Non-active tabs are
            // also closed so they don't sit there with a dead source.
            self.closeTab(tab.id)
            if tab.id == self.activeTabID {
                self.idleView.setStatus("Source app quit")
            }
        }
        tab.onCaptureSucceeded = { [weak self] windowID in
            self?.windowAspectEstablished = true
            self?.onCaptureSucceeded?(windowID)
            self?.rebuildTabStrip()
        }
        tab.onCropChanged = { [weak self, weak tab] _, cropAspect in
            guard let self = self, let tab = tab else { return }
            // With ≥2 tabs, crop is per-tab — don't resize the window.
            // With 1 tab, preserve v1 behavior (resize to crop aspect).
            guard self.tabs.count == 1 else { return }
            let aspect = cropAspect ?? tab.sourceAspect
            guard let aspect = aspect else { return }
            self.resizeOverlay(toAspect: aspect)
            tab.captureView.resizeHandle.aspectRatio = aspect
        }
    }

    private func rewireTabCallbacks() {
        for tab in tabs { wireTab(tab) }
    }

    private func updateActiveTabVisibility() {
        guard let active = activeTab else { return }
        // Inactive tabs don't drive auto-hide.
        for tab in tabs where tab.id != active.id {
            tab.visibility.enabled = false
        }
        active.visibility.enabled = _autoHide
    }

    // MARK: - Window-level layout

    /// Show the right view in the container based on active tab state.
    private func showActiveContent() {
        guard let active = activeTab else { return showIdle() }
        if active.isCapturing {
            installAsCapture(active.captureView)
        } else {
            showIdle()
        }
        // Update resize-handle aspect lock based on tab count.
        if let aspect = active.sourceAspect {
            active.captureView.resizeHandle.aspectRatio = aspect
            active.captureView.resizeHandle.lockAspect = (tabs.count == 1)
        } else {
            active.captureView.resizeHandle.lockAspect = (tabs.count == 1)
        }
    }

    private func installAsCapture(_ view: CaptureView) {
        // Remove any prior capture view; keep idle around (hidden) so we can
        // swap back without recreating it.
        for sub in containerView.subviews where (sub is CaptureView) && sub !== view {
            sub.removeFromSuperview()
        }
        idleView.isHidden = true
        view.frame = containerView.bounds
        view.autoresizingMask = [.width, .height]
        if view.superview !== containerView {
            // Insert below the strip so the strip sits on top.
            containerView.addSubview(view, positioned: .below, relativeTo: tabStrip)
        }
    }

    private func showIdle() {
        for sub in containerView.subviews where sub is CaptureView {
            sub.removeFromSuperview()
        }
        idleView.frame = containerView.bounds
        idleView.isHidden = false
    }

    /// First-frame handling for one tab. Resizes the host window IFF this is
    /// the first capture in the session (windowAspectEstablished == false).
    private func handleFirstFrame(size: CGSize, for tab: OverlayTab) {
        let aspect = size.width / size.height
        tab.recordSourceAspect(aspect)

        if !windowAspectEstablished {
            let preferredWidth: CGFloat = 480
            let preferredHeight = preferredWidth / aspect
            let clampedSize = clampToOverlayBounds(NSSize(width: preferredWidth, height: preferredHeight),
                                                    aspect: aspect)
            var f = window.frame
            f.origin.y -= (clampedSize.height - f.size.height)
            f.size = clampedSize
            window.setFrame(f, display: true, animate: false)
            windowAspectEstablished = true
        }

        tab.captureView.resizeHandle.aspectRatio = aspect
        tab.captureView.resizeHandle.minSize = Self.overlayMinSize
        tab.captureView.resizeHandle.maxSize = Self.overlayMaxSize
        tab.captureView.resizeHandle.lockAspect = (tabs.count == 1)

        // Only swap visible content if this is the active tab — background
        // tabs paint their CaptureView off-screen.
        if tab.id == activeTabID {
            installAsCapture(tab.captureView)
        }
        rebuildTabStrip()
    }

    /// Swap the currently-visible content to the idle view (used when active
    /// tab's capture stops). Doesn't touch tab list.
    private func swapActiveToIdle(message: String? = nil) {
        if let message = message { idleView.setStatus(message) }
        showIdle()
    }

    private func resizeOverlay(toAspect aspect: CGFloat) {
        let preferredWidth: CGFloat = max(Self.overlayMinSize.width,
                                          min(Self.overlayMaxSize.width, window.frame.size.width))
        let preferredHeight = preferredWidth / aspect
        let clamped = clampToOverlayBounds(NSSize(width: preferredWidth, height: preferredHeight), aspect: aspect)
        var f = window.frame
        f.origin.y -= (clamped.height - f.size.height)
        f.size = clamped
        window.setFrame(f, display: true, animate: false)
    }

    private func clampToOverlayBounds(_ size: NSSize, aspect: CGFloat) -> NSSize {
        var width = size.width
        var height = size.height
        if width < Self.overlayMinSize.width {
            width = Self.overlayMinSize.width
            height = width / aspect
        }
        if height < Self.overlayMinSize.height {
            height = Self.overlayMinSize.height
            width = height * aspect
        }
        if width > Self.overlayMaxSize.width {
            width = Self.overlayMaxSize.width
            height = width / aspect
        }
        if height > Self.overlayMaxSize.height {
            height = Self.overlayMaxSize.height
            width = height * aspect
        }
        return NSSize(width: width, height: height)
    }

    private func rebuildTabStrip() {
        tabStrip.update(tabModels())
    }

    private func runningAppIcon(pid: pid_t) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}

/// Forwards `setManualHide(_:)` to every tab's visibility controller so the
/// global panic-hide latch (`⌃⌥H`) lands consistently across tabs in a
/// session, regardless of which one is active.
@MainActor
struct SessionVisibilityProxy {
    weak var session: OverlaySession?

    func setManualHide(_ hidden: Bool) {
        guard let session = session else { return }
        for tab in session.tabs {
            tab.visibility.setManualHide(hidden)
        }
    }
}
