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

/// Floating panel that lays the capturable windows out as a thumbnail grid
/// with a search field on top. Replaces the long vertical NSMenu submenu —
/// many sources fit on screen at once, the user filters by app/title text,
/// and the grid reflows on resize.
@MainActor
final class PickerWindowController: NSObject, NSCollectionViewDataSource,
                                     NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout,
                                     NSSearchFieldDelegate, NSWindowDelegate {
    /// Selection callback. `cropImmediately` is true when ⌥ was held at click
    /// time — preserves the v1 ⌥-click-to-crop shortcut.
    var onPick: ((SCWindow, _ cropImmediately: Bool) -> Void)?

    private let panel: PickerPanel
    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let statusLabel = NSTextField(labelWithString: "")

    /// Source-of-truth window list (already filtered to capturable + sorted).
    private var allWindows: [SCWindow] = []
    /// What the grid currently shows — `allWindows` filtered by search text.
    private var displayed: [SCWindow] = []
    private var thumbnails: [CGWindowID: NSImage] = [:]
    private var capturedWindowIDs: Set<CGWindowID> = []
    private var isAtSoftCap: Bool = false
    private var permissionDenied: Bool = false

    var isVisible: Bool { panel.isVisible }

    override init() {
        let contentRect = NSRect(x: 0, y: 0, width: 1100, height: 700)
        panel = PickerPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Pick a window"
        panel.titlebarAppearsTransparent = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 600, height: 400)

        super.init()

        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        buildContent()
    }

    // MARK: - Public API

    /// Show the panel with whatever sources/thumbnails are currently available.
    /// Update later with `update(...)` once async refresh delivers more.
    func show(
        sources: SourceList,
        thumbnails: [CGWindowID: NSImage],
        capturedWindowIDs: Set<CGWindowID>,
        isAtSoftCap: Bool
    ) {
        update(
            sources: sources,
            thumbnails: thumbnails,
            capturedWindowIDs: capturedWindowIDs,
            isAtSoftCap: isAtSoftCap
        )
        searchField.stringValue = ""
        applyFilter()

        // Center on the screen containing the cursor so the picker pops up
        // near the user's attention, not on a side display.
        if let screen = screenAtMouse() {
            let f = panel.frame
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.midX - f.width / 2,
                y: visible.midY - f.height / 2
            )
            panel.setFrameOrigin(origin)
        }

        // LSUIElement apps don't get keyboard focus on simple makeKey — activate.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func update(
        sources: SourceList,
        thumbnails: [CGWindowID: NSImage],
        capturedWindowIDs: Set<CGWindowID>,
        isAtSoftCap: Bool
    ) {
        self.allWindows = sources.windows
        self.thumbnails = thumbnails
        self.capturedWindowIDs = capturedWindowIDs
        self.isAtSoftCap = isAtSoftCap
        self.permissionDenied = sources.permissionDenied
        applyFilter()
        refreshStatusLabel(sourceCount: sources.windows.count, axTrusted: sources.axTrusted)
    }

    func close() {
        panel.orderOut(nil)
    }

    // MARK: - Layout

    private func buildContent() {
        guard let content = panel.contentView else { return }
        content.wantsLayer = true

        let toolbarHeight: CGFloat = 44
        let statusHeight: CGFloat = 22

        searchField.placeholderString = "Filter by app or window title"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(searchField)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = PickerCell.cellSize
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(PickerCell.self, forItemWithIdentifier: PickerCell.identifier)

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            searchField.heightAnchor.constraint(equalToConstant: toolbarHeight - 16),

            statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            statusLabel.heightAnchor.constraint(equalToConstant: statusHeight),

            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func screenAtMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    private func refreshStatusLabel(sourceCount: Int, axTrusted: Bool) {
        if permissionDenied {
            statusLabel.stringValue = "Grant Screen Recording in System Settings, then relaunch"
            statusLabel.textColor = .systemRed
            return
        }
        statusLabel.textColor = .secondaryLabelColor
        var pieces: [String] = []
        pieces.append("\(sourceCount) capturable window\(sourceCount == 1 ? "" : "s")")
        pieces.append("hold ⌥ to pick and crop immediately")
        if isAtSoftCap {
            pieces.append("⚠ at soft cap — adding more may impact performance")
        }
        if !axTrusted {
            pieces.append("grant Accessibility to hide minimized")
        }
        statusLabel.stringValue = pieces.joined(separator: " · ")
    }

    // MARK: - Filtering

    private func applyFilter() {
        let query = searchField.stringValue.lowercased()
        if query.isEmpty {
            displayed = allWindows
        } else {
            displayed = allWindows.filter { window in
                let app = window.owningApplication?.applicationName ?? ""
                let title = window.title ?? ""
                return "\(app) \(title)".lowercased().contains(query)
            }
        }
        collectionView.reloadData()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as AnyObject === searchField else { return }
        applyFilter()
    }

    // MARK: - NSCollectionViewDataSource / Delegate

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        displayed.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: PickerCell.identifier, for: indexPath)
        guard let cell = item as? PickerCell else { return item }
        let window = displayed[indexPath.item]
        let appName = window.owningApplication?.applicationName ?? "Unknown"
        cell.configure(
            image: thumbnails[window.windowID],
            appName: appName,
            title: PickerLabel.displayTitle(for: window),
            isCurrent: capturedWindowIDs.contains(window.windowID)
        )
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first, indexPath.item < displayed.count else { return }
        let window = displayed[indexPath.item]
        // Read live modifier state — per CLAUDE.md gotcha #7, don't track state.
        let cropImmediately = NSEvent.modifierFlags.contains(.option)
        // Deselect so a re-click on the same item still fires.
        collectionView.deselectAll(nil)
        close()
        onPick?(window, cropImmediately)
    }

    // MARK: - NSWindowDelegate (Esc to close)

    func windowDidResignKey(_ notification: Notification) {
        // Don't auto-close on focus loss; the user may briefly tab to another
        // app or the focus ring may flicker. They can press Esc or click a cell.
    }
}

/// NSPanel subclass that closes on Escape and can be key even though
/// PiPanything is `LSUIElement` (otherwise the search field can't take
/// keyboard input).
@MainActor
final class PickerPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Title formatting shared between the (now thin) menu and the modal.
enum PickerLabel {
    static func displayTitle(for window: SCWindow) -> String {
        let raw = window.title ?? ""
        if raw.isEmpty {
            return "(untitled \(Int(window.frame.width))×\(Int(window.frame.height)))"
        }
        return raw.count > 80 ? String(raw.prefix(80)) + "…" : raw
    }
}
