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
