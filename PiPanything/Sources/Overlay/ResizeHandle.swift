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

/// A small grip view that lives in the overlay's bottom-right corner. Drags
/// resize the host window, locked to a configurable aspect ratio. Consumes
/// mouseDown / mouseDragged so the window's `isMovableByWindowBackground`
/// drag-to-move doesn't fight the resize.
final class ResizeHandle: NSView {
    static let size: CGFloat = 18

    var aspectRatio: CGFloat = 16.0 / 9.0
    var minSize: NSSize = NSSize(width: 240, height: 160)
    var maxSize: NSSize = NSSize(width: 1600, height: 1200)
    /// When false, the drag resizes width/height independently — used for
    /// tabbed overlays where each tab has its own aspect, so locking to one
    /// would awkwardly letterbox the others.
    var lockAspect: Bool = true

    private var startFrame: NSRect = .zero
    private var startMouse: NSPoint = .zero

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Critical: prevents `isMovableByWindowBackground` from stealing the
    /// drag and moving the whole window instead of resizing.
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Make sure clicks in our bounds always reach us, even if a sibling
        // layer (display/image) sits at the same level visually.
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : super.hitTest(point)
    }

    override func resetCursorRects() {
        // Public macOS doesn't expose a diagonal resize cursor; crosshair
        // signals "you can drag here" without misleading the user.
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        startFrame = window.frame
        startMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - startMouse.x
        // Dragging down (negative dy in screen coords) should grow height.
        let dy = startMouse.y - now.y

        var newWidth: CGFloat
        var newHeight: CGFloat

        if lockAspect {
            // Drive resize from whichever axis the user pushed further.
            // Compute the candidate new width from each delta, then pick
            // whichever implies the larger window.
            let widthFromX = startFrame.size.width + dx
            let heightFromY = startFrame.size.height + dy
            let widthFromYDelta = heightFromY * aspectRatio
            newWidth = max(widthFromX, widthFromYDelta)

            // Clamp to bounds, preserving aspect.
            if newWidth < minSize.width { newWidth = minSize.width }
            if newWidth > maxSize.width { newWidth = maxSize.width }
            newHeight = newWidth / aspectRatio
            if newHeight < minSize.height {
                newHeight = minSize.height
                newWidth = newHeight * aspectRatio
            }
            if newHeight > maxSize.height {
                newHeight = maxSize.height
                newWidth = newHeight * aspectRatio
            }
        } else {
            // Free resize: width and height move independently with the drag.
            newWidth = max(minSize.width, min(maxSize.width, startFrame.size.width + dx))
            newHeight = max(minSize.height, min(maxSize.height, startFrame.size.height + dy))
        }

        // Final defensive clamp. The branch logic above should already keep us
        // ≥ min and ≤ max, but NaN aspect ratios or other edge cases could
        // poison `max`/comparison ops (NaN compares false to everything), so
        // bound one more time before committing the frame.
        if !newWidth.isFinite || newWidth < minSize.width { newWidth = minSize.width }
        if !newHeight.isFinite || newHeight < minSize.height { newHeight = minSize.height }
        if newWidth > maxSize.width { newWidth = maxSize.width }
        if newHeight > maxSize.height { newHeight = maxSize.height }

        // Keep top-left fixed (the grip is bottom-right; that corner moves).
        var newFrame = startFrame
        newFrame.origin.y = startFrame.origin.y + (startFrame.size.height - newHeight)
        newFrame.size = NSSize(width: newWidth, height: newHeight)
        window.setFrame(newFrame, display: true, animate: false)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Three diagonal lines, like the macOS standard textured-button grip.
        let color = NSColor.white.withAlphaComponent(0.55)
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        let inset: CGFloat = 4
        for i in 0..<3 {
            let offset = CGFloat(i) * 4
            path.move(to: NSPoint(x: bounds.width - inset - offset, y: inset))
            path.line(to: NSPoint(x: bounds.width - inset, y: inset + offset))
        }
        path.stroke()
    }
}
