import SwiftUI
import AppKit

/// Two rules, from docs/BRAND.md: red belongs to the moon and to keeping the Mac
/// awake, and nothing is said twice.
struct Panel: View {
    static let size = NSSize(width: 340, height: 500)

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

            Picker("页面", selection: $tab) {
                Text("电源").tag(0)
                Text("诊断").tag(1)
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
                            Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭错误提示")
                        }.font(.system(size: 11))
                    }
                }.padding(.horizontal, 16).padding(.bottom, 14).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: .infinity)

            Divider()
            HStack {
                Menu {
                    Toggle("在菜单栏显示电量", isOn: $model.showPercent)
                    Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                    if model.loginNeedsApproval {
                        Button("在系统设置中允许登录启动") { SMSettings.openLogin() }
                    }
                    Divider()
                    Button("打开电池设置") { openBatterySettings() }
                    Button("关于 RestBar") { about() }
                } label: { Image(systemName: "gearshape").frame(width: 18) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("偏好设置")
                Spacer()
                Button("退出") { model.cleanup(); NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).disabled(model.busy)
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
            Toggle(isOn: Binding(get: { model.active }, set: model.toggleAwake)) { sectionTitle("保持唤醒") }
                .toggleStyle(RowSwitch()).tint(Color(nsColor: Brand.signal)).accessibilityIdentifier("keepAwake")
            Picker("屏幕", selection: Binding(get: { model.mode }, set: model.setMode)) {
                ForEach(AwakeMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            Picker("持续时间", selection: Binding(get: { model.duration }, set: model.setDuration)) {
                Text("15 分钟").tag(15)
                Text("30 分钟").tag(30)
                Text("1 小时").tag(60)
                Text("2 小时").tag(120)
                Text("4 小时").tag(240)
                Text("直到手动关闭").tag(0)
            }.labelsHidden()
            Toggle("电量 ≤ 20% 且未充电时停止", isOn: $model.lowBatteryGuard)
            Toggle("仅接通电源时保持唤醒", isOn: $model.onlyAC)
        }.font(.system(size: 12)).toggleStyle(.checkbox)

        Divider()

        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { model.settings.lowPower(model.selectedProfile) ?? false }, set: model.setLowPower)) {
                HStack(spacing: 6) {
                    sectionTitle("低电量模式")
                    if model.busy { ProgressView().controlSize(.mini) }
                }
            }
            .toggleStyle(RowSwitch())
            .disabled(model.busy || model.settings.lowPower(model.selectedProfile) == nil)
            Picker("电源场景", selection: $model.selectedProfile) {
                ForEach(PowerProfile.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().disabled(model.busy)
            if model.settings.lowPower(model.selectedProfile) == nil {
                Text("此场景不可用或未读取到").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }

        Divider()

        HStack(spacing: 8) {
            Button(action: model.displayOff) { Text("关闭屏幕").frame(maxWidth: .infinity) }
            Button(action: model.sleepNow) { Text("立即休眠…").frame(maxWidth: .infinity) }
        }.disabled(model.busy)
    }

    var diagnostics: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("系统休眠策略")
                if model.globalSleepDisabled == true {
                    Text("系统全局禁止了休眠。关闭 RestBar 后，系统仍可能无法休眠。").font(.system(size: 11)).foregroundStyle(.orange)
                    Button("恢复系统休眠…", action: model.restoreSystemSleep).disabled(model.busy)
                } else if model.globalSleepDisabled == nil {
                    Text("尚未确认").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                let current: PowerProfile = model.battery.onAC ? .adapter : .battery
                if let profile = model.settings.profiles[current.section] {
                    if let sleep = profile["sleep"] { settingsRow("自动休眠", sleep == 0 ? "从不" : "闲置 \(sleep) 分钟") }
                    if let display = profile["displaysleep"] { settingsRow("关闭屏幕", display == 0 ? "从不" : "闲置 \(display) 分钟") }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("谁在阻止自动休眠")
                    Spacer()
                    Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("刷新诊断")
                }
                if model.blockers.isEmpty {
                    Text(model.lastRefresh == nil ? "正在读取…" : "没有").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(model.blockers) { blocker in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(blocker.process).font(.system(size: 12, weight: .medium))
                        Text(blocker.reason).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                    }
                }
                Text("关闭开关只释放 RestBar 自己的请求。").font(.system(size: 10)).foregroundStyle(.secondary)
            }

            Divider()

            Button {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"), configuration: .init())
            } label: { Text("打开活动监视器").frame(maxWidth: .infinity) }
        }
    }

    /// The estimate only when macOS actually gave one: the placeholder sentences say nothing.
    private var batteryLine: String {
        let battery = model.battery
        guard battery.minutesRemaining != nil, !(battery.onAC && !battery.charging) else { return battery.description }
        return "\(battery.description) · \(battery.estimate)"
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .medium))
    }
    private func remaining(_ date: Date) -> String {
        guard let deadline = model.deadline else { return "唤醒中" }
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
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "RestBar", .applicationVersion: "1.0", .credits: NSAttributedString(string: "一个轻量的菜单栏电源助手。\n本地运行，无网络请求。\n保持唤醒是临时的，合盖仍按 macOS 规则休眠。\n低电量模式是系统设置，退出后仍保留。")])
    }
}

import ServiceManagement
enum SMSettings { static func openLogin() { SMAppService.openSystemSettingsLoginItems() } }

/// A title on the left and a small switch on the right edge.
private struct RowSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Toggle("", isOn: configuration.$isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
    }
}
