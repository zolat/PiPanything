import Cocoa

final class OverlayWindow: NSWindow {
    var onContextMenu: ((NSEvent) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown {
            onContextMenu?(event)
            return
        }
        super.sendEvent(event)
    }
}
