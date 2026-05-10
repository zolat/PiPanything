import Cocoa

/// Snapshot of one tab as the strip sees it. Built by OverlaySession.
struct TabStripModel {
    let id: OverlayTabID
    let appName: String
    let title: String
    let icon: NSImage?
    let isActive: Bool
}

/// Auto-hide tab strip pinned to the top of an overlay window. Renders one
/// pill per tab (app icon + label + close X). Hidden by default; revealed
/// when the cursor enters the overlay window. Suppressed while ⌥ is held so
/// it doesn't fight the click-through-on-⌥-hover gesture.
@MainActor
final class TabStripView: NSView {
    static let height: CGFloat = 30
    private static let pillSpacing: CGFloat = 4
    private static let pillPadding: CGFloat = 8
    private static let pillMaxWidth: CGFloat = 200
    private static let pillMinWidth: CGFloat = 80
    private static let iconSize: CGFloat = 16
    private static let closeSize: CGFloat = 14
    private static let revealAnimation: TimeInterval = 0.18
    private static let dwellBeforeHide: TimeInterval = 0.3

    var onSwitch: ((OverlayTabID) -> Void)?
    var onClose: ((OverlayTabID) -> Void)?
    var onRightClick: ((OverlayTabID, NSEvent) -> Void)?

    private var models: [TabStripModel] = []
    private var pills: [TabPillView] = []
    private var trackingArea: NSTrackingArea?
    private var hideTimer: Timer?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: Self.height))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        layer?.cornerRadius = 8
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        alphaValue = 0
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Critical: prevents `OverlayWindow.isMovableByWindowBackground` from
    /// stealing clicks on the strip and dragging the whole window instead of
    /// switching tabs. Mirrors `ResizeHandle`'s pattern.
    override var mouseDownCanMoveWindow: Bool { false }

    /// Update the strip's data and re-render pills. Called by OverlaySession
    /// whenever tabs change (add / close / switch / label change).
    func update(_ models: [TabStripModel]) {
        self.models = models
        rebuildPills()
        // Hide entirely when there's nothing to switch between.
        let shouldExist = models.count >= 2
        isHidden = !shouldExist
        if !shouldExist {
            stopRevealAnimation()
            alphaValue = 0
        }
    }

    private func rebuildPills() {
        for pill in pills { pill.removeFromSuperview() }
        pills.removeAll()
        var x: CGFloat = Self.pillPadding
        let y: CGFloat = (bounds.height - (Self.height - 6)) / 2
        let pillHeight = Self.height - 6
        for model in models {
            let label = model.title.isEmpty ? model.appName : "\(model.appName) — \(model.title)"
            let approxWidth = TabPillView.preferredWidth(for: label)
            let width = max(Self.pillMinWidth, min(Self.pillMaxWidth, approxWidth))
            let pill = TabPillView(model: model)
            pill.frame = NSRect(x: x, y: y, width: width, height: pillHeight)
            pill.onTap = { [weak self] in self?.onSwitch?(model.id) }
            pill.onClose = { [weak self] in self?.onClose?(model.id) }
            pill.onRightClick = { [weak self, weak pill] event in
                guard let pill = pill else { return }
                _ = pill  // explicitly capture so xcode compiler keeps the closure
                self?.onRightClick?(model.id, event)
            }
            addSubview(pill)
            pills.append(pill)
            x += width + Self.pillSpacing
        }
    }

    override func layout() {
        super.layout()
        // Re-layout pills from left at fixed positions; today no flex.
        rebuildPills()
    }

    // MARK: - Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Track the whole window area, not just the strip — we want the strip
        // to fade in as soon as the cursor enters the overlay anywhere.
        // Critical: the tracking area must be installed on the *superview*,
        // not on the strip itself. `.inVisibleRect` follows the visible rect
        // of the view it's installed on; if installed on the strip (~30pt
        // high), it would only fire when the cursor entered an invisible
        // top sliver. Strip stays the owner so its mouseEntered handlers run.
        if let existing = trackingArea {
            (existing.owner as? NSView)?.removeTrackingArea(existing)
        }
        guard let host = superview else { return }
        let area = NSTrackingArea(
            rect: host.bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        host.addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        // Force tracking-area refresh now that we have a superview to attach to.
        updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        // Suppress while ⌥ is held so click-through-on-⌥-hover isn't fighting
        // strip-reveal-on-hover.
        if NSEvent.modifierFlags.contains(.option) { return }
        startRevealAnimation()
    }

    override func mouseMoved(with event: NSEvent) {
        if NSEvent.modifierFlags.contains(.option) {
            // ⌥ held mid-hover — collapse the strip.
            scheduleHide()
        } else if alphaValue < 1 {
            startRevealAnimation()
        }
    }

    override func mouseExited(with event: NSEvent) {
        scheduleHide()
    }

    private func startRevealAnimation() {
        hideTimer?.invalidate()
        hideTimer = nil
        guard !isHidden else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.revealAnimation
            self.animator().alphaValue = 1
        }
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.dwellBeforeHide, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fadeOut() }
        }
    }

    private func stopRevealAnimation() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func fadeOut() {
        guard !isHidden else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.revealAnimation
            self.animator().alphaValue = 0
        }
    }
}

/// Single tab pill — app icon + truncated label + close X.
@MainActor
final class TabPillView: NSView {
    private let model: TabStripModel
    private let iconView = NSImageView()
    private let labelView = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "×", target: nil, action: nil)

    var onTap: (() -> Void)?
    var onClose: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    init(model: TabStripModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = (model.isActive
            ? NSColor.controlAccentColor.withAlphaComponent(0.85)
            : NSColor.white.withAlphaComponent(0.12)).cgColor

        iconView.image = model.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        labelView.stringValue = model.title.isEmpty ? model.appName : model.appName
        labelView.font = .systemFont(ofSize: 11, weight: model.isActive ? .semibold : .regular)
        labelView.textColor = model.isActive ? .white : .labelColor
        labelView.lineBreakMode = .byTruncatingTail
        labelView.maximumNumberOfLines = 1
        labelView.cell?.usesSingleLineMode = true
        labelView.drawsBackground = false
        labelView.isBezeled = false
        addSubview(labelView)

        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 13, weight: .bold)
        closeButton.contentTintColor = model.isActive ? .white : .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Same reason as TabStripView — the pill is the actual click target;
    /// without this, clicking a tab would drag the window.
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        let pad: CGFloat = 6
        let iconSide: CGFloat = 16
        let closeSide: CGFloat = 18
        iconView.frame = NSRect(x: pad, y: (bounds.height - iconSide) / 2, width: iconSide, height: iconSide)
        closeButton.frame = NSRect(x: bounds.width - closeSide - pad, y: (bounds.height - closeSide) / 2,
                                   width: closeSide, height: closeSide)
        let labelX = iconView.frame.maxX + 4
        labelView.frame = NSRect(x: labelX, y: 0,
                                 width: closeButton.frame.minX - labelX - 2,
                                 height: bounds.height)
    }

    static func preferredWidth(for label: String) -> CGFloat {
        // Rough text-width estimate; we mostly just clamp to min/max in the
        // strip layout, so this just needs to be in the right neighborhood.
        let approxCharWidth: CGFloat = 6.5
        return 6 + 16 + 4 + CGFloat(label.count) * approxCharWidth + 4 + 18 + 6
    }

    override func mouseDown(with event: NSEvent) {
        onTap?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    @objc private func handleClose() {
        onClose?()
    }
}
