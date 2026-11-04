import AppKit
import SwiftUI

/// The one definition of RestBar's look. The app, the icon and the README images
/// all draw from here; docs/BRAND.md explains the rules.
enum Brand {
    static let paper = hex(0x191919)
    static let white = hex(0xFFFFFF)
    /// The mark's red dot.
    static let markRed = hex(0xF50233)
    /// The one red thing in the app: the dot beside the timer while awake.
    static let signal = dynamic(light: 0xED0031, dark: 0xFF1748)
    /// Checked controls. Grey rather than white on dark, so a white knob still shows.
    static let controlTint = dynamic(light: 0x191919, dark: 0x8A8A8A)

    static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? hex(dark) : hex(light)
        }
    }
}

/// A moon drawn on a dot grid: a crescent at rest, the full disc while awake.
/// Coordinates are a unit square with y pointing up.
enum MoonMark {
    enum Phase { case resting, awake }
    struct Dot: Equatable {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
    }

    /// Dots are 80% of their cell, the same fill Dokki's dot marks use.
    static let fill: CGFloat = 0.8
    static let disc = (x: CGFloat(0.5), y: CGFloat(0.5), radius: CGFloat(0.5))
    static let cut = (x: CGFloat(0.64), y: CGFloat(0.64), radius: CGFloat(0.42))

    static func dots(columns: Int, phase: Phase) -> [Dot] {
        let cell = 1 / CGFloat(columns)
        func inside(_ x: CGFloat, _ y: CGFloat, _ c: (x: CGFloat, y: CGFloat, radius: CGFloat)) -> Bool {
            let dx = x - c.x, dy = y - c.y
            return dx * dx + dy * dy <= c.radius * c.radius
        }
        var result: [Dot] = []
        for row in 0..<columns {
            for column in 0..<columns {
                let x = (CGFloat(column) + 0.5) * cell, y = (CGFloat(row) + 0.5) * cell
                guard inside(x, y, disc), phase == .awake || !inside(x, y, cut) else { continue }
                result.append(Dot(x: x, y: y, radius: cell * fill / 2))
            }
        }
        return result
    }

    /// The logo's red dot: on the grid, in the crescent's mouth, the size of its
    /// neighbours. Only the logo has it. Inside the product the moon is one colour.
    static func logoDot(columns: Int) -> Dot {
        let cell = 1 / CGFloat(columns)
        let column = (0.70 / cell).rounded(.down), row = (0.68 / cell).rounded(.down)
        return Dot(x: (column + 0.5) * cell, y: (row + 0.5) * cell, radius: cell * fill / 2)
    }

    /// Few enough columns that every dot still lands on a pixel at small sizes.
    static func columns(forPixelSize size: Int) -> Int {
        size >= 128 ? 11 : 9
    }

    static func draw(in rect: NSRect, columns: Int, phase: Phase, ink: NSColor, logoDot dotColor: NSColor? = nil) {
        func fill(_ dot: Dot) {
            let radius = dot.radius * rect.width
            NSBezierPath(ovalIn: NSRect(
                x: rect.minX + dot.x * rect.width - radius,
                y: rect.minY + dot.y * rect.height - radius,
                width: radius * 2, height: radius * 2
            )).fill()
        }
        ink.setFill()
        dots(columns: columns, phase: phase).forEach(fill)
        if let dotColor {
            dotColor.setFill()
            fill(logoDot(columns: columns))
        }
    }

    /// The menu bar image: always a template, so macOS colours it for the bar. Its
    /// shape says the state, so it stays quiet in a bar full of other apps' icons.
    static func menuBarImage(phase: Phase) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            draw(in: rect.insetBy(dx: 1, dy: 1), columns: 9, phase: phase, ink: .black)
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The moon as a SwiftUI view, for the panel.
struct MoonGlyph: View {
    let phase: MoonMark.Phase
    var columns = 9

    var body: some View {
        Canvas { context, size in
            for dot in MoonMark.dots(columns: columns, phase: phase) {
                let radius = dot.radius * size.width
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: dot.x * size.width - radius,
                        y: (1 - dot.y) * size.height - radius,
                        width: radius * 2, height: radius * 2
                    )),
                    with: .color(.primary)
                )
            }
        }
        .accessibilityHidden(true)
    }
}
