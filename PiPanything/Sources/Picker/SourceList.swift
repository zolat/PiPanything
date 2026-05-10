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
import ScreenCaptureKit

/// Snapshot of capturable windows plus the permission state that produced it.
///
/// Filters in priority order:
///   1. `windowLayer == 0` (normal user windows; drops menubar/dock/system overlays).
///   2. Width and height > 80pt (drops tiny pickers/popups).
///   3. Owning app must have `.regular` activation policy (drops Spotlight,
///      Control Center, and friends — even when their layer is 0).
///   4. Drop our own bundle.
///   5. If Accessibility is granted, drop windows whose AXMinimized attribute
///      is true (otherwise capture would silently produce no frames).
///
/// `isOnScreen` is intentionally NOT used: it conflates "minimized" with
/// "on a non-current Space," and we want cross-Space sources visible.
struct SourceList {
    var windows: [SCWindow] = []
    var permissionDenied: Bool = false
    var axTrusted: Bool = false

    static func refresh() async -> SourceList {
        var result = SourceList()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            )
            let myBundle = Bundle.main.bundleIdentifier
            let regularPIDs = Set(
                NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular }
                    .map { $0.processIdentifier }
            )
            result.axTrusted = AXIsProcessTrusted()
            var minimizedIDs = Set<CGWindowID>()
            if result.axTrusted {
                let pids = Set(content.windows.compactMap { $0.owningApplication?.processID })
                    .intersection(regularPIDs)
                minimizedIDs = minimizedWindowIDs(in: pids)
            }
            result.windows = content.windows.filter { w in
                guard w.windowLayer == 0 else { return false }
                guard w.frame.width > 80, w.frame.height > 80 else { return false }
                guard let pid = w.owningApplication?.processID, regularPIDs.contains(pid) else { return false }
                if let bid = w.owningApplication?.bundleIdentifier, bid == myBundle { return false }
                if minimizedIDs.contains(w.windowID) { return false }
                return true
            }.sorted { lhs, rhs in
                let la = lhs.owningApplication?.applicationName ?? ""
                let ra = rhs.owningApplication?.applicationName ?? ""
                if la != ra { return la < ra }
                return (lhs.title ?? "") < (rhs.title ?? "")
            }
        } catch {
            result.permissionDenied = true
            NSLog("PiPanything: SCShareableContent failed: \(error)")
        }
        return result
    }
}
