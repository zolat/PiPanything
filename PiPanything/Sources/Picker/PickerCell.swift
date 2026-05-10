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

/// Grid cell for the picker modal — thumbnail on top, app name + window title
/// below. Hover highlights the cell; the "●" prefix marks windows already
/// driving an overlay so the user doesn't pick the same source twice.
@MainActor
final class PickerCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("PickerCell")
    static let cellSize = NSSize(width: 240, height: 170)

    private let imageView_ = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { view.needsDisplay = true }
    }

    override func loadView() {
        view = HoverView()
        view.frame = NSRect(origin: .zero, size: Self.cellSize)
        view.wantsLayer = true

        let inset: CGFloat = 10
        let textBlockHeight: CGFloat = 32
        let imageRect = NSRect(
            x: inset,
            y: inset + textBlockHeight,
            width: Self.cellSize.width - inset * 2,
            height: Self.cellSize.height - inset * 2 - textBlockHeight
        )

        imageView_.imageScaling = .scaleProportionallyUpOrDown
        imageView_.imageAlignment = .alignCenter
        imageView_.frame = imageRect
        imageView_.wantsLayer = true
        imageView_.layer?.cornerRadius = 6
        imageView_.layer?.masksToBounds = true
        imageView_.layer?.borderWidth = 0.5
        imageView_.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView_.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        view.addSubview(imageView_)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: inset, y: inset + 16, width: Self.cellSize.width - inset * 2, height: 14)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.drawsBackground = false; titleLabel.isBezeled = false
        view.addSubview(titleLabel)

        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.frame = NSRect(x: inset, y: inset + 2, width: Self.cellSize.width - inset * 2, height: 12)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.drawsBackground = false; subtitleLabel.isBezeled = false
        view.addSubview(subtitleLabel)

        if let host = view as? HoverView {
            host.onHoverChange = { [weak self] hovered in
                self?.isHovered = hovered
            }
            host.onDraw = { [weak self] dirty in
                self?.drawBackground(dirty)
            }
        }
    }

    func configure(image: NSImage?, appName: String, title: String, isCurrent: Bool) {
        imageView_.image = image
        titleLabel.stringValue = isCurrent ? "● \(appName)" : appName
        subtitleLabel.stringValue = title
    }

    private func drawBackground(_ dirtyRect: NSRect) {
        guard isHovered else { return }
        let path = NSBezierPath(
            roundedRect: view.bounds.insetBy(dx: 3, dy: 3),
            xRadius: 8, yRadius: 8
        )
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        path.fill()
    }
}

/// Tiny NSView that forwards hover and draw events to the owning cell. Lets
/// PickerCell stay value-shaped without subclassing NSView in two places.
@MainActor
private final class HoverView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    var onDraw: ((NSRect) -> Void)?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        onDraw?(dirtyRect)
    }
}
