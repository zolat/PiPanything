import Cocoa

/// Observes `NSWorkspace` to auto-show/hide the overlay based on whether the
/// captured source's app is currently frontmost. Also detects when the source
/// app quits so the host can swap back to idle.
@MainActor
final class SourceVisibilityController {
    private weak var overlayWindow: OverlayWindow?
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?

    var enabled: Bool = true {
        didSet { applyState() }
    }

    private(set) var sourceBundle: String?
    private(set) var sourcePID: pid_t?

    var onSourceTerminated: (() -> Void)?

    init(overlayWindow: OverlayWindow) {
        self.overlayWindow = overlayWindow
        let nc = NSWorkspace.shared.notificationCenter
        activationObserver = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.applyState()
            }
        }
        terminationObserver = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.handleTermination(note)
            }
        }
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        if let activationObserver { nc.removeObserver(activationObserver) }
        if let terminationObserver { nc.removeObserver(terminationObserver) }
    }

    func setSource(bundle: String?, pid: pid_t?) {
        sourceBundle = bundle
        sourcePID = pid
        applyState()
    }

    private func applyState() {
        guard let window = overlayWindow else { return }
        guard enabled, let bundle = sourceBundle else {
            window.orderFrontRegardless()
            return
        }
        let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if frontBundle == bundle {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    private func handleTermination(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if let pid = sourcePID, app.processIdentifier == pid {
            sourceBundle = nil
            sourcePID = nil
            onSourceTerminated?()
            applyState()
        }
    }
}
