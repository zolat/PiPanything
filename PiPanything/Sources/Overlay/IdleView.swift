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
import QuartzCore

final class IdleView: NSView {
    private let clock = NSTextField(labelWithString: "")
    private let gradient = CAGradientLayer()
    private let statusLabel = NSTextField(labelWithString: "Right-click for menu · drag to move")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        gradient.frame = bounds
        gradient.colors = [
            NSColor(srgbRed: 0.05, green: 0.32, blue: 0.70, alpha: 0.92).cgColor,
            NSColor(srgbRed: 0.08, green: 0.08, blue: 0.18, alpha: 0.92).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradient)

        let title = NSTextField(labelWithString: "PiPanything")
        title.textColor = .white
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.frame = NSRect(x: 20, y: bounds.height - 44, width: bounds.width - 40, height: 24)
        title.drawsBackground = false; title.isBezeled = false
        addSubview(title)

        statusLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.frame = NSRect(x: 20, y: bounds.height - 68, width: bounds.width - 40, height: 16)
        statusLabel.drawsBackground = false; statusLabel.isBezeled = false
        addSubview(statusLabel)

        clock.textColor = .white
        clock.font = .monospacedSystemFont(ofSize: 32, weight: .medium)
        clock.alignment = .center
        clock.drawsBackground = false; clock.isBezeled = false
        clock.frame = NSRect(x: 20, y: 70, width: bounds.width - 40, height: 40)
        addSubview(clock)

        let hint = NSTextField(labelWithString: "Cross-Space PiP · SCStream + CG polling fallback")
        hint.textColor = NSColor.white.withAlphaComponent(0.55)
        hint.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        hint.alignment = .center
        hint.drawsBackground = false; hint.isBezeled = false
        hint.frame = NSRect(x: 8, y: 14, width: bounds.width - 16, height: 12)
        addSubview(hint)

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            self?.clock.stringValue = f.string(from: Date())
        }
    }

    func setStatus(_ text: String) { statusLabel.stringValue = text }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }
}
