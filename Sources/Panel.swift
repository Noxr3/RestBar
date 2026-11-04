import SwiftUI
import AppKit

/// Two rules, from docs/BRAND.md: red belongs to the moon and to keeping the Mac
/// awake, and nothing is said twice.
struct Panel: View {
    static let size = NSSize(width: 340, height: 420)

    @ObservedObject var model: PowerController
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                MoonGlyph(phase: model.active ? .awake : .resting).frame(width: 18, height: 18)
                Text("RestBar").font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.active {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(remaining(context.date))
                            .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Picker(L("Page"), selection: $tab) {
                Text(L("Power")).tag(0)
                Text(L("Diagnostics")).tag(1)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 16).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if tab == 0 { controls } else { diagnostics }
                    if let notice = model.notice {
                        Text(notice).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if let error = model.error {
                        HStack(alignment: .top) {
                            Text(error).foregroundStyle(.orange).textSelection(.enabled)
                            Spacer(minLength: 0)
                            Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help(L("Dismiss error"))
                        }.font(.system(size: 11))
                    }
                }.padding(.horizontal, 16).padding(.bottom, 14).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: .infinity)

            Divider()
            HStack {
                Menu {
                    Toggle(L("Show battery in menu bar"), isOn: $model.showPercent)
                    Toggle(L("Start at login"), isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                    if model.loginNeedsApproval {
                        Button(L("Allow start at login in System Settings")) { SMSettings.openLogin() }
                    }
                    Divider()
                    ForEach(PowerProfile.allCases) { profile in
                        if let on = model.settings.lowPower(profile) {
                            Toggle(profile == .battery ? L("Low Power Mode on battery") : L("Low Power Mode when plugged in"),
                                   isOn: Binding(get: { on }, set: { model.setLowPower(profile, $0) }))
                                .disabled(model.busy)
                        }
                    }
                    Button(L("Battery Settings…")) { openBatterySettings() }
                    Divider()
                    Button(L("About RestBar")) { about() }
                } label: { Image(systemName: "gearshape").frame(width: 18) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L("Preferences"))
                Spacer()
                Button(L("Quit")) { model.cleanup(); NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).disabled(model.busy)
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color(nsColor: Brand.controlTint))
    }

    @ViewBuilder var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.battery.percent.map { "\($0)%" } ?? "—")
                .font(.system(size: 28, weight: .medium)).monospacedDigit()
            if let percent = model.battery.percent {
                GeometryReader { proxy in
                    Capsule().fill(Color.primary.opacity(0.1))
                        .overlay(alignment: .leading) {
                            Capsule().fill(percent <= 20 ? Color.orange : Color.primary)
                                .frame(width: max(0, proxy.size.width * CGFloat(percent) / 100))
                        }
                }.frame(height: 3)
            }
            Text(batteryLine).font(.system(size: 11)).foregroundStyle(.secondary)
        }

        Divider()

        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { model.active }, set: model.toggleAwake)) {
                Text(L("Keep Awake")).font(.system(size: 13, weight: .medium))
            }
            .toggleStyle(AwakeSwitch()).accessibilityIdentifier("keepAwake")
            Picker(L("Display"), selection: Binding(get: { model.mode }, set: model.setMode)) {
                ForEach(AwakeMode.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            Picker(L("Duration"), selection: Binding(get: { model.duration }, set: model.setDuration)) {
                Text(L("Until turned off")).tag(0)
                Text(L("15 minutes")).tag(15)
                Text(L("30 minutes")).tag(30)
                Text(L("1 hour")).tag(60)
                Text(L("2 hours")).tag(120)
                Text(L("4 hours")).tag(240)
            }.labelsHidden()
            Toggle(L("Stop at 20% battery when not charging"), isOn: $model.lowBatteryGuard)
            Toggle(L("Only while plugged in"), isOn: $model.onlyAC)
        }.font(.system(size: 12)).toggleStyle(.checkbox)

        Divider()

        HStack(spacing: 8) {
            Button(L("Turn Off Display"), action: model.displayOff)
            Button(L("Sleep Now…"), action: model.sleepNow)
        }.buttonStyle(QuietButton()).disabled(model.busy)
    }

    var diagnostics: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(L("System sleep policy"))
                if model.globalSleepDisabled == true {
                    Text(L("Sleep is disabled system-wide. Your Mac may not sleep even after RestBar stops."))
                        .font(.system(size: 11)).foregroundStyle(.orange)
                    Button(L("Restore System Sleep…"), action: model.restoreSystemSleep).buttonStyle(QuietButton()).disabled(model.busy)
                } else if model.globalSleepDisabled == nil {
                    Text(L("Not confirmed yet")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                let current: PowerProfile = model.battery.onAC ? .adapter : .battery
                if let profile = model.settings.profiles[current.section] {
                    if let sleep = profile["sleep"] { settingsRow(L("Automatic sleep"), idle(sleep)) }
                    if let display = profile["displaysleep"] { settingsRow(L("Turn display off"), idle(display)) }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle(L("What's preventing sleep"))
                    Spacer()
                    Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Refresh"))
                }
                if model.blockers.isEmpty {
                    Text(model.lastRefresh == nil ? L("Reading…") : L("Nothing")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(model.blockers) { blocker in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(blocker.process).font(.system(size: 12, weight: .medium))
                        Text(blocker.reason).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                    }
                }
                Text(L("The switch only releases RestBar's own request.")).font(.system(size: 10)).foregroundStyle(.secondary)
            }

            Divider()

            Button(L("Open Activity Monitor")) {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"), configuration: .init())
            }.buttonStyle(QuietButton())
        }
    }

    private var batteryLine: String {
        [model.battery.description, model.battery.estimate].compactMap { $0 }.joined(separator: " · ")
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .medium))
    }
    private func idle(_ minutes: Int) -> String {
        minutes == 0 ? L("Never") : String(format: L("After %d idle minutes"), minutes)
    }
    private func remaining(_ date: Date) -> String {
        guard let deadline = model.deadline else { return L("Awake") }
        let seconds = max(0, Int(deadline.timeIntervalSince(date)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    private func settingsRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value) }.font(.system(size: 11))
    }
    private func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    private func about() {
        model.closePanel?()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "RestBar",
            .applicationVersion: "1.0",
            .credits: NSAttributedString(string: L("Runs on your Mac, with no network requests.\nKeep-awake is temporary, and closing the lid still follows macOS rules.\nLow Power Mode is a system setting and stays changed after you quit.")),
        ])
    }
}

import ServiceManagement
enum SMSettings { static func openLogin() { SMAppService.openSystemSettingsLoginItems() } }

/// Drawn rather than the system switch, because the two states have to be told apart
/// at a glance: on is solid red with a white knob on the right; off is a hollow
/// outline with a grey knob on the left.
private struct AwakeSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.12)) { configuration.isOn.toggle() }
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 12).fill(configuration.isOn ? Color(nsColor: Brand.signal) : Color.clear)
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(configuration.isOn ? 0 : 0.4), lineWidth: 1.5)
                    Circle()
                        .fill(configuration.isOn ? Color.white : Color.primary.opacity(0.55))
                        .frame(width: 16, height: 16)
                        .padding(4)
                }
                .frame(width: 44, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Keep Awake"))
            .accessibilityValue(configuration.isOn ? L("On") : L("Off"))
        }
    }
}

/// A flat button that reads as available. The system bordered style renders so faintly
/// in a popover on macOS 26 that these looked disabled.
private struct QuietButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}
