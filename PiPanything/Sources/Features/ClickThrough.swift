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

/// Toggles `overlayWindow.ignoresMouseEvents` based on whether the Option
/// modifier is held while the cursor is over the overlay. The intent: hover
/// over the PiP, hold ⌥, click goes through to the app underneath.
@MainActor
final class ClickThroughController {
    private weak var overlayWindow: OverlayWindow?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var optionHeld = false

    /// User-selected base opacity (0...1). The actual `alphaValue` we set is
    /// this multiplied by the click-through dim when ⌥ is held.
    var baseAlpha: CGFloat = 1.0 {
        didSet { applyState() }
    }

    init(overlayWindow: OverlayWindow) {
        self.overlayWindow = overlayWindow
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .mouseMoved]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.handle()
        }
    }

    deinit {
        if let l = localMonitor { NSEvent.removeMonitor(l) }
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
    }

    private func handle() {
        // Always read the current modifier state — never trust accumulated
        // state from `.flagsChanged` events, which can drop release events
        // when the cursor crosses app boundaries.
        optionHeld = NSEvent.modifierFlags.contains(.option)
        applyState()
    }

    private func applyState() {
        guard let window = overlayWindow else { return }
        let cursor = NSEvent.mouseLocation
        let overOverlay = window.isVisible && window.frame.contains(cursor)
        let shouldIgnore = optionHeld && overOverlay
        if window.ignoresMouseEvents != shouldIgnore {
            window.ignoresMouseEvents = shouldIgnore
        }
        // Combine user-set opacity with click-through dim.
        let target = baseAlpha * (shouldIgnore ? 0.7 : 1.0)
        if abs(window.alphaValue - target) > 0.001 {
            window.alphaValue = target
        }
    }
}
