import Cocoa
import QuartzCore

/// Transparent overlay that captures mouse drags and renders a marquee.
/// Calls back with the normalized `CGRect` (in `[0,1]` view-space, bottom-left
/// origin so it can be passed straight to `CALayer.contentsRect`) on mouseUp,
/// or `nil` for cancel (ESC, click outside, or selection too tiny).
@MainActor
final class CropSelectionView: NSView {
    static let minNormalizedSize: CGFloat = 0.05

    private let onComplete: (CGRect?) -> Void
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    init(frame frameRect: NSRect, onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(dimLayer)
        layer?.addSublayer(borderLayer)

        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.5).cgColor
        dimLayer.fillRule = .evenOdd
        dimLayer.frame = bounds

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1.5
        borderLayer.lineDashPattern = [6, 4]
        borderLayer.frame = bounds

        rebuildPaths()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Prevent `isMovableByWindowBackground` from converting the drag into
    /// a window-move instead of a crop-selection.
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        dimLayer.frame = bounds
        borderLayer.frame = bounds
        rebuildPaths()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        startPoint = p
        currentPoint = p
        rebuildPaths()
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = clamp(convert(event.locationInWindow, from: nil), to: bounds)
        rebuildPaths()
    }

    override func mouseUp(with event: NSEvent) {
        defer { dismiss() }
        guard let start = startPoint, let end = currentPoint else {
            onComplete(nil)
            return
        }
        let rect = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        let normalized = CGRect(
            x: rect.minX / bounds.width,
            y: rect.minY / bounds.height,
            width: rect.width / bounds.width,
            height: rect.height / bounds.height
        )
        if normalized.width < Self.minNormalizedSize || normalized.height < Self.minNormalizedSize {
            onComplete(nil)
        } else {
            onComplete(normalized)
        }
    }

    override func keyDown(with event: NSEvent) {
        // ESC = 53.
        if event.keyCode == 53 {
            onComplete(nil)
            dismiss()
            return
        }
        super.keyDown(with: event)
    }

    private func dismiss() {
        removeFromSuperview()
    }

    private func clamp(_ point: NSPoint, to rect: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func selectionRect() -> NSRect? {
        guard let start = startPoint, let end = currentPoint else { return nil }
        return NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func rebuildPaths() {
        let outer = CGPath(rect: bounds, transform: nil)
        if let sel = selectionRect(), sel.width > 1, sel.height > 1 {
            let mutable = CGMutablePath()
            mutable.addRect(bounds)
            mutable.addRect(sel)
            dimLayer.path = mutable
            borderLayer.path = CGPath(rect: sel, transform: nil)
        } else {
            dimLayer.path = outer
            borderLayer.path = nil
        }
    }
}
