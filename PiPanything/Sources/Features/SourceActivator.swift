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

/// Brings the original source of a PIP capture forward in two steps:
///
/// 1. Accessibility designates *which* window of the source app is the
///    main window (un-minimising it if needed and performing AXRaise).
/// 2. `NSRunningApplication.activate` brings the app to the foreground,
///    which is what triggers macOS's automatic Space switch when the
///    chosen window lives on another (fullscreen or regular) Space.
///
/// Step 1 may fail silently (window closed since capture, AX denied for
/// the target app, etc.); step 2 is run unconditionally so the user
/// still lands in the right app even if the precise window can't be
/// targeted.
@MainActor
enum SourceActivator {
    static func bringSourceToFront(pid: pid_t, windowID: CGWindowID?) {
        if let windowID {
            _ = raiseWindow(in: pid, matching: windowID)
        }
        NSRunningApplication(processIdentifier: pid)?
            .activate(options: [.activateAllWindows])
    }
}
