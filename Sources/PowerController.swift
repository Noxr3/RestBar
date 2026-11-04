import AppKit
import SwiftUI
import ServiceManagement
import IOKit.ps

enum AwakeSource { case person, agent }

@MainActor
final class PowerController: ObservableObject {
    @Published var battery = BatterySnapshot.read()
    @Published var active = false
    @Published var source = AwakeSource.person
    @Published var agents: [AgentDetector.Agent] = []
    @Published var workingAgents: [String] = []
    @Published var holdingLid = false
    @Published var agentMode: Bool { didSet { UserDefaults.standard.set(agentMode, forKey: "agentMode"); Task { await checkAgents() } } }
    @Published private(set) var lidMode: Bool { didSet { UserDefaults.standard.set(lidMode, forKey: "lidMode") } }
    var lidRuleInstalled: Bool { FileManager.default.fileExists(atPath: LidHold.rulePath) }
    @Published var mode: AwakeMode = .system
    @Published var duration = 0
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
    private var agentTimer: Timer?
    private var watch = AgentWatch()
    /// The person turned it off, or a safety stop did, while an agent was working. Stays
    /// off until that agent finishes, rather than coming straight back.
    private var agentSnoozed = false
    private var lidWatchdog: Process?
    private let lidOwnedKey = "lidHoldOwned"

