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

/// Top-bar surface for PiPanything. Adds an `NSStatusItem` and a menu that
/// reuses `SourcePickerMenu.populate` for the active-overlays + picker block,
/// then injects an inline settings section (default opacity, auto-hide
/// default, launch-at-login) via the builder's `extraSection:` hook.
///
/// The status menu and the right-click menu share `AppDelegate`'s
/// selectors (`openPicker`, `handleOverlayMenu(_:)`, `stopAll`, `quit`) so the
/// two surfaces always agree on behavior.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private weak var appDelegate: AppDelegate?
    private let statusItem: NSStatusItem
    private let menu: NSMenu

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.menu = NSMenu()
        super.init()

        let symbol = NSImage(systemSymbolName: "rectangle.on.rectangle",
                             accessibilityDescription: "PiPanything")
        symbol?.isTemplate = true
        if let button = statusItem.button {
            button.image = symbol
            button.toolTip = "PiPanything"
        }

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    // MARK: - Build

    private func rebuild() {
        guard let appDelegate = appDelegate else {
            menu.removeAllItems()
            return
        }
        let activeOverlays = appDelegate.coordinator.sessions.map { $0.menuModel() }
        SourcePickerMenu.populate(
            menu,
            activeOverlays: activeOverlays,
            target: appDelegate,
            openPickerAction: #selector(AppDelegate.openPicker),
            overlayAction: #selector(AppDelegate.handleOverlayMenu(_:)),
            stopAllAction: #selector(AppDelegate.stopAll),
            quitAction: #selector(AppDelegate.quit),
            extraSection: { [weak self] menu in
                self?.appendSettingsItems(to: menu)
            }
        )
    }

    private func appendSettingsItems(to menu: NSMenu) {
        // Default opacity — submenu of presets matching the per-overlay set.
        let opacityRoot = NSMenuItem(title: "Default opacity", action: nil, keyEquivalent: "")
        let opacitySubmenu = NSMenu()
        let currentOpacity = Settings.shared.defaultOpacityPercent
        for percent in [100, 90, 75, 50, 25] {
            let item = NSMenuItem(title: "\(percent)%",
                                  action: #selector(setDefaultOpacity(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = percent
            item.state = (percent == currentOpacity) ? .on : .off
            opacitySubmenu.addItem(item)
        }
        opacityRoot.submenu = opacitySubmenu
        menu.addItem(opacityRoot)

        // Max overlay size — submenu of presets. Applies live to every
        // existing overlay (a hard cap, not a per-overlay default).
        let maxRoot = NSMenuItem(title: "Max overlay size", action: nil, keyEquivalent: "")
        let maxSubmenu = NSMenu()
        let currentMax = Settings.shared.maxOverlayDimension
        for dim in [720, 1280, 1920, 2560, 3840] {
            let item = NSMenuItem(title: "\(dim) px",
                                  action: #selector(setMaxOverlayDimension(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = dim
            item.state = (dim == currentMax) ? .on : .off
            maxSubmenu.addItem(item)
        }
        maxRoot.submenu = maxSubmenu
        menu.addItem(maxRoot)

        // Auto-hide default for new overlays.
        let autoHide = NSMenuItem(title: "Auto-hide new overlays",
                                   action: #selector(toggleAutoHideDefault),
                                   keyEquivalent: "")
        autoHide.target = self
        autoHide.state = Settings.shared.autoHideDefault ? .on : .off
        menu.addItem(autoHide)

        // Launch at login (SMAppService).
        let launch = NSMenuItem(title: "Launch at login",
                                 action: #selector(toggleLaunchAtLogin),
                                 keyEquivalent: "")
        launch.target = self
        launch.state = Settings.shared.launchAtLogin ? .on : .off
        menu.addItem(launch)
    }

    // MARK: - Settings actions

    @objc private func setDefaultOpacity(_ sender: NSMenuItem) {
        Settings.shared.defaultOpacityPercent = sender.tag
    }

    @objc private func toggleAutoHideDefault() {
        Settings.shared.autoHideDefault.toggle()
    }

    @objc private func setMaxOverlayDimension(_ sender: NSMenuItem) {
        Settings.shared.maxOverlayDimension = sender.tag
        // Push the (possibly clamped) effective value back to live overlays so
        // existing windows shrink immediately if they exceed the new cap.
        appDelegate?.applyMaxDimensionToAllSessions(Settings.shared.maxOverlayDimension)
    }

    @objc private func toggleLaunchAtLogin() {
        Settings.shared.launchAtLogin.toggle()
    }
}
