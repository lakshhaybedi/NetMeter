// Renders AppIcon.icns: swift icon.swift
import AppKit
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let path = NSBezierPath(roundedRect: NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88), xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(red: 0.2, green: 0.8, blue: 0.95, alpha: 1), NSColor(red: 0.32, green: 0.3, blue: 0.9, alpha: 1)])!.draw(in: path, angle: -60)
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.46, weight: .bold).applying(.init(paletteColors: [.white]))
    let img = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    img.draw(at: NSPoint(x: (s - img.size.width) / 2, y: (s - img.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let dir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (n, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(n).png"))
}
