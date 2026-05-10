import Cocoa
import ScreenCaptureKit
import AVFoundation
import CoreMedia

enum CaptureMode {
    case idle
    case stream
    case polling
}

@MainActor
final class CaptureManager: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var pollingTimer: Timer?
    let displayLayer = AVSampleBufferDisplayLayer()
    let imageLayer = CALayer()
    var onFirstFrame: ((CGSize) -> Void)?
    var onError: ((Error) -> Void)?
    var onModeChange: ((CaptureMode) -> Void)?
    private(set) var capturedWindowID: CGWindowID?
    private(set) var capturedSourceBundle: String?
    private(set) var capturedSourcePID: pid_t?
    private(set) var capturedSourceName: String?
    private(set) var mode: CaptureMode = .idle
    /// Normalized [0,1] sub-rect of the source that should be visible.
    /// `nil` means "full image". Applied to both `displayLayer.contentsRect`
    /// and `imageLayer.contentsRect` so it survives stream↔polling swaps.
    private(set) var cropRect: CGRect?
    private var firstFrameReported = false

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.backgroundColor = NSColor.black.cgColor
    }

    var isCapturing: Bool { mode != .idle }

    func start(window: SCWindow) async throws {
        await stop()
        capturedWindowID = window.windowID
        capturedSourceBundle = window.owningApplication?.bundleIdentifier
        capturedSourcePID = window.owningApplication?.processID
        capturedSourceName = window.owningApplication?.applicationName
        firstFrameReported = false

        // Try ScreenCaptureKit first — best quality / lowest CPU on the active Space.
        do {
            try await startSCStream(window: window)
            setMode(.stream)
        } catch {
            NSLog("PiPanything: SCStream start failed (\(error)), falling back to polling")
            startPolling(window: window)
            setMode(.polling)
            return
        }

        // Wait up to 1s for an SCStream frame. If none arrives the source is on a
        // non-rendering Space — switch to CGWindowList polling (works cross-Space).
        for _ in 0..<10 {
            if firstFrameReported { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !firstFrameReported else { return }
        NSLog("PiPanything: SCStream produced no frames in 1s — switching to polling fallback")
        await stopSCStream()
        startPolling(window: window)
        setMode(.polling)
    }

    func stop() async {
        await stopSCStream()
        stopPolling()
        capturedWindowID = nil
        capturedSourceBundle = nil
        capturedSourcePID = nil
        capturedSourceName = nil
        cropRect = nil
        firstFrameReported = false
        setMode(.idle)
    }

    /// Storage for the active crop rect. The actual layer-level cropping
    /// happens in `CaptureView` via the frame-translate trick because
    /// `AVSampleBufferDisplayLayer` ignores `contentsRect` for video.
    func applyCrop(_ rect: CGRect?) {
        cropRect = rect
    }

    private func setMode(_ newMode: CaptureMode) {
        mode = newMode
        onModeChange?(newMode)
    }

    private func startSCStream(window: SCWindow) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let w = max(2, Int(window.frame.width * scale))
        let h = max(2, Int(window.frame.height * scale))
        config.width = w
        config.height = h
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 5
        config.showsCursor = false

        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await s.startCapture()
        stream = s
        NSLog("PiPanything: SCStream started for windowID=\(window.windowID) \(w)x\(h)")
    }

    private func stopSCStream() async {
        if let s = stream {
            try? await s.stopCapture()
        }
        stream = nil
    }

    private func startPolling(window: SCWindow) {
        let id = window.windowID
        let timer = Timer(timeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickPoll(windowID: id)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
        NSLog("PiPanything: polling fallback started for windowID=\(id)")
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func tickPoll(windowID: CGWindowID) {
        guard let image = legacyCaptureWindow(windowID) else {
            if !firstFrameReported {
                NSLog("PiPanything: tickPoll legacyCaptureWindow returned nil for windowID=\(windowID)")
            }
            return
        }
        guard image.width > 1, image.height > 1 else {
            if !firstFrameReported {
                NSLog("PiPanything: tickPoll image too small \(image.width)x\(image.height)")
            }
            return
        }
        imageLayer.contents = image
        if !firstFrameReported {
            firstFrameReported = true
            NSLog("PiPanything: polling first frame \(image.width)x\(image.height)")
            onFirstFrame?(CGSize(width: image.width, height: image.height))
        }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }

        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusRaw = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete else { return }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if !self.firstFrameReported, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                self.firstFrameReported = true
                let size = CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
                self.onFirstFrame?(size)
            }
            if self.displayLayer.isReadyForMoreMediaData {
                self.displayLayer.enqueue(sampleBuffer)
            }
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            NSLog("PiPanything: stream stopped with error: \(error)")
            self?.onError?(error)
            self?.stream = nil
        }
    }
}
