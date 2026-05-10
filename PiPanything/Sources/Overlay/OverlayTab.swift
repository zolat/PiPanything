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

/// Stable identity for one tab in a session. NSObject so it bridges into
/// `NSMenuItem.representedObject` cleanly (matches `OverlayID`'s pattern).
final class OverlayTabID: NSObject {
    let value: UUID
    init(_ value: UUID = UUID()) { self.value = value }
    override var hash: Int { value.hashValue }
    override func isEqual(_ object: Any?) -> Bool {
        (object as? OverlayTabID)?.value == value
    }
    override var description: String { "OverlayTabID(\(value.uuidString.prefix(8)))" }
}

/// One capture inside an overlay window. Owns its own `CaptureManager` +
/// `CaptureView` + `SourceVisibilityController` so that N tabs in one window
/// can stream concurrently. Window-level concerns (frame, opacity, click-
/// through, idle view) live on `OverlaySession`; the tab fires callbacks
/// upward when the window needs to react (resize on first frame, swap to idle
/// on error, etc.).
@MainActor
final class OverlayTab {
    let id: OverlayTabID
    let captureManager: CaptureManager
    let captureView: CaptureView
    let visibility: SourceVisibilityController

    /// "App — Window Title" for the tab strip + menu. Set during `start`.
    private(set) var sessionLabel: String = "Idle"

    /// Last captured frame's aspect (W/H). Used to resize the host window.
    private(set) var sourceAspect: CGFloat?

    /// Most recent successful capture's windowID — survives `stop()` for the
    /// "restart last" hotkey path.
    private(set) var lastCapturedWindowID: CGWindowID?

    /// Source app whose foregrounding should hide the host window. Mirrors
    /// the visibility controller's `sourceBundle` for fast reads.
    var sourceApp: SCRunningApplication? { _sourceApp }
    private var _sourceApp: SCRunningApplication?

    /// Bundle ID + window title of the current source. Stored separately from
    /// `sessionLabel` (which is a display string) so minimize/restore can
    /// re-resolve the matching `SCWindow` after refresh, without parsing the
    /// "App — Title" label back apart.
    private(set) var sourceBundleID: String?
    private(set) var sourceTitle: String?

    /// Active crop rect on the underlying capture (`nil` = no crop). Exposed
    /// so the session can snapshot it during minimize.
    var cropRect: CGRect? { captureManager.cropRect }

    // MARK: - Upward callbacks (set by OverlaySession at construction)

    /// Fires once per capture, when the first frame's size is known. Session
    /// uses it to resize the window for the new aspect (when this is the only
    /// tab) or to fit-aspect (when there are siblings — Phase 2).
    var onFirstFrame: ((CGSize) -> Void)?

    /// Fires when the SCStream errors out — session typically swaps to idle.
    var onError: ((Error) -> Void)?

    /// Fires when the capture mode changes (.stream / .polling / .idle) so
    /// the captureView can swap which sublayer is visible. Today the session
    /// just forwards this to `captureView.showMode(_:)`.
    var onModeChange: ((CaptureMode) -> Void)?

    /// Fires when the captured source app terminates. Session decides whether
    /// to close the tab, switch to a sibling, or fall back to idle.
    var onSourceTerminated: (() -> Void)?

    /// Fires after the 2.5s safety net passes and the capture is confirmed
    /// running. AppDelegate uses this to maintain its app-level "last
    /// captured anywhere" pointer for the `⌃⌥P` hotkey.
    var onCaptureSucceeded: ((CGWindowID) -> Void)?

    /// Fires when crop changes — `(cropRect, cropAspect)`. Session decides
    /// whether to resize the window (today's single-tab behavior) or leave it
    /// alone (Phase 2 multi-tab seam). `nil` rect = crop cleared.
    var onCropChanged: ((CGRect?, CGFloat?) -> Void)?

    var isCapturing: Bool { captureManager.isCapturing }
    var hasCrop: Bool { captureManager.cropRect != nil }
    var capturedWindowID: CGWindowID? { captureManager.capturedWindowID }

    init(id: OverlayTabID = OverlayTabID(), overlayWindow: OverlayWindow, frame: NSRect) {
        self.id = id
        self.captureManager = CaptureManager()
        self.captureView = CaptureView(
            frame: frame,
            displayLayer: captureManager.displayLayer,
            imageLayer: captureManager.imageLayer
        )
        self.visibility = SourceVisibilityController(overlayWindow: overlayWindow)

        // Wire CaptureManager callbacks to fire our upward closures.
        captureManager.onFirstFrame = { [weak self] size in
            self?.onFirstFrame?(size)
        }
        captureManager.onError = { [weak self] err in
            self?.onError?(err)
        }
        captureManager.onModeChange = { [weak self] mode in
            self?.onModeChange?(mode)
        }
        visibility.onSourceTerminated = { [weak self] in
            self?.onSourceTerminated?()
        }
    }

