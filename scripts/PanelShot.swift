// The panel renderer behind scripts/screenshots.sh.
import AppKit
import SwiftUI

/// Controls draw in their inactive grey in a window that is not key, and this
/// window is never on screen.
private final class ShotWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

@main
struct PanelShot {
    @MainActor static func main() {
        guard CommandLine.arguments.count >= 2 else {
            print("usage: PanelShot <output-dir>")
            exit(2)
        }
        let output = CommandLine.arguments[1]
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let model = PowerController()
        // Long enough for the first pmset readback to land in the panel.
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))

        func shot(_ name: String, _ appearance: NSAppearance.Name) {
            let size = Panel.size
            let host = NSHostingView(rootView: Panel(model: model).frame(width: size.width, height: size.height))
            host.frame = NSRect(origin: .zero, size: size)
            let window = ShotWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            do {
                try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/\(name).png"))
            } catch {
                print("failed: \(error)")
                exit(1)
            }
        }

        shot("panel-resting-light", .aqua)
        shot("panel-resting-dark", .darkAqua)
        model.toggleAwake(true)
        guard model.active else {
            print("keep-awake did not start: \(model.notice ?? model.error ?? "unknown")")
            exit(1)
        }
        shot("panel-awake-light", .aqua)
        shot("panel-awake-dark", .darkAqua)
        model.cleanup()
    }
}
