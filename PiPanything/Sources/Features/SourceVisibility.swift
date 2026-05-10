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

    /// User-pinned hide via the `⌃⌥H` global hotkey. While true, the overlay
    /// stays hidden regardless of the auto-hide computation. Toggle off to let
    /// the normal frontmost-app logic resume.
    private(set) var manuallyHidden = false

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

    func toggleManualHide() {
        manuallyHidden.toggle()
        applyState()
    }

    /// Same as `toggleManualHide()` but with explicit state — used by the
    /// app-level global panic-hide hotkey so all sessions land in the same
    /// state regardless of where each started.
    func setManualHide(_ hidden: Bool) {
        guard manuallyHidden != hidden else { return }
        manuallyHidden = hidden
        applyState()
    }

    private func applyState() {
        guard let window = overlayWindow else { return }
        if manuallyHidden {
            window.orderOut(nil)
            return
        }
        // Disabled controllers must sit silent, not force the window visible.
        // In multi-tab sessions, only the active tab's controller is enabled;
        // if disabled controllers fell through to `orderFrontRegardless`,
        // they'd fight the active one on every NSWorkspace activation event.
        guard enabled else { return }
        guard let bundle = sourceBundle else {
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