    /// Drive a new capture for this tab. Mirrors the v1 OverlaySession.start
    /// flow: idle status (via the host's onError? no — the session shows the
    /// "starting…" state itself before calling us); 2.5s safety net; optional
    /// immediate crop on success.
    func start(window source: SCWindow, cropImmediately: Bool = false,
               onStartFailure: @escaping (String) -> Void = { _ in },
               onSafetyNetTimeout: @escaping (String) -> Void = { _ in }) {
        let appName = source.owningApplication?.applicationName ?? "source"
        let title = source.title ?? ""
        sessionLabel = title.isEmpty ? appName : "\(appName) — \(title)"
        captureView.endCropSelection()
        captureView.cropRect = nil
        sourceAspect = nil
        _sourceApp = source.owningApplication
        sourceBundleID = source.owningApplication?.bundleIdentifier
        sourceTitle = title

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
                self._sourceApp = nil
                onStartFailure(error.localizedDescription)
                return
            }
            // Safety net: if no frame within 2.5s, abandon this capture.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            // The onFirstFrame callback would have fired by now if frames
            // were arriving — session uses that to swap contentView to
            // captureView. We check `firstFrameReported` indirectly via
            // sourceAspect (set by handleFirstFrame in session). For Phase 1
            // we hand the safety-net callback the appName; the session
            // checks its own state to decide whether to swap to idle.
            if self.captureManager.capturedWindowID == source.windowID,
               self.sourceAspect == nil {
                await self.captureManager.stop()
                self.visibility.setSource(bundle: nil, pid: nil)
                self._sourceApp = nil
                onSafetyNetTimeout(appName)
                return
            }
            self.lastCapturedWindowID = source.windowID
            self.onCaptureSucceeded?(source.windowID)
            if cropImmediately {
                self.beginCropSelection()
            }
        }
    }

    func stop() {
        captureView.endCropSelection()
        captureView.cropRect = nil
        sessionLabel = "Idle"
        sourceAspect = nil
        sourceBundleID = nil
        sourceTitle = nil
        Task { [weak self] in
            guard let self = self else { return }
            await self.captureManager.stop()
            self.visibility.setSource(bundle: nil, pid: nil)
            self._sourceApp = nil
        }
    }

    /// Tear down all observers / monitors / streams. Call before dropping the
    /// tab — the controller registers `NSWorkspace` monitors that need
    /// explicit teardown when there are sibling tabs/windows.
    func close() {
        captureView.endCropSelection()
        // Capture the manager strongly so the SCStream stop completes even
        // after `self` deallocs — `[weak self]` here would orphan the stream
        // (advisor-flagged pattern from multi-overlay).
        let manager = captureManager
        Task { await manager.stop() }
        // visibility's deinit removes its NSWorkspace observers when self
        // releases.
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
        // Notify the session so it can resize the window back to source aspect
        // (single-tab behavior) or leave it alone (multi-tab — Phase 2).
        onCropChanged?(nil, sourceAspect)
    }

    /// Apply a crop programmatically (no marquee). Used by restore-from-
    /// minimized to re-establish a saved crop after the new capture's first
    /// frame settles `sourceAspect`. No-op if `sourceAspect` isn't known yet.
    func applyCropProgrammatic(_ rect: CGRect) {
        guard let aspect = sourceAspect else { return }
        captureManager.applyCrop(rect)
        captureView.cropRect = rect
        let cropAspect = (rect.width / rect.height) * aspect
        onCropChanged?(rect, cropAspect)
    }

    /// Called by the session after `onFirstFrame` so the tab can record the
    /// captured aspect for its own crop math. Kept separate from
    /// `onFirstFrame` since the session also uses the same value to size the
    /// window — passing it back avoids two sources of truth.
    func recordSourceAspect(_ aspect: CGFloat) {
        sourceAspect = aspect
    }

    // MARK: - Internals

    private func commitCrop(_ rect: CGRect?) {
        guard let rect = rect, let source = sourceAspect else { return }
        captureManager.applyCrop(rect)
        captureView.cropRect = rect
        // Crop's physical aspect on the source = (cropW / cropH) * sourceAspect.
        let cropAspect = (rect.width / rect.height) * source
        onCropChanged?(rect, cropAspect)
    }
}
