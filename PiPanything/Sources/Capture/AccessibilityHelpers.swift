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
import ApplicationServices

// Private CoreFoundation helper: maps an AXUIElement window to its CGWindowID.
// Stable across macOS releases; widely used by tools that bridge AX and CG.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

func minimizedWindowIDs(in pids: Set<pid_t>) -> Set<CGWindowID> {
    var result = Set<CGWindowID>()
    for pid in pids {
        let app = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { continue }
        for window in windows {
            var minimizedRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
                  let isMin = minimizedRef as? Bool, isMin else { continue }
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(window, &id) == .success {
                result.insert(id)
            }
        }
    }
    return result
}

/// Looks up the AX window in `pid` whose CGWindowID matches `target` and brings
/// it forward within its app: un-minimises it if needed, marks it as main, and
/// performs the AX raise action. Returns true on success; false if the window
/// is not currently AX-visible (e.g. closed, on lock screen, AX denied for
/// this app). The caller is expected to follow up with
/// `NSRunningApplication.activate` regardless — the AX work decides *which*
/// window of the app is frontmost; the activate brings the app forward.
// Best-effort window raise. Returns false (and the caller is expected to
// fall back to an app-level `activate`) when the target app uses a non-AppKit
// windowing toolkit (Sublime Text, parts of Electron/Qt) — those apps return
// an empty `kAXWindowsAttribute` to every AX caller, so per-window targeting
// isn't available for them.
func raiseWindow(in pid: pid_t, matching target: CGWindowID) -> Bool {
    let app = AXUIElementCreateApplication(pid)
    var windowsRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
          let windows = windowsRef as? [AXUIElement] else { return false }
    for window in windows {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &id) == .success, id == target else { continue }
        var minimizedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
           let isMin = minimizedRef as? Bool, isMin {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        return true
    }
    return false
}
