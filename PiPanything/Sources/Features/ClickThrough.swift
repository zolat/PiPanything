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

/// Latched click-through controller. When `latched == true`, the host window
/// becomes click-through (`ignoresMouseEvents`) and is dimmed by
/// `Settings.shared.clickThroughOpacity`. The latch is flipped externally
/// (`OverlaySession.clickThroughLatched`) — the controller itself is just
/// the rendering policy.
@MainActor
final class ClickThroughController {
    private weak var overlayWindow: OverlayWindow?

    /// User-selected base opacity (0...1). The actual `alphaValue` we set is
    /// this multiplied by the click-through dim factor when the latch is on.
    var baseAlpha: CGFloat = 1.0 {
        didSet { applyState() }
    }

    /// True when the user has latched click-through on this overlay (via the
    /// right-click menu or a hotkey). Persists across modifier releases —
    /// only changes when toggled again.
    var latched: Bool = false {
        didSet { applyState() }
    }

    init(overlayWindow: OverlayWindow) {
        self.overlayWindow = overlayWindow
    }

    /// Re-evaluate and push current state to the window. Public so the
    /// status-menu broadcast can flush a settings change (new dim factor)
    /// across every live session without each session needing a setter call.
    func reapply() {
        applyState()
    }

    private func applyState() {
        guard let window = overlayWindow else { return }
        let shouldIgnore = latched
        if window.ignoresMouseEvents != shouldIgnore {
            window.ignoresMouseEvents = shouldIgnore
        }
        let dimFactor = CGFloat(Settings.shared.clickThroughOpacity) / 100.0
        let target = baseAlpha * (shouldIgnore ? dimFactor : 1.0)
        if abs(window.alphaValue - target) > 0.001 {
            window.alphaValue = target
        }
    }
}
