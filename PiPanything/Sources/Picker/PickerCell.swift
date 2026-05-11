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
import QuartzCore

/// Grid cell for the picker modal — edge-to-edge thumbnail with a gradient
/// caption overlay at the bottom (app name + window title). On hover the
/// caption hides and the thumbnail goes live: the hovered window is polled
/// via the project's dlsym `legacyCaptureWindow` path so the preview reflects
/// the current state of that window, including cross-Space sources.
@MainActor
final class PickerCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("PickerCell")
    static let cellSize = NSSize(width: 240, height: 150)

    private let thumbnailLayer = CALayer()
    private let gradientLayer = CAGradientLayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    private var windowID: CGWindowID?
    private var snapshotContents: CGImage?
    private var livePollTimer: Timer?

    private var isHovered = false { didSet { applyHoverState() } }

    override func loadView() {
        let host = HoverView()
        host.frame = NSRect(origin: .zero, size: Self.cellSize)
        host.wantsLayer = true
        view = host

        guard let cardLayer = host.layer else { return }
        cardLayer.cornerRadius = 10
        cardLayer.masksToBounds = true
        cardLayer.borderWidth = 0.5
        cardLayer.borderColor = NSColor.separatorColor.cgColor
        cardLayer.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor

        thumbnailLayer.contentsGravity = .resizeAspectFill
        thumbnailLayer.masksToBounds = true
        thumbnailLayer.frame = host.bounds
        thumbnailLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        cardLayer.addSublayer(thumbnailLayer)

        gradientLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.65).cgColor,
            NSColor.black.withAlphaComponent(0.85).cgColor,
        ]
        gradientLayer.locations = [0.0, 0.55, 1.0]
        gradientLayer.frame = NSRect(
            x: 0, y: 0,
            width: Self.cellSize.width,
            height: 60
        )
        gradientLayer.autoresizingMask = [.layerWidthSizable, .layerMaxYMargin]
        cardLayer.addSublayer(gradientLayer)

        let inset: CGFloat = 10

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: inset, y: inset + 16, width: Self.cellSize.width - inset * 2, height: 14)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.drawsBackground = false; titleLabel.isBezeled = false
        titleLabel.autoresizingMask = [.width, .maxYMargin]
        host.addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        subtitleLabel.frame = NSRect(x: inset, y: inset, width: Self.cellSize.width - inset * 2, height: 12)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.drawsBackground = false; subtitleLabel.isBezeled = false
        subtitleLabel.autoresizingMask = [.width, .maxYMargin]
        host.addSubview(subtitleLabel)

        host.onHoverChange = { [weak self] hovered in
            self?.isHovered = hovered
        }
    }

    func configure(windowID: CGWindowID, image: NSImage?, appName: String, title: String, isCurrent: Bool) {
        stopLivePolling()
        self.windowID = windowID
        let cg = image.flatMap { cgImage(from: $0) }
        self.snapshotContents = cg
        setLayerContents(cg)
        titleLabel.stringValue = isCurrent ? "● \(appName)" : appName
        subtitleLabel.stringValue = title
        if isHovered {
            startLivePolling()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopLivePolling()
        // Reset the hover-driven hide so the next configure renders the caption.
        if isHovered {
            isHovered = false
        }
    }

    // MARK: - Hover state

    private func applyHoverState() {
        guard let layer = view.layer else { return }
        gradientLayer.isHidden = isHovered
        titleLabel.isHidden = isHovered
        subtitleLabel.isHidden = isHovered
        if isHovered {
            layer.borderWidth = 2
            layer.borderColor = NSColor.controlAccentColor.cgColor
            startLivePolling()
        } else {
            layer.borderWidth = 0.5
            layer.borderColor = NSColor.separatorColor.cgColor
            stopLivePolling()
            setLayerContents(snapshotContents)
        }
    }

    // MARK: - Live polling

    private func startLivePolling() {
        guard livePollTimer == nil, let wid = windowID else { return }
        tickLiveFrame(for: wid)
        let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            // Timer is scheduled on the main run loop, so the closure runs on
            // the main thread even though its type is @Sendable. Hop into the
            // main actor explicitly to access PickerCell state.
            MainActor.assumeIsolated {
                guard let self = self, let wid = self.windowID else { return }
                self.tickLiveFrame(for: wid)
            }
        }
        // Track on common modes so the timer keeps firing during scroll.
        RunLoop.main.add(timer, forMode: .common)
        livePollTimer = timer
    }

    private func stopLivePolling() {
        livePollTimer?.invalidate()
        livePollTimer = nil
    }

    private func tickLiveFrame(for wid: CGWindowID) {
        guard let cg = legacyCaptureWindow(wid) else { return }
        let target = CGSize(width: Self.cellSize.width * 2, height: Self.cellSize.height * 2)
        let scaled = downsampledCGImage(cg, fittingIn: target) ?? cg
        setLayerContents(scaled)
    }

    // MARK: - Helpers

    private func setLayerContents(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thumbnailLayer.contents = image
        CATransaction.commit()
    }

    private func cgImage(from image: NSImage) -> CGImage? {
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

/// Tiny NSView that forwards hover events to the owning cell. Lets PickerCell
/// stay free of NSView subclassing while still tracking mouse enter/exit.
@MainActor
private final class HoverView: NSView {
    var onHoverChange: ((Bool) -> Void)?
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
}
