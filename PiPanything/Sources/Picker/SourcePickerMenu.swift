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
    /// True when the click-through latch is engaged for this session — the
    /// window is dimmed and accepts no mouse input.
    let clickThroughLatched: Bool
    /// True when the session is parked in the status menu's "Minimized"
    /// section. Mutually exclusive with `isCapturing` (minimized = stopped).
    let isMinimized: Bool
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
        let minimizedOverlays = activeOverlays.filter { $0.isMinimized }

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

        // ─ Minimized ─ (parked overlays; click an entry to restore it)
        if !minimizedOverlays.isEmpty {
            let header = NSMenuItem(title: "Minimized", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for model in minimizedOverlays {
                menu.addItem(makeMinimizedItem(model: model, target: target, action: overlayAction))
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

    /// Per-overlay action items in display order. Used by the status menu's
    /// per-overlay submenu (flat list, no separators). The right-click menu
    /// arranges the same items into visual groups separately.
    ///
    /// Order: Go to window / Crop / Opacity / Click-through / Auto-hide /
    /// Minimize / Stop.
    private static func sessionActionItems(model: OverlaySessionMenuModel, target: AnyObject, action: Selector) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        // Mirrors ⌘-click on the overlay: raise the captured source, cross-Space
        // switching follows from NSRunningApplication.activate.
        let goToWindow = NSMenuItem(title: "Go to window", action: action, keyEquivalent: "")
        goToWindow.target = target
        goToWindow.representedObject = OverlayMenuTag(model.id, .bringSourceToFront)
        items.append(goToWindow)

        if model.hasCrop {
            let clear = NSMenuItem(title: "Clear crop", action: action, keyEquivalent: "")
            clear.target = target
            clear.representedObject = OverlayMenuTag(model.id, .clearCrop)
            items.append(clear)
        } else {
            let setCrop = NSMenuItem(title: "Crop…", action: action, keyEquivalent: "")
            setCrop.target = target
            setCrop.representedObject = OverlayMenuTag(model.id, .setCrop)
            items.append(setCrop)
        }

        let opacityMenu = NSMenu()
        for percent in [100, 90, 75, 50, 25] {
            let opacityItem = NSMenuItem(title: "\(percent)%", action: action, keyEquivalent: "")
            opacityItem.target = target
            opacityItem.representedObject = OverlayMenuTag(model.id, .setOpacity(percent))
            opacityItem.state = (percent == model.opacityPercent) ? .on : .off
            opacityMenu.addItem(opacityItem)
        }
        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu
        items.append(opacityItem)

        let clickThrough = NSMenuItem(title: "Click-through", action: action, keyEquivalent: "")
        clickThrough.target = target
        clickThrough.representedObject = OverlayMenuTag(model.id, .toggleClickThrough)
        clickThrough.state = model.clickThroughLatched ? .on : .off
        items.append(clickThrough)

        let autoHide = NSMenuItem(title: "Auto-hide", action: action, keyEquivalent: "")
        autoHide.target = target
        autoHide.representedObject = OverlayMenuTag(model.id, .toggleAutoHide)
        autoHide.state = model.autoHide ? .on : .off
        items.append(autoHide)

        let minimize = NSMenuItem(title: "Minimize", action: action, keyEquivalent: "")
        minimize.target = target
        minimize.representedObject = OverlayMenuTag(model.id, .minimize)
        items.append(minimize)

        let stop = NSMenuItem(title: "Stop", action: action, keyEquivalent: "")
        stop.target = target
        stop.representedObject = OverlayMenuTag(model.id, .stop)
        items.append(stop)

        return items
    }

    /// Right-click-on-overlay menu, overlay-scoped.
    ///
    /// Layout for a capturing session:
    ///   Header (overlay name)
    ///   ─────
    ///   Go to window                                    (Source)
    ///   ─────
    ///   Replace window…  /  Add tab…  /  Other tabs ▸   (Tabs)
    ///   ─────
    ///   Crop… or Clear crop  /  Opacity ▸
    ///   Click-through  /  Auto-hide                     (Appearance)
    ///   ─────
    ///   Minimize  /  Stop                               (Lifecycle)
    ///   ─────
    ///   Pick window…
    ///   Quit PiPanything                                (global escape hatches)
    ///
    /// Idle session collapses everything between the header and the global
    /// escape hatches to a single disabled "Idle — pick a window below" hint.
    ///
    /// Cross-overlay navigation (sibling overlays, minimized list, Stop all)
    /// lives only in the status menu now — `populate` builds that surface.
    static func populateSessionScoped(
        _ menu: NSMenu,
        focusedID: OverlayID,
        activeOverlays: [OverlaySessionMenuModel],
        target: AnyObject,
        openPickerAction: Selector,
        addTabAction: Selector,
        setWindowAction: Selector,
        overlayAction: Selector,
        quitAction: Selector
    ) {
        menu.removeAllItems()

        // Session-vanished fallback: just the global escape hatches.
        guard let focused = activeOverlays.first(where: { $0.id == focusedID }) else {
            menu.addItem(makePickItem(target: target, action: openPickerAction))
            menu.addItem(makeQuitItem(target: target, action: quitAction))
            return
        }

        let header = NSMenuItem(title: focused.displayLabel, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if focused.isCapturing {
            menu.addItem(.separator())
            appendSourceGroup(to: menu, model: focused, target: target, action: overlayAction)

            menu.addItem(.separator())
            appendTabsGroup(to: menu, focused: focused, activeOverlays: activeOverlays,
                            target: target,
                            setWindowAction: setWindowAction,
                            addTabAction: addTabAction,
                            overlayAction: overlayAction)

            menu.addItem(.separator())
            appendAppearanceGroup(to: menu, model: focused, target: target, action: overlayAction)

            menu.addItem(.separator())
            appendLifecycleGroup(to: menu, model: focused, target: target, action: overlayAction)
        } else {
            let idleHint = NSMenuItem(title: "Idle — pick a window below", action: nil, keyEquivalent: "")
            idleHint.isEnabled = false
            menu.addItem(idleHint)
        }

        menu.addItem(.separator())
        menu.addItem(makePickItem(target: target, action: openPickerAction))
        menu.addItem(makeQuitItem(target: target, action: quitAction))
    }

    // MARK: - Right-click group builders

    private static func appendSourceGroup(to menu: NSMenu,
                                          model: OverlaySessionMenuModel,
                                          target: AnyObject,
                                          action: Selector) {
        let goToWindow = NSMenuItem(title: "Go to window", action: action, keyEquivalent: "")
        goToWindow.target = target
        goToWindow.representedObject = OverlayMenuTag(model.id, .bringSourceToFront)
        menu.addItem(goToWindow)
    }

    /// Tabs group: Replace window… (capturing only), Add tab…, and the
    /// per-tab submenu when the session has ≥2 tabs. `moveTargets` for the
    /// per-tab "Move to" sub-sub-menu still uses all capturing siblings so
    /// users can shuttle tabs between overlays even though sibling overlay
    /// *controls* no longer appear in the right-click.
    private static func appendTabsGroup(to menu: NSMenu,
                                        focused: OverlaySessionMenuModel,
                                        activeOverlays: [OverlaySessionMenuModel],
                                        target: AnyObject,
                                        setWindowAction: Selector,
                                        addTabAction: Selector,
                                        overlayAction: Selector) {
        let setWindow = NSMenuItem(title: "Replace window…", action: setWindowAction, keyEquivalent: "")
        setWindow.target = target
        setWindow.representedObject = focused.id
        menu.addItem(setWindow)

        let addTab = NSMenuItem(title: "Add tab…", action: addTabAction, keyEquivalent: "")
        addTab.target = target
        addTab.representedObject = focused.id
        menu.addItem(addTab)

        if focused.tabs.count >= 2 {
            let siblings = activeOverlays.filter { $0.id != focused.id && $0.isCapturing }
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
    }

    private static func appendAppearanceGroup(to menu: NSMenu,
                                              model: OverlaySessionMenuModel,
                                              target: AnyObject,
                                              action: Selector) {
        if model.hasCrop {
            let clear = NSMenuItem(title: "Clear crop", action: action, keyEquivalent: "")
            clear.target = target
            clear.representedObject = OverlayMenuTag(model.id, .clearCrop)
            menu.addItem(clear)
        } else {
            let setCrop = NSMenuItem(title: "Crop…", action: action, keyEquivalent: "")
            setCrop.target = target
            setCrop.representedObject = OverlayMenuTag(model.id, .setCrop)
            menu.addItem(setCrop)
        }

        let opacitySubmenu = NSMenu()
        for percent in [100, 90, 75, 50, 25] {
            let item = NSMenuItem(title: "\(percent)%", action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = OverlayMenuTag(model.id, .setOpacity(percent))
            item.state = (percent == model.opacityPercent) ? .on : .off
            opacitySubmenu.addItem(item)
        }
        let opacity = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacity.submenu = opacitySubmenu
        menu.addItem(opacity)

        let clickThrough = NSMenuItem(title: "Click-through", action: action, keyEquivalent: "")
        clickThrough.target = target
        clickThrough.representedObject = OverlayMenuTag(model.id, .toggleClickThrough)
        clickThrough.state = model.clickThroughLatched ? .on : .off
        menu.addItem(clickThrough)

        let autoHide = NSMenuItem(title: "Auto-hide", action: action, keyEquivalent: "")
        autoHide.target = target
        autoHide.representedObject = OverlayMenuTag(model.id, .toggleAutoHide)
        autoHide.state = model.autoHide ? .on : .off
        menu.addItem(autoHide)
    }

    private static func appendLifecycleGroup(to menu: NSMenu,
                                             model: OverlaySessionMenuModel,
                                             target: AnyObject,
                                             action: Selector) {
        let minimize = NSMenuItem(title: "Minimize", action: action, keyEquivalent: "")
        minimize.target = target
        minimize.representedObject = OverlayMenuTag(model.id, .minimize)
        menu.addItem(minimize)

        let stop = NSMenuItem(title: "Stop", action: action, keyEquivalent: "")
        stop.target = target
        stop.representedObject = OverlayMenuTag(model.id, .stop)
        menu.addItem(stop)
    }

    private static func makeQuitItem(target: AnyObject, action: Selector) -> NSMenuItem {
        let quit = NSMenuItem(title: "Quit PiPanything", action: action, keyEquivalent: "q")
        quit.target = target
        return quit
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

    // MARK: - Minimized entry

    /// Single-line entry for a parked overlay. Click to restore — no submenu,
    /// since per-overlay controls (Stop, Crop, etc.) require the capture to
    /// be live. To clear a minimized entry without restoring, use Stop all.
    private static func makeMinimizedItem(model: OverlaySessionMenuModel, target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "◯ \(model.displayLabel)", action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = OverlayMenuTag(model.id, .restoreFromMinimized)
        return item
    }

}
