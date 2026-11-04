import Foundation
import IOKit.pwr_mgt

var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fputs("FAIL: \(label)\n", stderr); exit(1) }
    passed += 1
    print("PASS: \(label)")
}

if CommandLine.arguments.contains("--assertion-child") {
    let assertion = PowerAssertion()
    try assertion.start(mode: .system, name: "RestBar-exit-test")
    print("READY")
    fflush(stdout)
    Thread.sleep(forTimeInterval: 15)
    exit(0)
}

let settings = PowerSettings("""
Battery Power:
 sleep 15
 lowpowermode 1
AC Power:
 lowpowermode 0
 displaysleep 10
 sleep 30
""")
check(settings.lowPower(.battery) == true, "Battery low power parsed independently")
check(settings.lowPower(.adapter) == false, "AC low power parsed independently")
check(settings.profiles["AC Power"]?["sleep"] == 30, "Idle timer parsed")
check(PowerSettings("AC Power:\n sleep 30").lowPower(.adapter) == nil, "Unsupported mode stays unknown")
check(PowerSettings("").lowPower(.battery) == nil, "Failed read never becomes off")
check(PowerSettings.sleepDisabled("System-wide power settings:\n SleepDisabled\t\t1") == true, "Global disabled detected")
check(PowerSettings.sleepDisabled("System-wide power settings:\n SleepDisabled\t\t0") == false, "Global allowed detected")
check(PowerSettings.sleepDisabled("error") == nil, "Global read failure stays unknown")

let blockers = SleepBlocker.parse("""
 PreventUserIdleSystemSleep 1
 pid 123(RestBar): [0x001] 00:00:01 PreventUserIdleSystemSleep named: "RestBar · 保持唤醒"
 pid 456(An App (Helper)): [0x002] 00:00:01 NoIdleSleepAssertion named: "Electron"
 pid 789(WindowServer): [0x003] 00:00:01 UserIsActive named: "Keyboard"
 pid 987(powerd): [0x004] 00:00:01 InternalPreventDisplaySleep named: "delayDisplayOff"
""")
check(blockers.count == 2, "Only relevant app blockers included")
check(blockers[0].reason == "RestBar · 保持唤醒", "Unicode reason preserved")
check(blockers[1].process == "An App (Helper)", "Nested process parentheses preserved")
check(SleepBlocker.parse("No kernel assertions.").isEmpty, "Empty blocker list")

let now = Date()
var battery = BatterySnapshot(percent: 85, onAC: true, charging: false, hasBattery: true, sourceKnown: true)
func reason(_ low: Bool = true, _ onlyAC: Bool = false, _ deadline: Date? = nil) -> String? {
    AwakePolicy.stopReason(battery: battery, lowBattery: low, onlyAC: onlyAC, deadline: deadline, now: now)
}
check(reason() == nil, "Healthy battery permits awake")
check(reason(true, false, now) != nil, "Deadline inclusive expiry")
check(reason(true, false, now.addingTimeInterval(1)) == nil, "Future deadline permits awake")
battery.onAC = false
check(reason(true, true) != nil, "Unplugging stops AC-only session")
check(reason(true, false) == nil, "Battery use allowed when opted in")
battery.percent = 20
check(reason() != nil, "20 percent threshold stops awake")
battery.percent = 21
check(reason() == nil, "21 percent permits awake")
battery.percent = 5
check(reason(false) == nil, "Disabled battery guard respected")
battery.onAC = true
check(reason() != nil, "Plugged-in but discharging low battery stays protected")
battery.charging = true
check(reason() == nil, "Charging low battery permits awake")
battery.sourceKnown = false
check(reason(true, true) != nil, "Unknown source cannot bypass AC-only guard")
battery.percent = nil
battery.sourceKnown = true
check(reason() == nil, "Missing percentage is not treated as zero")
check(BatterySnapshot(percent: 85, onAC: true, charging: false, hasBattery: true, sourceKnown: true).description.contains("未在充电"), "Plugged in does not imply charging")
check(BatterySnapshot().description == "电源状态暂不可用", "Missing source is explicitly unavailable")

let modern = PowerSettings("Battery Power:\n powermode 1\nAC Power:\n powermode 2\n")
check(modern.lowPower(.battery) == true, "powermode 1 reads as Low Power on");
check(modern.lowPower(.adapter) == false, "powermode 2 (High Power) is not Low Power");
check(modern.lowPowerKey(.battery) == "powermode", "A powermode Mac is written with powermode");
check(settings.lowPowerKey(.battery) == "lowpowermode", "A lowpowermode Mac keeps its own key");

let resting = MoonMark.dots(columns: 15, phase: .resting)
check(resting.filter(\.isSignal).count == 1, "Resting mark has exactly one red dot")
check(resting.filter { !$0.isSignal }.allSatisfy { dot in
    let dx = dot.x - MoonMark.cut.x, dy = dot.y - MoonMark.cut.y
    return dx * dx + dy * dy > MoonMark.cut.radius * MoonMark.cut.radius
}, "Crescent dots stay outside the cut")
let awakeDots = MoonMark.dots(columns: 15, phase: .awake)
check(!awakeDots.contains(where: \.isSignal) && awakeDots.count > resting.count, "Awake mark is the fuller disc, in one colour")

if CommandLine.arguments.contains("--integration") {
    let assertion = PowerAssertion()
    let name = "RestBar-integration-\(UUID().uuidString)"
    try assertion.start(mode: .system, name: name)
    check(Command.run("/usr/bin/pmset", ["-g", "assertions"]).output.contains(name), "System observes live idle-sleep assertion")
    assertion.stop()
    check(!Command.run("/usr/bin/pmset", ["-g", "assertions"]).output.contains(name), "Explicit stop releases native assertion")
    try assertion.start(mode: .system, seconds: 1, name: name)
    Thread.sleep(forTimeInterval: 2)
    check(!Command.run("/usr/bin/pmset", ["-g", "assertions"]).output.contains(name), "OS releases timed assertion without app timer")
    assertion.stop()
    try assertion.start(mode: .display, name: name)
    let displayOutput = Command.run("/usr/bin/pmset", ["-g", "assertions"]).output
    check(displayOutput.split(separator: "\n").contains { $0.contains(name) && $0.contains("PreventUserIdleDisplaySleep") }, "Display mode creates correct assertion type")
    try assertion.start(mode: .system, name: name)
    let switched = Command.run("/usr/bin/pmset", ["-g", "assertions"]).output.split(separator: "\n").filter { $0.contains(name) }
    check(switched.count == 1 && switched[0].contains("PreventUserIdleSystemSleep"), "Switching modes leaves only one assertion")
    assertion.stop()

    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = ["--assertion-child"]
    let pipe = Pipe()
    child.standardOutput = pipe
    try child.run()
    _ = pipe.fileHandleForReading.availableData
    check(Command.run("/usr/bin/pmset", ["-g", "assertions"]).output.contains("RestBar-exit-test"), "Child process assertion active")
    child.terminate()
    child.waitUntilExit()
    check(!Command.run("/usr/bin/pmset", ["-g", "assertions"]).output.contains("RestBar-exit-test"), "Process exit releases its native assertion")
    let liveBattery = BatterySnapshot.read()
    check(liveBattery.sourceKnown, "Native power-source API available")
    print("Live battery: \(liveBattery.percent.map(String.init) ?? "n/a")%; \(liveBattery.description)")
}

print("\(passed) checks passed.")
