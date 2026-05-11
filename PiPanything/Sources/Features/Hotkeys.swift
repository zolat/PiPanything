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
import Carbon

/// Global hotkeys, registered via the Carbon `RegisterEventHotKey` API so the
/// shortcut is intercepted by the OS rather than merely observed (which is
/// what `NSEvent.addGlobalMonitorForEvents` would give us). Keys do not leak
/// to the focused app's text input.
///
/// AppDelegate is responsible for calling `unregister()` from
/// `applicationWillTerminate(_:)` — `deinit` cannot safely reach the C handler
/// teardown from a non-MainActor context.
@MainActor
final class HotkeysController {
    var onToggleCapture: (() -> Void)?
    var onToggleVisibility: (() -> Void)?
    var onCycleSource: (() -> Void)?
    var onToggleClickThrough: (() -> Void)?
    var onToggleClickThroughUnderCursor: (() -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]

    // 4CC 'PiPa' — uniqueness scope is per-process for hotKeyID.
    private static let signature: OSType = 0x50695061

    private enum HotKeyID: UInt32 {
        case toggleCapture = 1
        case toggleVisibility = 2
        case cycleSource = 3
        case toggleClickThrough = 4
        case toggleClickThroughUnderCursor = 5
    }

    init() {
        installEventHandler()
        registerHotKey(.toggleCapture, keyCode: UInt32(kVK_ANSI_P)) { [weak self] in
            self?.onToggleCapture?()
        }
        registerHotKey(.toggleVisibility, keyCode: UInt32(kVK_ANSI_H)) { [weak self] in
            self?.onToggleVisibility?()
        }
        registerHotKey(.cycleSource, keyCode: UInt32(kVK_ANSI_N)) { [weak self] in
            self?.onCycleSource?()
        }
        registerHotKey(.toggleClickThrough, keyCode: UInt32(kVK_ANSI_T)) { [weak self] in
            self?.onToggleClickThrough?()
        }
        // Single-modifier ⌥T — distinct from the ⌃⌥-prefixed family. Will
        // shadow the OS's default ⌥T (types `†` on US layouts) globally;
        // this is a deliberate user-chosen binding.
        registerHotKey(.toggleClickThroughUnderCursor,
                       keyCode: UInt32(kVK_ANSI_T),
                       modifiers: UInt32(optionKey)) { [weak self] in
            self?.onToggleClickThroughUnderCursor?()
        }
    }

    func unregister() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        actions.removeAll()
    }

    private func installEventHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
                var hkID = EventHotKeyID()
                let r = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard r == noErr else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<HotkeysController>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    controller.fire(id: hkID.id)
                }
                return noErr
            },
            1,
            &spec,
            userData,
            &eventHandler
        )
        if status != noErr {
            NSLog("PiPanything: InstallEventHandler failed (status=\(status))")
        }
    }

    private func fire(id: UInt32) {
        actions[id]?()
    }

    private func registerHotKey(_ id: HotKeyID,
                                keyCode: UInt32,
                                modifiers: UInt32 = UInt32(controlKey | optionKey),
                                action: @escaping () -> Void) {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("PiPanything: RegisterEventHotKey failed for id=\(id.rawValue) keyCode=\(keyCode) status=\(status) — combo may already be in use")
            return
        }
        hotKeyRefs.append(ref)
        actions[id.rawValue] = action
    }
}
