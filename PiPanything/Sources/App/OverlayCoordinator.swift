import Cocoa
import ScreenCaptureKit

/// Owns the live `OverlaySession`s. Phase 2 introduces this even though only
/// one session exists at runtime — Phase 3 flips to N sessions and the
/// coordinator becomes load-bearing.
@MainActor
final class OverlayCoordinator {
    private(set) var sessions: [OverlaySession] = []

    static let softCap = 4
    private static let initialFrame = NSRect(x: 240, y: 240, width: 380, height: 230)
    private static let cascadeOffset: CGFloat = 32

    /// Creates a fresh idle session and tracks it. Phase 3 cascades the spawn
    /// origin so sibling overlays don't stack directly on top of each other.
    @discardableResult
    func add() -> OverlaySession {
        let frame = nextSpawnFrame()
        let session = OverlaySession(initialFrame: frame)
        sessions.append(session)
        return session
    }

    func remove(_ id: OverlayID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions.remove(at: idx)
        session.close()
    }

    func stopAll() {
        for session in sessions { session.stop() }
    }

    func session(id: OverlayID) -> OverlaySession? {
        sessions.first(where: { $0.id == id })
    }

    /// First session that's currently capturing the given window. Used by the
    /// picker to surface "this source is already an overlay" hints.
    func session(forWindowID id: CGWindowID) -> OverlaySession? {
        sessions.first(where: { $0.capturedWindowID == id })
    }

    /// Convenience for the single-session paths that survive into Phase 2.
    var primary: OverlaySession? { sessions.first }

    var isAtSoftCap: Bool { sessions.count >= Self.softCap }

    /// Cascade subsequent overlays down-and-right from the most recent one,
    /// wrapping back to the initial origin when we'd fall off the screen.
    private func nextSpawnFrame() -> NSRect {
        guard let last = sessions.last else { return Self.initialFrame }
        let lastFrame = last.window.frame
        var origin = NSPoint(
            x: lastFrame.origin.x + Self.cascadeOffset,
            y: lastFrame.origin.y - Self.cascadeOffset
        )
        if let screen = last.window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            // Wrap back if the new origin would push the title-less window
            // off-screen on either axis.
            if origin.x + Self.initialFrame.width > visible.maxX
                || origin.y < visible.minY {
                origin = Self.initialFrame.origin
            }
        }
        return NSRect(origin: origin, size: Self.initialFrame.size)
    }
}
