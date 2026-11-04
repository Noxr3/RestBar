import AppKit
import SwiftUI
import ServiceManagement
import IOKit.ps

@MainActor
final class PowerController: ObservableObject {
    @Published var battery = BatterySnapshot.read()
    @Published var active = false
    @Published var mode: AwakeMode = .system
    @Published var duration = 60
    @Published var deadline: Date?
    @Published var settings = PowerSettings("")
    @Published var globalSleepDisabled: Bool?
    @Published var blockers: [SleepBlocker] = []
    @Published var busy = false
    @Published var error: String?
    @Published var notice: String?
    @Published var lastRefresh: Date?
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var selectedProfile: PowerProfile = .adapter
    @Published var lowBatteryGuard: Bool { didSet { UserDefaults.standard.set(lowBatteryGuard, forKey: "lowBatteryGuard"); enforcePolicy() } }
    @Published var onlyAC: Bool { didSet { UserDefaults.standard.set(onlyAC, forKey: "onlyAC"); enforcePolicy() } }
    @Published var showPercent: Bool { didSet { UserDefaults.standard.set(showPercent, forKey: "showPercent"); onStatusChange?() } }
    var onStatusChange: (() -> Void)?
    var closePanel: (() -> Void)?
    private let assertion = PowerAssertion()
    private var refreshTimer: Timer?
    private var expiryTimer: Timer?
    private var powerSource: CFRunLoopSource?
    private var refreshing = false

