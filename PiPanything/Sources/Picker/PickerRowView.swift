import Cocoa

final class PickerRowView: NSView {
    static let rowSize = NSSize(width: 320, height: 220)
    private static let inset: CGFloat = 12
    private static let textBlockHeight: CGFloat = 36

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    init(image: NSImage?, title: String, subtitle: String, isCurrent: Bool) {
        super.init(frame: NSRect(origin: .zero, size: Self.rowSize))
        setup(image: image, title: title, subtitle: subtitle, isCurrent: isCurrent)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func setup(image: NSImage?, title: String, subtitle: String, isCurrent: Bool) {
        wantsLayer = true
        let inset = Self.inset
        let textBlockHeight = Self.textBlockHeight
        let imageRect = NSRect(
            x: inset,
            y: inset + textBlockHeight,
            width: bounds.width - inset * 2,
            height: bounds.height - inset * 2 - textBlockHeight
        )

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.frame = imageRect
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 0.5
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        addSubview(imageView)

        titleLabel.stringValue = isCurrent ? "● \(title)" : title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: inset, y: inset + 18, width: bounds.width - inset * 2, height: 16)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.drawsBackground = false; titleLabel.isBezeled = false
        addSubview(titleLabel)

        subtitleLabel.stringValue = subtitle
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.frame = NSRect(x: inset, y: inset + 2, width: bounds.width - inset * 2, height: 14)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.drawsBackground = false; subtitleLabel.isBezeled = false
        addSubview(subtitleLabel)
    }

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

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem,
              let menu = item.menu else { return }
        // Tag the item so the action handler can tell whether ⌥ was held.
        item.tag = event.modifierFlags.contains(.option) ? 1 : 0
        menu.cancelTracking()
        // Defer so the menu finishes dismissing before we run the action.
        let target = item.target
        let action = item.action
        DispatchQueue.main.async {
            if let action = action {
                _ = target?.perform(action, with: item)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHovered {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 8, yRadius: 8)
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            path.fill()
        }
    }
}
