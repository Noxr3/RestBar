// Draws the app icon and the README brand images from Sources/Brand.swift, so
// they cannot drift from what the app itself draws.
//
// The wordmark is set in Bitcount Grid Single (SIL Open Font License). The font is
// only needed to regenerate these images and is not committed or shipped; pass the
// path of a local copy.
//
//   mkdir -p build/module-cache
//   xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path build/module-cache \
//     Sources/Brand.swift scripts/Icon.swift -framework AppKit -framework SwiftUI -o build/Icon
//   build/Icon build/AppIcon.iconset assets/brand path/to/BitcountGridSingle.ttf
//   iconutil -c icns build/AppIcon.iconset -o AppIcon.icns
import AppKit
import CoreText

@main
struct Icon {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else {
            print("usage: Icon <iconset-dir> <brand-dir> <font-path>")
            exit(2)
        }
        let (iconset, brand, fontPath) = (arguments[1], arguments[2], arguments[3])
        let fm = FileManager.default
        try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: brand, withIntermediateDirectories: true)

        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let size = points * scale
                try png(width: size, height: size, to: "\(iconset)/icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png") {
                    tile(size: CGFloat(size), columns: MoonMark.columns(forPixelSize: size))
                }
            }
        }

        var fontError: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: fontPath) as CFURL, .process, &fontError) else {
            print("could not load \(fontPath): \(String(describing: fontError?.takeRetainedValue()))")
            exit(1)
        }

        try png(width: 512, height: 512, to: "\(brand)/mark-on-dark.png") {
            MoonMark.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512), columns: 15, phase: .resting, ink: Brand.white, signal: Brand.markRed)
        }
        try png(width: 512, height: 512, to: "\(brand)/mark-on-light.png") {
            MoonMark.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512), columns: 15, phase: .resting, ink: Brand.paper, signal: Brand.markRed)
        }
        for (name, ink) in [("lockup-on-dark", Brand.white), ("lockup-on-light", Brand.paper)] {
            try png(width: 1200, height: 280, to: "\(brand)/\(name).png") {
                MoonMark.draw(in: NSRect(x: 20, y: 40, width: 200, height: 200), columns: 15, phase: .resting, ink: ink, signal: Brand.markRed)
                text("RestBar", at: NSPoint(x: 262, y: 14), font: wordmark(190), color: ink)
            }
        }
        // GitHub's social card: 1280 x 640, flat, with everything away from the edges.
        try png(width: 1280, height: 640, to: "\(brand)/social-preview.png") {
            Brand.paper.setFill()
            NSRect(x: 0, y: 0, width: 1280, height: 640).fill()
            MoonMark.draw(in: NSRect(x: 110, y: 190, width: 260, height: 260), columns: 15, phase: .resting, ink: Brand.white, signal: Brand.markRed)
            text("RestBar", at: NSPoint(x: 424, y: 318), font: wordmark(150), color: Brand.white)
            text("Let your Mac rest on your schedule.", at: NSPoint(x: 432, y: 258), font: .systemFont(ofSize: 34), color: Brand.white)
            text("让 Mac 按你的节奏休息", at: NSPoint(x: 432, y: 206), font: .systemFont(ofSize: 30), color: Brand.white.withAlphaComponent(0.62))
        }
    }

    /// Apple's macOS icon grid: an 824-of-1024 tile, so RestBar matches its Dock
    /// neighbours. Flat black, no gradient, no glow.
    static func tile(size s: CGFloat, columns: Int) {
        let rect = NSRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8046, height: s * 0.8046)
        Brand.paper.setFill()
        NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18).fill()
        // Small sizes get a larger moon: the dots matter more than the margin there.
        let moon = s * (s >= 128 ? 0.53 : 0.64)
        let area = NSRect(x: (s - moon) / 2, y: (s - moon) / 2, width: moon, height: moon)
        if s > 32 {
            MoonMark.draw(in: area, columns: columns, phase: .resting, ink: Brand.white, signal: Brand.markRed)
        } else {
            solidMoon(in: area)
        }
    }

    /// Below about 40 pixels a dot is under two pixels wide and the grid turns to
    /// grey mush, so the smallest icons draw the same moon as a solid shape.
    static func solidMoon(in area: NSRect) {
        func circle(_ c: (x: CGFloat, y: CGFloat, radius: CGFloat)) -> NSBezierPath {
            let r = c.radius * area.width
            return NSBezierPath(ovalIn: NSRect(x: area.minX + c.x * area.width - r, y: area.minY + c.y * area.height - r, width: r * 2, height: r * 2))
        }
        NSGraphicsContext.saveGraphicsState()
        let outsideCut = NSBezierPath(rect: area.insetBy(dx: -area.width, dy: -area.height))
        outsideCut.append(circle(MoonMark.cut))
        outsideCut.windingRule = .evenOdd
        outsideCut.addClip()
        Brand.white.setFill()
        circle(MoonMark.disc).fill()
        NSGraphicsContext.restoreGraphicsState()
        Brand.markRed.setFill()
        circle((x: 0.72, y: 0.70, radius: 0.13)).fill()
    }

    static func wordmark(_ size: CGFloat) -> NSFont {
        let wght = 0x77676874 // 'wght'
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: "Bitcount Grid Single",
            NSFontDescriptor.AttributeName(kCTFontVariationAttribute as String): [wght: 300],
        ])
        guard let font = NSFont(descriptor: descriptor, size: size) else {
            print("Bitcount Grid Single did not load")
            exit(1)
        }
        return font
    }

    static func text(_ string: String, at point: NSPoint, font: NSFont, color: NSColor) {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]).draw(at: point)
    }

    static func png(width: Int, height: Int, to path: String, _ draw: () -> Void) throws {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}