    init() {
        let defaults = UserDefaults.standard
        lowBatteryGuard = defaults.object(forKey: "lowBatteryGuard") as? Bool ?? true
        onlyAC = defaults.bool(forKey: "onlyAC")
        showPercent = defaults.object(forKey: "showPercent") as? Bool ?? false
        selectedProfile = battery.onAC ? .adapter : .battery
        refreshLogin()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshBattery() }
        }
        refreshTimer?.tolerance = 10
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let controller = Unmanaged<PowerController>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in controller.refreshBattery() }
        }
        powerSource = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        Task { await refresh() }
    }

    @objc private func woke() {
        refreshBattery()
        Task { await refresh() }
    }

    func refreshBattery() {
        battery = .read()
        enforcePolicy()
        onStatusChange?()
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        refreshBattery()
        async let config = Command.asyncRun("/usr/bin/pmset", ["-g", "custom"])
        async let global = Command.asyncRun("/usr/bin/pmset", ["-g"])
        async let assertions = Command.asyncRun("/usr/bin/pmset", ["-g", "assertions"])
        let (c, g, a) = await (config, global, assertions)
        settings = PowerSettings(c.status == 0 ? c.output : "")
        globalSleepDisabled = g.status == 0 ? PowerSettings.sleepDisabled(g.output) : nil
        blockers = a.status == 0 ? SleepBlocker.parse(a.output) : []
        if c.status != 0 || g.status != 0 || a.status != 0 { error = "部分系统状态读取失败，请重试。" }
        lastRefresh = Date()
        refreshLogin()
        onStatusChange?()
    }

    func toggleAwake(_ enabled: Bool) {
        if !enabled { stop("已释放 RestBar 的防休眠请求"); return }
        battery = .read()
        if let reason = AwakePolicy.stopReason(battery: battery, lowBattery: lowBatteryGuard, onlyAC: onlyAC, deadline: nil, now: Date()) {
            notice = reason
            return
        }
        do {
            let seconds = TimeInterval(duration * 60)
            try assertion.start(mode: mode, seconds: seconds)
            deadline = duration > 0 ? Date().addingTimeInterval(seconds) : nil
            active = true
            notice = nil
            scheduleExpiry()
            onStatusChange?()
        } catch { self.error = error.localizedDescription }
    }

    func setMode(_ next: AwakeMode) {
        guard next != mode else { return }
        if active {
            if let deadline, deadline <= Date() { stop("定时结束，已允许自动休眠") }
            else {
                do { try assertion.start(mode: next, seconds: deadline.map { max(1, $0.timeIntervalSinceNow) } ?? 0) }
                catch { self.error = error.localizedDescription; return }
            }
        }
        mode = next
        onStatusChange?()
    }

    func setDuration(_ minutes: Int) {
        guard [0, 15, 30, 60, 120, 240].contains(minutes) else { return }
        duration = minutes
        if active { toggleAwake(true) }
    }

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        if let deadline {
            expiryTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, deadline.timeIntervalSinceNow + 0.1), repeats: false) { [weak self] _ in
                Task { @MainActor in self?.enforcePolicy() }
            }
        }
    }

    func stop(_ message: String? = nil) {
        assertion.stop()
        expiryTimer?.invalidate()
        expiryTimer = nil
        active = false
        deadline = nil
        notice = message
        onStatusChange?()
    }

    private func enforcePolicy() {
        guard active else { return }
        if let reason = AwakePolicy.stopReason(battery: battery, lowBattery: lowBatteryGuard, onlyAC: onlyAC, deadline: deadline, now: Date()) { stop(reason) }
    }

    func setLowPower(_ enabled: Bool) {
        guard !busy, settings.lowPower(selectedProfile) != nil else { return }
        let profile = selectedProfile
        authorize("/usr/bin/pmset \(profile.argument) \(settings.lowPowerKey(profile)) \(enabled ? 1 : 0)") { [weak self] in
            guard let self else { return }
            let result = await Command.asyncRun("/usr/bin/pmset", ["-g", "custom"])
            self.settings = PowerSettings(result.output)
            if result.status == 0 && self.settings.lowPower(profile) == enabled {
                self.notice = "\(profile.rawValue)时：低电量模式已\(enabled ? "开启" : "关闭")"
            } else { self.error = "命令已执行，但未确认设置生效。请在系统设置中检查。" }
        }
    }

    func restoreSystemSleep() {
        authorize("/usr/bin/pmset -a disablesleep 0") { [weak self] in
            guard let self else { return }
            let result = await Command.asyncRun("/usr/bin/pmset", ["-g"])
            self.globalSleepDisabled = PowerSettings.sleepDisabled(result.output)
            if result.status == 0 && self.globalSleepDisabled == false { self.notice = "系统已允许休眠" }
            else { self.error = "无法确认系统防休眠已关闭，请刷新后检查。" }
        }
    }

    private func authorize(_ command: String, verified: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        notice = "请在 macOS 授权窗口中确认…"
        Task {
            defer { busy = false; onStatusChange?() }
            let result = await Command.asyncRun("/usr/bin/osascript", ["-e", "do shell script \"\(command)\" with administrator privileges"])
            if result.status == 0 { await verified() }
            else if result.output.contains("-128") { notice = "已取消，系统设置未更改" }
            else { notice = nil; error = "系统未能应用设置：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))" }
        }
    }

    func displayOff() {
        if active && mode == .display { setMode(.system) }
        guard mode != .display || !active else { return }
        closePanel?()
        Task {
            let result = await Command.asyncRun("/usr/bin/pmset", ["displaysleepnow"])
            if result.status != 0 { error = "无法关闭屏幕：\(result.output)" }
        }
    }

    func sleepNow() {
        closePanel?()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "现在让 Mac 休眠？"
        alert.informativeText = "运行中的下载、编译和远程连接可能暂停。RestBar 会先释放自己的防休眠请求。"
        alert.addButton(withTitle: "立即休眠")
        alert.addButton(withTitle: "取消")
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        stop()
        Task {
            let result = await Command.asyncRun("/usr/bin/pmset", ["sleepnow"])
            if result.status != 0 { error = "无法进入休眠：\(result.output)" }
        }
    }

    func refreshLogin() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLogin()
            if loginNeedsApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = "登录启动设置失败：\(error.localizedDescription)"; refreshLogin() }
    }

    func cleanup() {
        stop()
        refreshTimer?.invalidate()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        powerSource = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
