import Cocoa
import ScreenCaptureKit

enum SourcePickerMenu {
    /// Populates `menu` with a "Pick window" submenu plus state-dependent items.
    /// The menu items hold their selected `SCWindow` in `representedObject`.
    static func populate(
        _ menu: NSMenu,
        sources: SourceList,
        thumbnails: [CGWindowID: NSImage] = [:],
        capturedWindowID: CGWindowID?,
        isCapturing: Bool,
        hasCrop: Bool,
        autoHideEnabled: Bool,
        opacityPercent: Int,
        target: AnyObject,
        pickAction: Selector,
        stopAction: Selector,
        setCropAction: Selector,
        clearCropAction: Selector,
        autoHideAction: Selector,
        opacityAction: Selector,
        quitAction: Selector
    ) {
        menu.removeAllItems()

        let pickMenu = NSMenu()
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
                    isCurrent: window.windowID == capturedWindowID
                )
                pickMenu.addItem(item)
            }
        }

        let pickItem = NSMenuItem(title: "Pick window", action: nil, keyEquivalent: "")
        pickItem.submenu = pickMenu
        menu.addItem(pickItem)

        if isCapturing {
            let stop = NSMenuItem(title: "Stop capture", action: stopAction, keyEquivalent: "")
            stop.target = target
            menu.addItem(stop)

            if hasCrop {
                let clear = NSMenuItem(title: "Clear crop region", action: clearCropAction, keyEquivalent: "")
                clear.target = target
                menu.addItem(clear)
            } else {
                let set = NSMenuItem(title: "Set crop region…", action: setCropAction, keyEquivalent: "")
                set.target = target
                menu.addItem(set)
            }
        }

        menu.addItem(.separator())
        let autoHide = NSMenuItem(title: "Auto-hide when source is frontmost", action: autoHideAction, keyEquivalent: "")
        autoHide.target = target
        autoHide.state = autoHideEnabled ? .on : .off
        menu.addItem(autoHide)

        let opacityMenu = NSMenu()
        for percent in [100, 90, 75, 50, 25] {
            let item = NSMenuItem(title: "\(percent)%", action: opacityAction, keyEquivalent: "")
            item.target = target
            item.tag = percent
            item.state = (percent == opacityPercent) ? .on : .off
            opacityMenu.addItem(item)
        }
        let opacityItem = NSMenuItem(title: "Transparency", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PiPanything", action: quitAction, keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)
    }

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
