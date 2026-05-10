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

import Foundation
import ServiceManagement

/// Persisted user preferences surfaced through the status-bar menu. Plain
/// UserDefaults wrapper — no observation, no SwiftUI. New `OverlaySession`s
/// read these as their starting values; existing sessions are not retroactively
/// touched (keeps the menu's "default" semantics honest).
@MainActor
final class Settings {
    static let shared = Settings()

    private let defaults: UserDefaults
    private let opacityKey = "pip.defaultOpacityPercent"
    private let autoHideKey = "pip.autoHideDefault"
    private let maxDimensionKey = "pip.maxOverlayDimension"

    /// Allowed range for the user-configurable overlay size cap. Floor sits
    /// well above the resize-handle minimum so the cap is always usable; ceiling
    /// covers a 4K display's longer side.
    static let maxDimensionBounds: ClosedRange<Int> = 480...3840
    static let defaultMaxDimension: Int = 1280

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Starting opacity (10–100) applied to every newly-created overlay.
    /// Falls back to 100 when unset.
    var defaultOpacityPercent: Int {
        get {
            let raw = defaults.object(forKey: opacityKey) as? Int ?? 100
            return max(10, min(100, raw))
        }
        set {
            defaults.set(max(10, min(100, newValue)), forKey: opacityKey)
        }
    }

    /// Starting auto-hide state for new overlays. Defaults to off so a fresh
    /// install behaves like v1.
    var autoHideDefault: Bool {
        get { defaults.object(forKey: autoHideKey) as? Bool ?? false }
        set { defaults.set(newValue, forKey: autoHideKey) }
    }

    /// Upper bound (in points) on either side of an overlay window. The
    /// resize handle and `OverlaySession.clampToOverlayBounds` both honour
    /// this. A single dimension caps both width and height — for any aspect
    /// ratio, the longer side hits the cap first.
    var maxOverlayDimension: Int {
        get {
            let raw = defaults.object(forKey: maxDimensionKey) as? Int ?? Self.defaultMaxDimension
            return min(Self.maxDimensionBounds.upperBound,
                       max(Self.maxDimensionBounds.lowerBound, raw))
        }
        set {
            let clamped = min(Self.maxDimensionBounds.upperBound,
                              max(Self.maxDimensionBounds.lowerBound, newValue))
            defaults.set(clamped, forKey: maxDimensionKey)
        }
    }

    /// Whether the app is registered to launch at login. Backed by
    /// `SMAppService.mainApp` (macOS 13+). Reads reflect the actual system
    /// state rather than a cached UserDefaults bool, so the menu's checkmark
    /// stays honest if registration silently fails (e.g. ad-hoc signing).
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("PiPanything: launch-at-login toggle failed — \(error.localizedDescription)")
            }
        }
    }
}
