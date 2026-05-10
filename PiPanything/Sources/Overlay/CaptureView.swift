import Cocoa
import AVFoundation
import QuartzCore

final class CaptureView: NSView {
    let displayLayer: AVSampleBufferDisplayLayer
    let imageLayer: CALayer
    let resizeHandle = ResizeHandle()

    /// Normalized [0,1] crop rect. `nil` = full source. The layer-frame
    /// translate trick is used instead of `contentsRect` because
    /// `AVSampleBufferDisplayLayer` does not honor `contentsRect` for video.
    var cropRect: CGRect? {
        didSet { updateLayerFrames() }
    }

    init(frame: NSRect, displayLayer: AVSampleBufferDisplayLayer, imageLayer: CALayer) {
        self.displayLayer = displayLayer
        self.imageLayer = imageLayer
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(displayLayer)
        layer?.addSublayer(imageLayer)
        updateLayerFrames()
        addSubview(resizeHandle)
        positionResizeHandle()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func positionResizeHandle() {
        let s = ResizeHandle.size
        resizeHandle.frame = NSRect(x: bounds.width - s, y: 0, width: s, height: s)
    }

    override func layout() {
        super.layout()
        updateLayerFrames()
        positionResizeHandle()
    }

    private func updateLayerFrames() {
        let crop = cropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let cw = max(0.0001, crop.width)
        let ch = max(0.0001, crop.height)
        let layerWidth = bounds.width / cw
        let layerHeight = bounds.height / ch
        let originX = -crop.minX * layerWidth
        let originY = -crop.minY * layerHeight
        let frame = CGRect(x: originX, y: originY, width: layerWidth, height: layerHeight)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = frame
        imageLayer.frame = frame
        CATransaction.commit()
    }

    func showMode(_ mode: CaptureMode) {
        switch mode {
        case .stream:
            displayLayer.isHidden = false
            imageLayer.isHidden = true
        case .polling:
            displayLayer.isHidden = true
            imageLayer.isHidden = false
        case .idle:
            displayLayer.isHidden = true
            imageLayer.isHidden = true
        }
    }

    private weak var activeCropSelection: CropSelectionView?

    func beginCropSelection(onComplete: @escaping (CGRect?) -> Void) {
        endCropSelection()
        let view = CropSelectionView(frame: bounds) { [weak self] rect in
            self?.activeCropSelection = nil
            onComplete(rect)
        }
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        activeCropSelection = view
        view.window?.makeFirstResponder(view)
    }

    func endCropSelection() {
        activeCropSelection?.removeFromSuperview()
        activeCropSelection = nil
    }
}
