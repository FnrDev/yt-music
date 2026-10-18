#!/usr/bin/env swift
// Renders the app icon into YTMusic/Resources/Assets.xcassets/AppIcon.appiconset.
// Usage: swift scripts/make-icon.swift  (from the macos/ directory)
import AppKit

let outputDir = URL(fileURLWithPath: "YTMusic/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: ~10% margin, continuous-corner squircle.
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 0.25, blue: 0.35, alpha: 1),
        NSColor(srgbRed: 0.78, green: 0.05, blue: 0.20, alpha: 1),
        NSColor(srgbRed: 0.35, green: 0.04, blue: 0.22, alpha: 1),
    ])!.draw(in: squircle, angle: -60)

    // Equalizer bars.
    let heights: [CGFloat] = [0.30, 0.55, 0.80, 0.45, 0.65]
    let barWidth = rect.width * 0.09
    let gap = rect.width * 0.055
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = rect.midX - totalWidth / 2
    let baseline = rect.minY + rect.height * 0.2
    NSColor.white.setFill()
    for h in heights {
        let bar = NSRect(x: x, y: baseline, width: barWidth, height: rect.height * 0.6 * h)
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        x += barWidth + gap
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(size: points * scale).write(to: outputDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDir.appendingPathComponent("Contents.json"))

let catalogInfo = try JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: .prettyPrinted)
try catalogInfo.write(to: outputDir.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(outputDir.path)")
