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
