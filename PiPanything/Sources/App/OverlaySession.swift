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
    }
    let id: OverlayID
    let action: Action
    init(_ id: OverlayID, _ action: Action) {
        self.id = id
        self.action = action
    }
}

/// One PiP overlay — owns its window, capture pipeline, views, and per-overlay
/// feature controllers. Kicked off by `OverlayCoordinator` (Phase 2+); for now
/// `AppDelegate` instantiates one of these and routes menu actions to it.
@MainActor
final class OverlaySession {
    let id: OverlayID
    let window: OverlayWindow
    let captureManager: CaptureManager
    let captureView: CaptureView
    let idleView: IdleView
    let visibility: SourceVisibilityController
    let clickThrough: ClickThroughController

    static let overlayMinSize = NSSize(width: 240, height: 160)
    static let overlayMaxSize = NSSize(width: 720, height: 540)
    static let overlayIdleSize = NSSize(width: 380, height: 230)

    private var sourceAspect: CGFloat?

    var autoHide: Bool {
        get { visibility.enabled }
        set { visibility.enabled = newValue }
    }

    var opacity: CGFloat = 1.0 {
        didSet { clickThrough.baseAlpha = opacity }
    }

    var opacityPercent: Int { Int((opacity * 100).rounded()) }
    var capturedWindowID: CGWindowID? { captureManager.capturedWindowID }
    var isCapturing: Bool { captureManager.isCapturing }
    var hasCrop: Bool { captureManager.cropRect != nil }

    /// "App — Window Title" for the menu. Set during `start(window:)`.
    private(set) var sessionLabel: String = "Idle"

    func menuModel() -> OverlaySessionMenuModel {
        OverlaySessionMenuModel(
            id: id,
            displayLabel: sessionLabel,
            isCapturing: isCapturing,
            capturedWindowID: capturedWindowID,
            hasCrop: hasCrop,
            autoHide: autoHide,
            opacityPercent: opacityPercent
        )
    }

    /// Right-click context menu builder. Phase 1 keeps AppDelegate as the
    /// builder (assigned externally); Phase 4 moves the build into the session.
    var contextMenuBuilder: ((NSEvent) -> Void)?

    init(id: OverlayID = OverlayID(), initialFrame: NSRect) {
        self.id = id
        self.captureManager = CaptureManager()
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

        self.idleView = IdleView(frame: NSRect(origin: .zero, size: initialFrame.size))
        self.captureView = CaptureView(
            frame: NSRect(origin: .zero, size: initialFrame.size),
            displayLayer: captureManager.displayLayer,
            imageLayer: captureManager.imageLayer
        )

        window.contentView = idleView
        window.orderFrontRegardless()

        self.visibility = SourceVisibilityController(overlayWindow: window)
        self.clickThrough = ClickThroughController(overlayWindow: window)

        // Wire callbacks back into the session.
        visibility.onSourceTerminated = { [weak self] in
            guard let self = self else { return }
            Task { [weak self] in
                guard let self = self else { return }
                await self.captureManager.stop()
                self.swapToIdle(message: "Source app quit")
            }
        }
        captureManager.onFirstFrame = { [weak self] size in
            self?.handleFirstFrame(size: size)
        }
        captureManager.onError = { [weak self] _ in
            self?.swapToIdle(message: "Capture stream error")
        }
        captureManager.onModeChange = { [weak self] mode in
            self?.captureView.showMode(mode)
        }
        window.onContextMenu = { [weak self] event in
            self?.contextMenuBuilder?(event)
        }
    }

    func setIdleStatus(_ message: String) {
        idleView.setStatus(message)
    }

