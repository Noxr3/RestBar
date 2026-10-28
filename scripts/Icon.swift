import AppKit
let out = CommandLine.arguments[1]
let fm = FileManager.default
try fm.createDirectory(atPath: out, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let s = CGFloat(size)
        let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
        let background = NSBezierPath(roundedRect: rect, xRadius: s * 0.21, yRadius: s * 0.21)
        NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.52, blue: 0.42, alpha: 1), ending: NSColor(calibratedRed: 0.10, green: 0.29, blue: 0.25, alpha: 1))!.draw(in: background, angle: -80)
        let moon = NSBezierPath(ovalIn: NSRect(x: s * 0.25, y: s * 0.24, width: s * 0.50, height: s * 0.53))
        NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.82, alpha: 1).setFill()
        moon.fill()
        let cut = NSBezierPath(ovalIn: NSRect(x: s * 0.43, y: s * 0.39, width: s * 0.40, height: s * 0.43))
        NSColor(calibratedRed: 0.17, green: 0.42, blue: 0.35, alpha: 1).setFill()
        cut.fill()
        let star = NSBezierPath()
        let cx = s * 0.70, cy = s * 0.70, r = s * 0.075
        star.move(to: NSPoint(x: cx, y: cy + r))
        star.line(to: NSPoint(x: cx + r * 0.28, y: cy + r * 0.28))
        star.line(to: NSPoint(x: cx + r, y: cy))
        star.line(to: NSPoint(x: cx + r * 0.28, y: cy - r * 0.28))
        star.line(to: NSPoint(x: cx, y: cy - r))
        star.line(to: NSPoint(x: cx - r * 0.28, y: cy - r * 0.28))
        star.line(to: NSPoint(x: cx - r, y: cy))
        star.line(to: NSPoint(x: cx - r * 0.28, y: cy + r * 0.28))
        star.close()
        NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.82, alpha: 1).setFill()
        star.fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(points)x\(points)\(suffix).png"))
    }
}
