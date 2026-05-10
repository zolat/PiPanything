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
import Darwin

// CGWindowListCreateImage is `__API_UNAVAILABLE` in the macOS 15 SDK but the
// implementation is still shipped in CoreGraphics for backward compatibility.
// It is the only public path that pulls a window's frame from its CG backing
// store regardless of whether its Space is currently being composited — which
// is what makes the cross-Space PiP capture possible.

private let kCGWindowListOptionIncludingWindow: UInt32 = 1 << 3
private let kCGWindowImageBoundsIgnoreFraming: UInt32 = 1 << 0
private let kCGWindowImageBestResolution: UInt32 = 1 << 3

private typealias CGWindowListCreateImageFn = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?

private let cgWindowListCreateImageDynamic: CGWindowListCreateImageFn? = {
    let path = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    guard let handle = dlopen(path, RTLD_NOW) else {
        NSLog("PiPanything: dlopen CoreGraphics failed: \(String(cString: dlerror()))")
        return nil
    }
    guard let sym = dlsym(handle, "CGWindowListCreateImage") else {
        NSLog("PiPanything: dlsym CGWindowListCreateImage failed — symbol gone in this macOS")
        return nil
    }
    return unsafeBitCast(sym, to: CGWindowListCreateImageFn.self)
}()

func legacyCaptureWindow(_ id: CGWindowID) -> CGImage? {
    guard let fn = cgWindowListCreateImageDynamic else { return nil }
    let opts = kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution
    return fn(.null, kCGWindowListOptionIncludingWindow, id, opts)?.takeRetainedValue()
}

/// Downsample a CGImage to fit within `targetSize`, preserving aspect ratio.
/// Backed by a fresh CGContext at the target dimensions, so the returned
/// image's pixel footprint is small even when the source is full screen.
func downsampledCGImage(_ image: CGImage, fittingIn targetSize: CGSize) -> CGImage? {
    let aspect = CGFloat(image.width) / CGFloat(max(1, image.height))
    var w = targetSize.width
    var h = w / aspect
    if h > targetSize.height {
        h = targetSize.height
        w = h * aspect
    }
    let pixelW = max(1, Int(w))
    let pixelH = max(1, Int(h))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixelW,
        height: pixelH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
    return context.makeImage()
}
