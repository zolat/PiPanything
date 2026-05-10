import Cocoa
import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var overlayWindow: OverlayWindow!
    var captureManager: CaptureManager!
    var idleView: IdleView!
    var captureView: CaptureView!
    var visibilityController: SourceVisibilityController!
    var clickThroughController: ClickThroughController!
    private(set) var sources = SourceList()
    private(set) var autoHideEnabled = true
    private(set) var overlayOpacity: CGFloat = 1.0
    private var thumbnails: [CGWindowID: NSImage] = [:]

    private static let overlayMinSize = NSSize(width: 240, height: 160)
    private static let overlayMaxSize = NSSize(width: 720, height: 540)
    private static let overlayIdleSize = NSSize(width: 380, height: 230)

    func applicationDidFinishLaunching(_ notification: Notification) {
        captureManager = CaptureManager()
        setupOverlay()
        // Request Accessibility permission so we can detect minimized windows.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        Task {
            await refreshSources()
            if ProcessInfo.processInfo.environment["PIP_AUTO_CAPTURE"] == "1" {
                await autoCaptureLargest()
            }
        }
    }

    private func setupOverlay() {
        let frame = NSRect(x: 240, y: 240, width: 380, height: 230)
        overlayWindow = OverlayWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.hasShadow = true
        overlayWindow.isMovableByWindowBackground = true
        overlayWindow.level = .screenSaver
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        idleView = IdleView(frame: NSRect(origin: .zero, size: frame.size))
        captureView = CaptureView(
            frame: NSRect(origin: .zero, size: frame.size),
            displayLayer: captureManager.displayLayer,
            imageLayer: captureManager.imageLayer
        )

        overlayWindow.contentView = idleView
        overlayWindow.orderFrontRegardless()

        visibilityController = SourceVisibilityController(overlayWindow: overlayWindow)
        visibilityController.onSourceTerminated = { [weak self] in
            guard let self = self else { return }
            Task {
                await self.captureManager.stop()
                self.swapToIdle(message: "Source app quit")
            }
        }
        clickThroughController = ClickThroughController(overlayWindow: overlayWindow)

        captureManager.onFirstFrame = { [weak self] size in
            self?.handleFirstFrame(size: size)
        }
        captureManager.onError = { [weak self] _ in
            self?.swapToIdle(message: "Capture stream error")
        }
        captureManager.onModeChange = { [weak self] mode in
            self?.captureView.showMode(mode)
        }

        overlayWindow.onContextMenu = { [weak self] event in
            self?.showContextMenu(for: event)
        }
    }

    private func showContextMenu(for event: NSEvent) {
        let menu = NSMenu()
        menu.delegate = self
        guard let view = overlayWindow.contentView else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func handleFirstFrame(size: CGSize) {
        let aspect = size.width / size.height
        sourceAspect = aspect
        let preferredWidth: CGFloat = 480
        let preferredHeight = preferredWidth / aspect
        let clampedSize = clampToOverlayBounds(NSSize(width: preferredWidth, height: preferredHeight),
                                                aspect: aspect)
        var f = overlayWindow.frame
        f.origin.y -= (clampedSize.height - f.size.height)
        f.size = clampedSize
        overlayWindow.setFrame(f, display: true, animate: false)
        captureView.frame = NSRect(origin: .zero, size: clampedSize)
        captureView.resizeHandle.aspectRatio = aspect
        captureView.resizeHandle.minSize = Self.overlayMinSize
        captureView.resizeHandle.maxSize = Self.overlayMaxSize
        if overlayWindow.contentView !== captureView {
            overlayWindow.contentView = captureView
        }
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

    private func swapToIdle(message: String? = nil) {
        if let message = message { idleView.setStatus(message) }
        if overlayWindow.contentView !== idleView {
            let size = Self.overlayIdleSize
            let f = NSRect(x: overlayWindow.frame.origin.x, y: overlayWindow.frame.origin.y,
                           width: size.width, height: size.height)
            overlayWindow.setFrame(f, display: true, animate: false)
            idleView.frame = NSRect(origin: .zero, size: f.size)
            overlayWindow.contentView = idleView
        }
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
            idleView.setStatus("Screen Recording permission needed — System Settings → Privacy & Security")
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
        idleView.setStatus("\(sources.windows.count) capturable windows · right-click for menu\(axNote)")
    }

    private func rebuildMenu(_ menu: NSMenu) {
        SourcePickerMenu.populate(
            menu,
            sources: sources,
            thumbnails: thumbnails,
            capturedWindowID: captureManager.capturedWindowID,
            isCapturing: captureManager.isCapturing,
            hasCrop: captureManager.cropRect != nil,
            autoHideEnabled: autoHideEnabled,
            opacityPercent: Int((overlayOpacity * 100).rounded()),
            target: self,
            pickAction: #selector(pickWindow(_:)),
            stopAction: #selector(stopCapture),
            setCropAction: #selector(setCropRegion),
            clearCropAction: #selector(clearCropRegion),
            autoHideAction: #selector(toggleAutoHide(_:)),
            opacityAction: #selector(setOpacity(_:)),
            quitAction: #selector(quit)
        )
    }

    @objc func pickWindow(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? SCWindow else { return }
        let label = window.owningApplication?.applicationName ?? "source"
        let cropImmediately = sender.tag == 1
        sender.tag = 0  // reset so subsequent picks aren't sticky
        captureView.endCropSelection()
        captureView.cropRect = nil
        sourceAspect = nil
        // Drop any stale captured frames immediately so the user sees a clear
        // "Starting capture…" state, not the previous source's last frame.
        swapToIdle(message: "Starting capture of \(label)…")
        // Tell the visibility controller about the new source up front so a
        // didActivate notification arriving mid-start is correctly routed.
        visibilityController.setSource(
            bundle: window.owningApplication?.bundleIdentifier,
            pid: window.owningApplication?.processID
        )
        Task {
            do {
                try await captureManager.start(window: window)
            } catch {
                visibilityController.setSource(bundle: nil, pid: nil)
                swapToIdle(message: "Capture failed: \(error.localizedDescription)")
                return
            }
            // Safety net: if no frame within 2.5s, swap back so we don't show a black box.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if captureManager.capturedWindowID == window.windowID,
               overlayWindow.contentView !== captureView {
                await captureManager.stop()
                visibilityController.setSource(bundle: nil, pid: nil)
                swapToIdle(message: "\(label) didn't produce frames — try another window")
                return
            }
            if cropImmediately, overlayWindow.contentView === captureView {
                setCropRegion()
            }
        }
    }

    @objc func stopCapture() {
        captureView.endCropSelection()
        captureView.cropRect = nil
        Task {
            await captureManager.stop()
            visibilityController.setSource(bundle: nil, pid: nil)
            sourceAspect = nil
            swapToIdle(message: "Capture stopped")
        }
    }

    @objc func toggleAutoHide(_ sender: NSMenuItem) {
        autoHideEnabled.toggle()
        visibilityController.enabled = autoHideEnabled
    }

    @objc func setOpacity(_ sender: NSMenuItem) {
        let pct = max(10, min(100, sender.tag))
        overlayOpacity = CGFloat(pct) / 100.0
        clickThroughController.baseAlpha = overlayOpacity
    }

    @objc func setCropRegion() {
        guard captureManager.isCapturing else { return }
        captureView.beginCropSelection { [weak self] rect in
            self?.commitCrop(rect)
        }
    }

    @objc func clearCropRegion() {
        captureManager.applyCrop(nil)
        captureView.cropRect = nil
        if let aspect = sourceAspect {
            resizeOverlay(toAspect: aspect)
            captureView.resizeHandle.aspectRatio = aspect
        }
    }

    private var sourceAspect: CGFloat?

    private func commitCrop(_ rect: CGRect?) {
        guard let rect = rect, let source = sourceAspect else { return }
        captureManager.applyCrop(rect)
        captureView.cropRect = rect
        // Crop's physical aspect on the source = (cropW / cropH) * sourceAspect.
        let cropAspect = (rect.width / rect.height) * source
        resizeOverlay(toAspect: cropAspect)
        captureView.resizeHandle.aspectRatio = cropAspect
    }

    private func resizeOverlay(toAspect aspect: CGFloat) {
        let preferredWidth: CGFloat = max(Self.overlayMinSize.width, min(Self.overlayMaxSize.width, overlayWindow.frame.size.width))
        let preferredHeight = preferredWidth / aspect
        let clamped = clampToOverlayBounds(NSSize(width: preferredWidth, height: preferredHeight), aspect: aspect)
        var f = overlayWindow.frame
        f.origin.y -= (clamped.height - f.size.height)
        f.size = clamped
        overlayWindow.setFrame(f, display: true, animate: false)
        captureView.frame = NSRect(origin: .zero, size: clamped)
    }

    @objc func quit() { NSApp.terminate(nil) }

    private func autoCaptureLargest() async {
        guard let win = sources.windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            NSLog("PiPanything: PIP_AUTO_CAPTURE set but no windows available")
            return
        }
        NSLog("PiPanything: auto-capturing \(win.owningApplication?.applicationName ?? "?") — \(win.title ?? "")")
        do {
            try await captureManager.start(window: win)
        } catch {
            NSLog("PiPanything: auto-capture failed: \(error)")
        }
    }
}
