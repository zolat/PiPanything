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

final class OverlayWindow: NSWindow {
    var onContextMenu: ((NSEvent) -> Void)?
    var onModifierActivate: ((NSEvent) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        // Intercept at sendEvent (rather than via a view's mouseDown) so the
        // window's drag-to-move gesture doesn't consume the click before we
        // see it — same trick as the rightMouseDown branch below.
        // Exact-`.command` (not `.contains(.command)`) lets ⌘⇧/⌘⌥-click fall
        // through to normal handling.
        if event.type == .leftMouseDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let onModifierActivate {
            onModifierActivate(event)
            return
        }
        if event.type == .rightMouseDown {
            onContextMenu?(event)
            return
        }
        super.sendEvent(event)
    }
}
