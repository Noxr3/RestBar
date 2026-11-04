import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var model: PowerController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second Finder launch focuses the already-running instance.
        if let identifier = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        model = PowerController()
        model.applyLoginDefault()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = Panel.size
        model.onStatusChange = { [weak self] in self?.updateStatus() }
        model.closePanel = { [weak self] in self?.popover.performClose(nil) }
        updateStatus()
        if CommandLine.arguments.contains("--show") { showPanel() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if popover != nil { showPanel() }
        return true
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let open = NSMenuItem(title: L("Open RestBar"), action: #selector(showFromMenu), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            if model.active {
                let stop = NSMenuItem(title: L("Stop Keeping Awake"), action: #selector(stopFromMenu), keyEquivalent: "")
                stop.target = self
                menu.addItem(stop)
            }
            menu.addItem(.separator())
            let quit = NSMenuItem(title: L("Quit RestBar"), action: #selector(quitFromMenu), keyEquivalent: "q")
            quit.target = self
            quit.isEnabled = !model.busy
            menu.autoenablesItems = false
            menu.addItem(quit)
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else { showPanel() }
    }
    @objc private func showFromMenu() { showPanel() }
    @objc private func stopFromMenu() { model.stop(L("RestBar released its keep-awake request.")) }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    private func showPanel() {
        guard let button = statusItem.button else { return }
        // Recreate the view on opening so the countdown never ticks while hidden.
        popover.contentViewController = NSHostingController(rootView: Panel(model: model))
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task { await model.refresh() }
    }
    func popoverDidClose(_ notification: Notification) { popover.contentViewController = nil }

    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        button.image = MoonMark.menuBarImage(phase: model.active ? .awake : .resting)
        button.imagePosition = .imageLeading
        button.title = model.showPercent ? model.battery.percent.map { " \($0)%" } ?? "" : ""
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.toolTip = "RestBar · \(model.active ? L("Keeping awake") : L("Not preventing sleep")) · \(model.battery.description)"
        button.setAccessibilityLabel(button.toolTip)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.busy == true { return .terminateCancel }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { model?.cleanup() }
}
