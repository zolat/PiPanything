import Cocoa
import ScreenCaptureKit

/// Snapshot of one overlay session as the menu sees it. The coordinator builds
/// these once per `menuNeedsUpdate`; the menu doesn't reach back into live
/// session state.
struct OverlaySessionMenuModel {
    let id: OverlayID
    let displayLabel: String
    let isCapturing: Bool
    let capturedWindowID: CGWindowID?
    let hasCrop: Bool
    let autoHide: Bool
    let opacityPercent: Int
}

enum SourcePickerMenu {
    /// Populates `menu` with the multi-overlay status menu:
    ///   ─ Active overlays ─
    ///   ● Safari — YouTube ▸  Stop / Crop / Auto-hide / Opacity
    ///   ● Slack — #eng     ▸  …
    ///   ─────────
    ///   Pick window ▸  (always adds; ⌥-click adds + crops)
    ///   Stop all
    ///   Quit
    static func populate(
        _ menu: NSMenu,
        sources: SourceList,
        thumbnails: [CGWindowID: NSImage],
        activeOverlays: [OverlaySessionMenuModel],
        atSoftCap: Bool,
        target: AnyObject,
        pickAction: Selector,
        overlayAction: Selector,
        stopAllAction: Selector,
        quitAction: Selector
    ) {
        menu.removeAllItems()

        let capturingOverlays = activeOverlays.filter { $0.isCapturing }

        // ─ Active overlays ─
        if !capturingOverlays.isEmpty {
            let header = NSMenuItem(title: "Active overlays", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for model in capturingOverlays {
                menu.addItem(makeOverlayItem(model: model, target: target, action: overlayAction))
            }
            menu.addItem(.separator())
        }

        menu.addItem(buildPickItem(sources: sources, thumbnails: thumbnails,
                                   capturedWindowIDs: capturedWindowIDs(in: activeOverlays),
                                   atSoftCap: atSoftCap, activeCount: activeOverlays.count,
                                   target: target, pickAction: pickAction))

        if !capturingOverlays.isEmpty {
            let stopAll = NSMenuItem(title: "Stop all", action: stopAllAction, keyEquivalent: "")
            stopAll.target = target
            menu.addItem(stopAll)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PiPanything", action: quitAction, keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)
    }

    // MARK: - Shared pieces

    private static func capturedWindowIDs(in overlays: [OverlaySessionMenuModel]) -> Set<CGWindowID> {
        Set(overlays.filter { $0.isCapturing }.compactMap { $0.capturedWindowID })
    }

    private static func buildPickItem(
        sources: SourceList,
        thumbnails: [CGWindowID: NSImage],
        capturedWindowIDs: Set<CGWindowID>,
        atSoftCap: Bool,
        activeCount: Int,
        target: AnyObject,
        pickAction: Selector
    ) -> NSMenuItem {
        let pickMenu = NSMenu()
        if atSoftCap {
            let warn = NSMenuItem(
                title: "⚠ \(activeCount) overlays active — adding more may impact performance",
                action: nil,
                keyEquivalent: ""
            )
            warn.isEnabled = false
            pickMenu.addItem(warn)
            pickMenu.addItem(.separator())
        }
        if sources.permissionDenied {
            let item = NSMenuItem(title: "Grant Screen Recording in System Settings, then relaunch", action: nil, keyEquivalent: "")
            item.isEnabled = false
            pickMenu.addItem(item)
        } else if sources.windows.isEmpty {
            let item = NSMenuItem(title: "Loading windows…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            pickMenu.addItem(item)
        } else {
            let hint = NSMenuItem(title: "Tip: hold ⌥ to pick and crop immediately", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            pickMenu.addItem(hint)
            pickMenu.addItem(.separator())
            for window in sources.windows.prefix(60) {
                let item = NSMenuItem(title: label(for: window), action: pickAction, keyEquivalent: "")
                item.target = target
                item.representedObject = window
                let appName = window.owningApplication?.applicationName ?? "Unknown"
                let title = displayTitle(for: window)
                item.view = PickerRowView(
                    image: thumbnails[window.windowID],
                    title: appName,
                    subtitle: title,
                    isCurrent: capturedWindowIDs.contains(window.windowID)
                )
                pickMenu.addItem(item)
            }
        }
        let pickItem = NSMenuItem(title: "Pick window", action: nil, keyEquivalent: "")
        pickItem.submenu = pickMenu
        return pickItem
    }

    /// The Stop / Crop / Auto-hide / Opacity items for a single session,
    /// returned in display order. Used both inline (right-click on overlay)
    /// and in the per-overlay submenu (status menu's "Active overlays").
    private static func sessionActionItems(model: OverlaySessionMenuModel, target: AnyObject, action: Selector) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        let stop = NSMenuItem(title: "Stop", action: action, keyEquivalent: "")
        stop.target = target
        stop.representedObject = OverlayMenuTag(model.id, .stop)
        items.append(stop)

        if model.hasCrop {
            let clear = NSMenuItem(title: "Clear crop region", action: action, keyEquivalent: "")
            clear.target = target
            clear.representedObject = OverlayMenuTag(model.id, .clearCrop)
            items.append(clear)
        } else {
            let setCrop = NSMenuItem(title: "Set crop region…", action: action, keyEquivalent: "")
            setCrop.target = target
            setCrop.representedObject = OverlayMenuTag(model.id, .setCrop)
            items.append(setCrop)
        }

        let autoHide = NSMenuItem(title: "Auto-hide when source is frontmost", action: action, keyEquivalent: "")
        autoHide.target = target
        autoHide.representedObject = OverlayMenuTag(model.id, .toggleAutoHide)
        autoHide.state = model.autoHide ? .on : .off
        items.append(autoHide)

        let opacityMenu = NSMenu()
        for percent in [100, 90, 75, 50, 25] {
            let opacityItem = NSMenuItem(title: "\(percent)%", action: action, keyEquivalent: "")
            opacityItem.target = target
            opacityItem.representedObject = OverlayMenuTag(model.id, .setOpacity(percent))
            opacityItem.state = (percent == model.opacityPercent) ? .on : .off
            opacityMenu.addItem(opacityItem)
        }
        let opacityItem = NSMenuItem(title: "Transparency", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu
        items.append(opacityItem)

        return items
    }

    /// Right-click-on-overlay menu: the focused session's controls inline at
    /// the top, sibling sessions in an "Other overlays" submenu, then the
    /// global picker / Stop all / Quit. Lets a user reach any other session
    /// from any overlay without forcing them to dig through "Active overlays".
    static func populateSessionScoped(
        _ menu: NSMenu,
        focusedID: OverlayID,
        sources: SourceList,
        thumbnails: [CGWindowID: NSImage],
        activeOverlays: [OverlaySessionMenuModel],
        atSoftCap: Bool,
        target: AnyObject,
        pickAction: Selector,
        overlayAction: Selector,
        stopAllAction: Selector,
        quitAction: Selector
    ) {
        menu.removeAllItems()

        guard let focused = activeOverlays.first(where: { $0.id == focusedID }) else {
            // Session was removed mid-right-click — fall back to the global menu.
            populate(menu, sources: sources, thumbnails: thumbnails,
                     activeOverlays: activeOverlays, atSoftCap: atSoftCap,
                     target: target, pickAction: pickAction,
                     overlayAction: overlayAction, stopAllAction: stopAllAction,
                     quitAction: quitAction)
            return
        }

        // Header showing which overlay the user clicked on.
        let header = NSMenuItem(title: focused.displayLabel, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // Inline session controls (only meaningful when the session is capturing).
        if focused.isCapturing {
            for item in sessionActionItems(model: focused, target: target, action: overlayAction) {
                menu.addItem(item)
            }
        } else {
            let idleHint = NSMenuItem(title: "Idle — pick a window below", action: nil, keyEquivalent: "")
            idleHint.isEnabled = false
            menu.addItem(idleHint)
        }

        // Other overlays (siblings only).
        let siblings = activeOverlays.filter { $0.id != focusedID && $0.isCapturing }
        if !siblings.isEmpty {
            menu.addItem(.separator())
            let other = NSMenuItem(title: "Other overlays", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for sibling in siblings {
                sub.addItem(makeOverlayItem(model: sibling, target: target, action: overlayAction))
            }
            other.submenu = sub
            menu.addItem(other)
        }

        menu.addItem(.separator())

        // Global picker, reachable from any overlay's right-click.
        menu.addItem(buildPickItem(sources: sources, thumbnails: thumbnails,
                                   capturedWindowIDs: capturedWindowIDs(in: activeOverlays),
                                   atSoftCap: atSoftCap, activeCount: activeOverlays.count,
                                   target: target, pickAction: pickAction))

        if activeOverlays.contains(where: { $0.isCapturing }) {
            let stopAll = NSMenuItem(title: "Stop all", action: stopAllAction, keyEquivalent: "")
            stopAll.target = target
            menu.addItem(stopAll)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PiPanything", action: quitAction, keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)
    }

    // MARK: - Per-overlay submenu

    private static func makeOverlayItem(model: OverlaySessionMenuModel, target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "● \(model.displayLabel)", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for child in sessionActionItems(model: model, target: target, action: action) {
            sub.addItem(child)
        }
        item.submenu = sub
        return item
    }

    // MARK: - Labels

    private static func label(for window: SCWindow) -> String {
        let appName = window.owningApplication?.applicationName ?? "?"
        return "\(appName) — \(displayTitle(for: window))"
    }

    private static func displayTitle(for window: SCWindow) -> String {
        let rawTitle = window.title ?? ""
        if rawTitle.isEmpty {
            return "(untitled \(Int(window.frame.width))×\(Int(window.frame.height)))"
        }
        return rawTitle.count > 60 ? String(rawTitle.prefix(60)) + "…" : rawTitle
    }
}
