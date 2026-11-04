import SwiftUI
import AppKit

struct Panel: View {
    @ObservedObject var model: PowerController
    @State private var tab = 0
    private let signal = Color(nsColor: Brand.signal)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MoonGlyph(phase: model.active ? .awake : .resting).frame(width: 26, height: 26)
                    .frame(width: 42, height: 42).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("RestBar").font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("让 Mac 按你的节奏休息").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(model.active ? signal : Color.secondary).frame(width: 7, height: 7)
                Text(model.active ? "唤醒中" : "待机").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }.padding(18)

            Picker("页面", selection: $tab) {
                Text("电源控制").tag(0)
                Text("休眠诊断").tag(1)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 18).padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 12) {
                    if tab == 0 { controls } else { diagnostics }
                    if let notice = model.notice {
                        Label(notice, systemImage: model.busy ? "hourglass" : "info.circle")
                            .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = model.error {
                        HStack(alignment: .top) {
                            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled)
                            Spacer(minLength: 0)
                            Button { model.error = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("关闭错误提示")
                        }.font(.system(size: 11)).padding(10).background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                }.padding(.horizontal, 18).padding(.bottom, 14)
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
                .menuStyle(.borderlessButton).fixedSize().tint(.secondary).help("偏好设置")
                Text("仅在菜单栏运行").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button("退出") { model.cleanup(); NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11)).disabled(model.busy)
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(width: 374, height: 710)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color(nsColor: Brand.signalFill))
    }

    @ViewBuilder var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.battery.percent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                Spacer()
                Image(systemName: model.battery.charging ? "battery.100percent.bolt" : "battery.\(batterySymbol)percent")
                    .font(.system(size: 28)).foregroundStyle(model.battery.percent.map { $0 <= 20 } == true ? Color.orange : Color.primary)
            }
            if let percent = model.battery.percent {
                GeometryReader { proxy in
                    Capsule().fill(Color.primary.opacity(0.12))
                        .overlay(alignment: .leading) { Capsule().fill(Color.primary).frame(width: max(0, proxy.size.width * CGFloat(percent) / 100)) }
                }.frame(height: 5)
            }
            HStack {
                Text(model.battery.description).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: model.battery.onAC ? "powerplug.fill" : "bolt.fill").foregroundStyle(.secondary)
            }
            Text(model.battery.estimate).font(.system(size: 10)).foregroundStyle(.secondary)
        }.card()

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("保持唤醒").font(.system(size: 13, weight: .semibold))
                        Text(model.active ? "RestBar 正在阻止自动休眠" : "RestBar 未阻止自动休眠").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                } icon: { MoonGlyph(phase: model.active ? .awake : .resting, columns: 9).frame(width: 16, height: 16) }
                Spacer()
                Toggle("保持唤醒", isOn: Binding(get: { model.active }, set: model.toggleAwake))
                    .toggleStyle(.switch).labelsHidden().accessibilityIdentifier("keepAwake")
            }
            Picker("屏幕", selection: Binding(get: { model.mode }, set: model.setMode)) {
                ForEach(AwakeMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Text("持续时间").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Picker("持续时间", selection: Binding(get: { model.duration }, set: model.setDuration)) {
                    Text("15 分钟").tag(15)
                    Text("30 分钟").tag(30)
                    Text("1 小时").tag(60)
                    Text("2 小时").tag(120)
                    Text("4 小时").tag(240)
                    Text("直到手动关闭").tag(0)
                }.labelsHidden().frame(width: 158)
            }
            if model.active {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(remaining(context.date), systemImage: "timer")
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(signal)
                }
            }
            Text("退出应用即释放。合盖仍按 macOS 规则休眠。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.card()

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("低电量模式", systemImage: "leaf.fill").font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            Picker("电源场景", selection: $model.selectedProfile) {
                ForEach(PowerProfile.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().disabled(model.busy)
            HStack {
                Text(model.settings.lowPower(model.selectedProfile) == nil ? "此场景不可用或未读取到" : "降低能耗，优先续航")
                    .font(.system(size: 12))
                Spacer()
                Toggle("低电量模式", isOn: Binding(get: { model.settings.lowPower(model.selectedProfile) ?? false }, set: model.setLowPower))
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(model.busy || model.settings.lowPower(model.selectedProfile) == nil)
            }
            Text("修改需要系统授权，退出应用后设置仍保留。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.card()

        VStack(alignment: .leading, spacing: 10) {
            Toggle("电量 ≤ 20% 且未充电时停止唤醒", isOn: $model.lowBatteryGuard)
            Toggle("仅接通电源时保持唤醒", isOn: $model.onlyAC)
        }.font(.system(size: 11)).toggleStyle(.checkbox).card()

        HStack(spacing: 10) {
            Button(action: model.displayOff) { Label("关闭屏幕", systemImage: "display").frame(maxWidth: .infinity) }
            Button(action: model.sleepNow) { Label("立即休眠…", systemImage: "moon.zzz").frame(maxWidth: .infinity) }
        }.controlSize(.large).disabled(model.busy)
    }

    var diagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                Label("系统休眠策略", systemImage: "slider.horizontal.3").font(.system(size: 13, weight: .semibold))
                if model.globalSleepDisabled == true {
                    Text("系统全局禁止了休眠").foregroundStyle(.orange)
                    Text("即使关闭 RestBar 的保持唤醒，系统仍可能无法休眠。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("恢复系统休眠…", action: model.restoreSystemSleep).disabled(model.busy)
                } else if model.globalSleepDisabled == false {
                    Label("系统允许休眠", systemImage: "checkmark.circle.fill").foregroundStyle(.primary)
                } else {
                    Text("系统休眠策略尚未确认").foregroundStyle(.secondary)
                }
                let current: PowerProfile = model.battery.onAC ? .adapter : .battery
                if let profile = model.settings.profiles[current.section] {
                    if let sleep = profile["sleep"] { settingsRow("自动休眠", sleep == 0 ? "从不" : "闲置 \(sleep) 分钟") }
                    if let display = profile["displaysleep"] { settingsRow("关闭屏幕", display == 0 ? "从不" : "闲置 \(display) 分钟") }
                }
            }.font(.system(size: 12)).card()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("谁在阻止自动休眠").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("刷新诊断")
                }
                if model.blockers.isEmpty {
                    Text(model.lastRefresh == nil ? "正在读取…" : "本次未检测到应用防休眠请求")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(model.blockers) { blocker in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(blocker.process, systemImage: blocker.process == "RestBar" ? "cup.and.saucer" : "app.dashed")
                            .font(.system(size: 12, weight: .medium))
                        Text(blocker.reason).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                    }
                    if blocker.id != model.blockers.last?.id { Divider() }
                }
                Text("关闭本工具的开关只释放 RestBar 自己的请求。其他应用仍可保持 Mac 唤醒。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                if let date = model.lastRefresh {
                    Text("更新于 \(date.formatted(date: .omitted, time: .standard))").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }.card()

            Button {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"), configuration: .init())
            } label: { Label("查看活动监视器", systemImage: "waveform.path.ecg").frame(maxWidth: .infinity) }.controlSize(.large)
            Text("在活动监视器的「能耗」页查看应用消耗。RestBar 不估算或虚构整机瓦数。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var batterySymbol: Int { guard let p = model.battery.percent else { return 0 }; return p >= 88 ? 100 : p >= 63 ? 75 : p >= 38 ? 50 : p >= 13 ? 25 : 0 }
    private func remaining(_ date: Date) -> String {
        guard let deadline = model.deadline else { return "保持唤醒 · 直到手动关闭" }
        let seconds = max(0, Int(deadline.timeIntervalSince(date)))
        return String(format: "剩余 %02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
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
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "RestBar", .applicationVersion: "1.0", .credits: NSAttributedString(string: "一个轻量的菜单栏电源助手。\n本地运行，无网络请求。\n保持唤醒是临时的；系统低电量设置会保留。")])
    }
}

import ServiceManagement
enum SMSettings { static func openLogin() { SMAppService.openSystemSettingsLoginItems() } }

private extension View {
    func card() -> some View {
        self.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.055), lineWidth: 1))
    }
}
