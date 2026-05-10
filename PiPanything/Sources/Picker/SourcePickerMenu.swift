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
    /// All capturing tabs in this session, including the active one.
    /// Single-tab sessions have `tabs.count == 1`; multi-tab sessions enable
    /// the per-tab submenus.
    let tabs: [OverlayTabMenuModel]
}

struct OverlayTabMenuModel {
    let id: OverlayTabID
    let displayLabel: String
    let isActive: Bool
    let capturedWindowID: CGWindowID?
}

enum SourcePickerMenu {
    /// Populates `menu` with the multi-overlay status menu:
    ///   ─ Active overlays ─
    ///   ● Safari — YouTube ▸  Stop / Crop / Auto-hide / Opacity
    ///   ● Slack — #eng     ▸  …
    ///   ─────────
    ///   Pick window…   (opens the grid modal; ⌥-click in the modal adds + crops)
    ///   Stop all
    ///   Quit
    static func populate(
        _ menu: NSMenu,
        activeOverlays: [OverlaySessionMenuModel],
        target: AnyObject,
        openPickerAction: Selector,
        overlayAction: Selector,
        stopAllAction: Selector,
        quitAction: Selector,
        extraSection: ((NSMenu) -> Void)? = nil
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

        menu.addItem(makePickItem(target: target, action: openPickerAction))

        if !capturingOverlays.isEmpty {
            let stopAll = NSMenuItem(title: "Stop all", action: stopAllAction, keyEquivalent: "")
            stopAll.target = target
            menu.addItem(stopAll)
        }

        // Caller-supplied section (status menu uses this for app-wide settings).
        // Right-click-menu callers leave it nil — no behavior change there.
        if let extraSection = extraSection {
            menu.addItem(.separator())
            extraSection(menu)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PiPanything", action: quitAction, keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)
    }

    // MARK: - Shared pieces

    /// Single "Pick window…" entry that opens the grid modal. The modal pulls
    /// fresh sources/thumbnails from AppDelegate when shown — keeping the menu
    /// itself dumb.
    private static func makePickItem(target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "Pick window…", action: action, keyEquivalent: "")
        item.target = target
        return item
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
        activeOverlays: [OverlaySessionMenuModel],
        target: AnyObject,
        openPickerAction: Selector,
        addTabAction: Selector,
        overlayAction: Selector,
        stopAllAction: Selector,
        quitAction: Selector
    ) {
        menu.removeAllItems()

        guard let focused = activeOverlays.first(where: { $0.id == focusedID }) else {
            // Session was removed mid-right-click — fall back to the global menu.
            populate(menu,
                     activeOverlays: activeOverlays,
                     target: target,
                     openPickerAction: openPickerAction,
                     overlayAction: overlayAction,
                     stopAllAction: stopAllAction,
                     quitAction: quitAction)
            return
        }

        // Header showing which overlay (and active tab) the user clicked on.
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

        // Add-tab to this session — opens the picker bound to focused.id.
        menu.addItem(.separator())
        let addTab = NSMenuItem(title: "Add tab here…", action: addTabAction, keyEquivalent: "")
        addTab.target = target
        addTab.representedObject = focused.id
        menu.addItem(addTab)

        // Other overlays (siblings only) — needed early so per-tab "Move to"
        // submenus can list possible destinations.
        let siblings = activeOverlays.filter { $0.id != focusedID && $0.isCapturing }

        // Per-tab submenu (only visible when there are multiple tabs).
        if focused.tabs.count >= 2 {
            let other = NSMenuItem(title: "Other tabs", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for tab in focused.tabs where !tab.isActive {
                sub.addItem(makeTabItem(tab: tab, sessionID: focused.id,
                                        moveTargets: siblings,
                                        target: target, action: overlayAction))
            }
            other.submenu = sub
            menu.addItem(other)
        }
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
        menu.addItem(makePickItem(target: target, action: openPickerAction))

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

    // MARK: - Per-tab submenu (multi-tab overlays only)

    private static func makeTabItem(tab: OverlayTabMenuModel, sessionID: OverlayID,
                                    moveTargets: [OverlaySessionMenuModel],
                                    target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: tab.displayLabel, action: nil, keyEquivalent: "")
        let sub = NSMenu()

        let switchTo = NSMenuItem(title: "Switch to", action: action, keyEquivalent: "")
        switchTo.target = target
        switchTo.representedObject = OverlayMenuTag(sessionID, .switchTab(tab.id))
        sub.addItem(switchTo)

        sub.addItem(.separator())

        let tearOut = NSMenuItem(title: "Tear into new window", action: action, keyEquivalent: "")
        tearOut.target = target
        tearOut.representedObject = OverlayMenuTag(sessionID, .tearOutTab(tab.id))
        sub.addItem(tearOut)

        // Move to ▸ <other window> — only when other sessions exist.
        if !moveTargets.isEmpty {
            let move = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
            let moveSub = NSMenu()
            for dest in moveTargets {
                let destItem = NSMenuItem(title: dest.displayLabel, action: action, keyEquivalent: "")
                destItem.target = target
                destItem.representedObject = OverlayMenuTag(sessionID, .moveTabTo(tab.id, dest.id))
                moveSub.addItem(destItem)
            }
            move.submenu = moveSub
            sub.addItem(move)
        }

        sub.addItem(.separator())

        let close = NSMenuItem(title: "Close", action: action, keyEquivalent: "")
        close.target = target
        close.representedObject = OverlayMenuTag(sessionID, .closeTab(tab.id))
        sub.addItem(close)

        item.submenu = sub
        return item
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

}