    init() {
        let defaults = UserDefaults.standard
        lowBatteryGuard = defaults.object(forKey: "lowBatteryGuard") as? Bool ?? true
        onlyAC = defaults.bool(forKey: "onlyAC")
        showPercent = defaults.object(forKey: "showPercent") as? Bool ?? false
        agentMode = defaults.object(forKey: "agentMode") as? Bool ?? true
        lidMode = defaults.bool(forKey: "lidMode")
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
        NotificationCenter.default.addObserver(self, selector: #selector(thermalChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        Task { await refresh() }
    }

    @objc private nonisolated func thermalChanged() {
        Task { @MainActor in self.enforcePolicy() }
    }

    /// Called once by the app. Separate from init so rendering the panel for screenshots
    /// never starts a session by itself.
    func startWatching() {
        restoreLidIfLeftOn()
        agentTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkAgents() }
        }
        agentTimer?.tolerance = 3
        Task { await checkAgents() }
    }

    func checkAgents() async {
        guard agentMode else {
            agents = []
            workingAgents = []
            agentSnoozed = false
            if active && source == .agent { stop() }
            return
        }
        let sampled = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: AgentDetector.sample()) }
        }
        agents = sampled
        workingAgents = watch.update(sampled, now: Date())
        guard !workingAgents.isEmpty else {
            agentSnoozed = false
            if active && source == .agent { stop(L("Agents finished. Your Mac can sleep again.")) }
            return
        }
        guard !active, !agentSnoozed else { return }
        battery = .read()
        guard AwakePolicy.stopReason(battery: battery, lowBattery: lowBatteryGuard, onlyAC: onlyAC, deadline: nil, now: Date()) == nil,
              !lidMode || LidHold.stopReason(battery: battery, thermal: ProcessInfo.processInfo.thermalState) == nil else { return }
        startAssertion(source: .agent, seconds: 0)
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
        if c.status != 0 || g.status != 0 || a.status != 0 { error = L("Some system status couldn't be read. Try again.") }
        lastRefresh = Date()
        refreshLogin()
        onStatusChange?()
    }

    func toggleAwake(_ enabled: Bool) {
        if !enabled {
            agentSnoozed = !workingAgents.isEmpty
            stop(L("RestBar released its keep-awake request."))
            return
        }
        battery = .read()
        if let reason = AwakePolicy.stopReason(battery: battery, lowBattery: lowBatteryGuard, onlyAC: onlyAC, deadline: nil, now: Date()) {
            notice = reason
            return
        }
        startAssertion(source: .person, seconds: TimeInterval(duration * 60))
    }

    private func startAssertion(source next: AwakeSource, seconds: TimeInterval) {
        do {
            try assertion.start(mode: mode, seconds: seconds)
            deadline = seconds > 0 ? Date().addingTimeInterval(seconds) : nil
            source = next
            active = true
            notice = nil
            scheduleExpiry()
            applyLid()
            onStatusChange?()
        } catch { self.error = error.localizedDescription }
    }

    func setMode(_ next: AwakeMode) {
        guard next != mode else { return }
        if active {
            if let deadline, deadline <= Date() { stop(L("Time is up. Your Mac can sleep again.")) }
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
        if active && source == .person { toggleAwake(true) }
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
        source = .person
        deadline = nil
        notice = message
        applyLid()
        onStatusChange?()
    }

    private func enforcePolicy() {
        guard active else { return }
        var reason = AwakePolicy.stopReason(battery: battery, lowBattery: lowBatteryGuard, onlyAC: onlyAC, deadline: deadline, now: Date())
        if reason == nil && holdingLid {
            reason = LidHold.stopReason(battery: battery, thermal: ProcessInfo.processInfo.thermalState)
        }
        if let reason {
            agentSnoozed = !workingAgents.isEmpty
            stop(reason)
        }
    }

    // MARK: Lid closed

    /// Turning it on the first time installs the permission that lets RestBar switch this
    /// one setting back unattended, after saying plainly what it does.
    func setLidMode(_ enabled: Bool) {
        guard enabled else {
            lidMode = false
            applyLid()
            return
        }
        guard !lidRuleInstalled else {
            lidMode = true
            applyLid()
            return
        }
        guard let rule = LidHold.sudoersRule(user: NSUserName()) else {
            error = L("Your account name can't be used for this setting.")
            return
        }
        closePanel?()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Keep running with the lid closed?")
        alert.informativeText = L("While RestBar keeps your Mac awake, it stays on with the lid closed, then sleeps as usual when it's done. It can get hot, so don't put it in a bag. RestBar stops at 20% battery or if your Mac runs hot.\n\nmacOS will ask for your password once, to let RestBar change this one setting.")
        alert.addButton(withTitle: L("Continue"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        authorize(LidHold.installCommand(rule: rule)) { [weak self] in
            guard let self else { return }
            self.notice = nil
            self.lidMode = true
            self.applyLid()
        }
    }

    func removeLidPermission() {
        lidMode = false
        applyLid()
        authorize(LidHold.removeCommand) { [weak self] in
            self?.notice = L("Lid-closed permission removed.")
        }
    }

    private func applyLid() {
        if active && lidMode && !holdingLid { holdLid() }
        else if !(active && lidMode) && holdingLid { releaseLid() }
    }

    private func holdLid() {
        let current = Command.run("/usr/bin/pmset", ["-g"])
        if current.status == 0, PowerSettings.sleepDisabled(current.output) == true {
            // Someone else turned it off. Theirs to turn back on, so RestBar leaves it alone.
            holdingLid = true
            return
        }
        let result = Command.run("/usr/bin/sudo", LidHold.onArguments)
        guard result.status == 0 else {
            lidMode = false
            error = String(format: L("Couldn't keep running with the lid closed: %@"), result.output.trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }
        UserDefaults.standard.set(true, forKey: lidOwnedKey)
        holdingLid = true
        startLidWatchdog()
    }

    private func releaseLid() {
        holdingLid = false
        lidWatchdog?.terminate()
        lidWatchdog = nil
        guard UserDefaults.standard.bool(forKey: lidOwnedKey) else { return }
        let result = Command.run("/usr/bin/sudo", LidHold.offArguments)
        if result.status == 0 {
            UserDefaults.standard.set(false, forKey: lidOwnedKey)
        } else {
            error = String(format: L("Couldn't restore system sleep: %@"), result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func startLidWatchdog() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", LidHold.watchdogScript(restore: LidHold.restoreCommand), "restbar-watchdog", String(ProcessInfo.processInfo.processIdentifier)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            lidWatchdog = process
        } catch {
            // Without a way back, the setting must not stay on.
            releaseLid()
            lidMode = false
            self.error = error.localizedDescription
        }
    }

    private func restoreLidIfLeftOn() {
        let defaults = UserDefaults.standard
        guard LidHold.needsRestore(owned: defaults.bool(forKey: lidOwnedKey), holding: holdingLid) else { return }
        if Command.run("/usr/bin/sudo", LidHold.offArguments).status == 0 { defaults.set(false, forKey: lidOwnedKey) }
    }

    func setLowPower(_ profile: PowerProfile, _ enabled: Bool) {
        guard !busy, settings.lowPower(profile) != nil else { return }
        authorize("/usr/bin/pmset \(profile.argument) \(settings.lowPowerKey(profile)) \(enabled ? 1 : 0)") { [weak self] in
            guard let self else { return }
            let result = await Command.asyncRun("/usr/bin/pmset", ["-g", "custom"])
            self.settings = PowerSettings(result.output)
            if result.status == 0 && self.settings.lowPower(profile) == enabled {
                self.notice = enabled ? L("Low Power Mode is on.") : L("Low Power Mode is off.")
            } else { self.error = L("The command ran, but the setting couldn't be confirmed. Check System Settings.") }
        }
    }

    func restoreSystemSleep() {
        authorize("/usr/bin/pmset -a disablesleep 0") { [weak self] in
            guard let self else { return }
            let result = await Command.asyncRun("/usr/bin/pmset", ["-g"])
            self.globalSleepDisabled = PowerSettings.sleepDisabled(result.output)
            if result.status == 0 && self.globalSleepDisabled == false { self.notice = L("Your Mac is allowed to sleep again.") }
            else { self.error = L("Couldn't confirm sleep is allowed again. Refresh and check.") }
        }
    }

    private func authorize(_ command: String, verified: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        notice = L("Confirm in the macOS password prompt…")
        Task {
            defer { busy = false; onStatusChange?() }
            let result = await Command.asyncRun("/usr/bin/osascript", ["-e", "do shell script \"\(command)\" with administrator privileges"])
            if result.status == 0 { await verified() }
            else if result.output.contains("-128") { notice = L("Cancelled. System settings weren't changed.") }
            else { notice = nil; error = String(format: L("macOS couldn't apply the setting: %@"), result.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }

    func displayOff() {
        if active && mode == .display { setMode(.system) }
        guard mode != .display || !active else { return }
        closePanel?()
        Task {
            let result = await Command.asyncRun("/usr/bin/pmset", ["displaysleepnow"])
            if result.status != 0 { error = String(format: L("Couldn't turn off the display: %@"), result.output) }
        }
    }

    func sleepNow() {
        closePanel?()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Put your Mac to sleep now?")
        alert.informativeText = L("Downloads, builds and remote connections may pause. RestBar releases its own keep-awake request first.")
        alert.addButton(withTitle: L("Sleep Now"))
        alert.addButton(withTitle: L("Cancel"))
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        stop()
        Task {
            let result = await Command.asyncRun("/usr/bin/pmset", ["sleepnow"])
            if result.status != 0 { error = String(format: L("Couldn't put your Mac to sleep: %@"), result.output) }
        }
    }

    func refreshLogin() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    /// Starting at login is the default, once. After that it's whatever the person
    /// last chose, including off, so a reinstall never turns it back on.
    func applyLoginDefault() {
        let defaults = UserDefaults.standard
        guard LoginDefault.shouldEnable(
            decided: defaults.bool(forKey: "loginDecided"),
            bundlePath: Bundle.main.bundlePath,
            home: NSHomeDirectory()
        ) else { return }
        setLogin(true, askingForApproval: false)
    }

    func setLogin(_ enabled: Bool, askingForApproval: Bool = true) {
        UserDefaults.standard.set(true, forKey: "loginDecided")
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLogin()
            if loginNeedsApproval && askingForApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            self.error = String(format: L("Couldn't update start at login: %@"), error.localizedDescription)
            refreshLogin()
        }
    }

    func cleanup() {
        stop()
        refreshTimer?.invalidate()
        agentTimer?.invalidate()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        powerSource = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