    /// Drive a new capture for this session. Mirrors today's `pickWindow`
    /// behavior: idle status while starting, 2.5s safety net for sources that
    /// don't deliver frames, optional immediate crop selection on success.
    func start(window source: SCWindow, cropImmediately: Bool = false) {
        let appName = source.owningApplication?.applicationName ?? "source"
        let title = source.title ?? ""
        sessionLabel = title.isEmpty ? appName : "\(appName) — \(title)"
        captureView.endCropSelection()
        captureView.cropRect = nil
        sourceAspect = nil
        swapToIdle(message: "Starting capture of \(appName)…")
        // Tell the visibility controller about the new source up front so a
        // didActivate notification arriving mid-start is correctly routed.
        visibility.setSource(
            bundle: source.owningApplication?.bundleIdentifier,
            pid: source.owningApplication?.processID
        )
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.captureManager.start(window: source)
            } catch {
                self.visibility.setSource(bundle: nil, pid: nil)
                self.swapToIdle(message: "Capture failed: \(error.localizedDescription)")
                return
            }
            // Safety net: if no frame within 2.5s, swap back so we don't show a black box.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.captureManager.capturedWindowID == source.windowID,
               self.window.contentView !== self.captureView {
                await self.captureManager.stop()
                self.visibility.setSource(bundle: nil, pid: nil)
                self.swapToIdle(message: "\(appName) didn't produce frames — try another window")
                return
            }
            if cropImmediately, self.window.contentView === self.captureView {
                self.beginCropSelection()
            }
        }
    }

    func stop() {
        captureView.endCropSelection()
        captureView.cropRect = nil
        sessionLabel = "Idle"
        Task { [weak self] in
            guard let self = self else { return }
            await self.captureManager.stop()
            self.visibility.setSource(bundle: nil, pid: nil)
            self.sourceAspect = nil
            self.swapToIdle(message: "Capture stopped")
        }
    }

    func beginCropSelection() {
        guard captureManager.isCapturing else { return }
        captureView.beginCropSelection { [weak self] rect in
            self?.commitCrop(rect)
        }
    }

    func clearCrop() {
        captureManager.applyCrop(nil)
        captureView.cropRect = nil
        if let aspect = sourceAspect {
            resizeOverlay(toAspect: aspect)
            captureView.resizeHandle.aspectRatio = aspect
        }
    }

    /// Tear down all observers / monitors / streams. Call before dropping the
    /// session — the controllers register `NSWorkspace` and `NSEvent` monitors
    /// that need explicit teardown when there are sibling overlays.
    func close() {
        captureView.endCropSelection()
        // Capture the manager strongly so the SCStream stop completes even
        // after `self` deallocs — `[weak self]` here would orphan the stream.
        let manager = captureManager
        Task { await manager.stop() }
        window.orderOut(nil)
        // Controllers' deinit removes their observers — releasing `self`
        // releases them.
    }

    // MARK: - Internals

    private func commitCrop(_ rect: CGRect?) {
        guard let rect = rect, let source = sourceAspect else { return }
        captureManager.applyCrop(rect)
        captureView.cropRect = rect
        // Crop's physical aspect on the source = (cropW / cropH) * sourceAspect.
        let cropAspect = (rect.width / rect.height) * source
        resizeOverlay(toAspect: cropAspect)
        captureView.resizeHandle.aspectRatio = cropAspect
    }

    private func handleFirstFrame(size: CGSize) {
        let aspect = size.width / size.height
        sourceAspect = aspect
        let preferredWidth: CGFloat = 480
        let preferredHeight = preferredWidth / aspect
        let clampedSize = clampToOverlayBounds(NSSize(width: preferredWidth, height: preferredHeight),
                                                aspect: aspect)
        var f = window.frame
        f.origin.y -= (clampedSize.height - f.size.height)
        f.size = clampedSize
        window.setFrame(f, display: true, animate: false)
        captureView.frame = NSRect(origin: .zero, size: clampedSize)
        captureView.resizeHandle.aspectRatio = aspect
        captureView.resizeHandle.minSize = Self.overlayMinSize
        captureView.resizeHandle.maxSize = Self.overlayMaxSize
        if window.contentView !== captureView {
            window.contentView = captureView
        }
    }

    private func swapToIdle(message: String? = nil) {
        if let message = message { idleView.setStatus(message) }
        if window.contentView !== idleView {
            let size = Self.overlayIdleSize
            let f = NSRect(x: window.frame.origin.x, y: window.frame.origin.y,
                           width: size.width, height: size.height)
            window.setFrame(f, display: true, animate: false)
            idleView.frame = NSRect(origin: .zero, size: f.size)
            window.contentView = idleView
        }
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
        captureView.frame = NSRect(origin: .zero, size: clamped)
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
}
