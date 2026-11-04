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
check(BatterySnapshot(percent: 85, onAC: true, charging: false, hasBattery: true, sourceKnown: true).description.contains("Not charging"), "Plugged in does not imply charging")
check(BatterySnapshot().description == "Power status unavailable", "Missing source is explicitly unavailable")
check(BatterySnapshot(onAC: true, charging: false, minutesRemaining: 90).estimate == nil, "No estimate while plugged in and not charging")
check(BatterySnapshot(onAC: false, charging: false, minutesRemaining: 90).estimate == "1 hr 30 min remaining", "Estimate formats hours and minutes")

let home = "/Users/someone"
check(LoginDefault.shouldEnable(decided: false, bundlePath: "/Applications/RestBar.app", home: home), "First launch from Applications starts at login")
check(LoginDefault.shouldEnable(decided: false, bundlePath: "\(home)/Applications/RestBar.app", home: home), "First launch from personal Applications starts at login")
check(!LoginDefault.shouldEnable(decided: true, bundlePath: "/Applications/RestBar.app", home: home), "A person's choice is never overridden")
check(!LoginDefault.shouldEnable(decided: false, bundlePath: "\(home)/RestBar/dist/RestBar.app", home: home), "A build folder never becomes a login item")
check(!LoginDefault.shouldEnable(decided: false, bundlePath: "/private/var/folders/x/AppTranslocation/y/RestBar.app", home: home), "A translocated download never becomes a login item")

let ps = """
  100     1   0.2 /Users/x/Library/Application Support/Claude/claude-code/2.1/claude.app/Contents/MacOS/claude
  101   100  12.0 /bin/zsh
  102   101  30.0 /usr/bin/swiftc
  200     1   0.0 /Applications/Claude.app/Contents/MacOS/Claude
  300     1   0.1 /opt/homebrew/bin/codex
  400     1   0.0 /usr/local/bin/node
  401     1   5.0 /usr/local/bin/node
  402     1   5.0 /usr/local/bin/node
  403     1   0.0 /usr/bin/python3
  500     1   9.0 /usr/bin/grep
"""
let processes = AgentDetector.parseProcesses(ps)
check(processes.count == 10 && processes[0].name == "claude", "Process paths with spaces parse")
let commands = AgentDetector.parseCommands("""
  400 node /usr/local/lib/node_modules/@openai/codex/bin/codex.js
  401 node /Users/x/claude/server.js
  402 node --no-warnings /usr/local/bin/gemini
  403 /usr/bin/python3 /opt/homebrew/bin/aider --yes
""")
let found = AgentDetector.agents(in: processes, commands: commands)
check(found.map(\.pid) == [100, 300, 400, 402, 403], "Agents are found by program, not by a mention in a path")
check(found[0].name == "Claude Code" && found[0].cpu == 42.2, "An agent's CPU includes everything it started")
check(found.map(\.name) == ["Claude Code", "Codex", "Codex", "Gemini CLI", "Aider"], "Agents get their display names")
check(!found.contains { $0.pid == 200 }, "A desktop app of the same name is not an agent")

var agentWatch = AgentWatch()
let t0 = Date(timeIntervalSince1970: 1000)
func agent(_ cpu: Double, _ name: String = "Claude Code") -> [AgentDetector.Agent] { [.init(name: name, pid: 1, cpu: cpu)] }
check(agentWatch.update(agent(0.5), now: t0).isEmpty, "An idle open session doesn't hold the Mac awake")
check(agentWatch.update(agent(30), now: t0) == ["Claude Code"], "A busy agent counts as working")
check(agentWatch.update(agent(0), now: t0 + 540) == ["Claude Code"], "Waiting on its model for nine minutes still counts")
check(agentWatch.update(agent(0), now: t0 + 601).isEmpty, "Ten quiet minutes counts as finished")
_ = agentWatch.update(agent(30), now: t0 + 700)
check(agentWatch.update([], now: t0 + 710).isEmpty, "An agent that exited is finished at once")

check(LidHold.sudoersRule(user: "brad") == "brad ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1", "The permission allows only these two commands")
check(LidHold.sudoersRule(user: "a b") == nil && LidHold.sudoersRule(user: "x'; rm -rf /") == nil && LidHold.sudoersRule(user: "") == nil, "A strange account name can't reach a root command")
check(!LidHold.installCommand(rule: "r").contains("\""), "The root command survives being quoted into AppleScript")
let ruleFile = NSTemporaryDirectory() + "restbar-rule-\(UUID().uuidString)"
try (LidHold.sudoersRule(user: "brad")! + "\n").write(toFile: ruleFile, atomically: true, encoding: .utf8)
check(Command.run("/usr/sbin/visudo", ["-cf", ruleFile]).status == 0, "visudo accepts the permission")
try? FileManager.default.removeItem(atPath: ruleFile)
let hot = BatterySnapshot(percent: 90, onAC: true, charging: true, hasBattery: true, sourceKnown: true)
let low = BatterySnapshot(percent: 20, onAC: false, charging: false, hasBattery: true, sourceKnown: true)
check(LidHold.stopReason(battery: hot, thermal: .nominal) == nil, "A cool, charged Mac may stay on with the lid closed")
check(LidHold.stopReason(battery: hot, thermal: .serious) != nil && LidHold.stopReason(battery: hot, thermal: .critical) != nil, "A hot Mac stops")
check(LidHold.stopReason(battery: low, thermal: .nominal) != nil, "20% battery stops whatever the other options say")
check(LidHold.needsRestore(owned: true, holding: false) && !LidHold.needsRestore(owned: true, holding: true) && !LidHold.needsRestore(owned: false, holding: false), "Only a setting RestBar left on gets restored")

func matches(_ pattern: String, in text: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: pattern)
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
        let range = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        return String(text[Range(range, in: text)!])
    }
}
let languages = ["en", "zh-Hans", "zh-Hant"]
let tables = languages.map { NSDictionary(contentsOfFile: "Resources/\($0).lproj/Localizable.strings") as? [String: String] ?? [:] }
let english = tables[0]
check(!english.isEmpty && tables.allSatisfy { Set($0.keys) == Set(english.keys) }, "Every language has exactly the same strings")
check(tables.allSatisfy { table in
    table.allSatisfy { Set(matches("%[d@]", in: $0.key)).sorted() == Set(matches("%[d@]", in: $0.value)).sorted() }
}, "Translations keep their placeholders")
let source = try FileManager.default.contentsOfDirectory(atPath: "Sources").filter { $0.hasSuffix(".swift") }
    .map { try String(contentsOfFile: "Sources/\($0)", encoding: .utf8) }.joined(separator: "\n")
check(matches("\\p{Han}", in: source).isEmpty, "No translated text is left in the source")
let used = Set(matches("\\bL\\(\"([^\"]+)\"\\)", in: source).map { $0.replacingOccurrences(of: "\\n", with: "\n") })
check(!used.isEmpty && used == Set(english.keys), "Every string used has a translation, and none is left unused")
check(matches("\\b(?:Text|Toggle|Button|Picker)\\(\"|\\.help\\(\"|[tT]itle: \"|(?:messageText|informativeText) = \"", in: source).filter { $0 != "Text(\"" }.isEmpty
      && matches("Text\\(\"([^\"]+)\"\\)", in: source).allSatisfy { $0 == "RestBar" }, "No interface text bypasses translation")

check(PowerSettings.sleepDisabled("System-wide power settings:\nCurrently in use:\n sleep 10") == false, "An absent line means sleep is allowed")

let modern = PowerSettings("Battery Power:\n powermode 1\nAC Power:\n powermode 2\n")
check(modern.lowPower(.battery) == true, "powermode 1 reads as Low Power on");
check(modern.lowPower(.adapter) == false, "powermode 2 (High Power) is not Low Power");
check(modern.lowPowerKey(.battery) == "powermode", "A powermode Mac is written with powermode");
check(settings.lowPowerKey(.battery) == "lowpowermode", "A lowpowermode Mac keeps its own key");

let resting = MoonMark.dots(columns: 11, phase: .resting)
check(resting.allSatisfy { dot in
    let dx = dot.x - MoonMark.cut.x, dy = dot.y - MoonMark.cut.y
    return dx * dx + dy * dy > MoonMark.cut.radius * MoonMark.cut.radius
}, "Crescent dots stay outside the cut")
let logoDot = MoonMark.logoDot(columns: 11)
check(!resting.contains { $0.x == logoDot.x && $0.y == logoDot.y }, "Moon's red dot sits in the crescent's mouth")
check(MoonMark.dots(columns: 11, phase: .awake).count > resting.count, "Awake mark is the fuller disc")

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
    // The watchdog: when the process it watches dies, however it dies, it runs the restore.
    let marker = NSTemporaryDirectory() + "restbar-watchdog-\(UUID().uuidString)"
    let watched = Process()
    watched.executableURL = URL(fileURLWithPath: "/bin/sleep")
    watched.arguments = ["30"]
    try watched.run()
    let watchdog = Process()
    watchdog.executableURL = URL(fileURLWithPath: "/bin/sh")
    watchdog.arguments = ["-c", LidHold.watchdogScript(restore: "/usr/bin/touch \(marker)", every: 1), "restbar-watchdog", String(watched.processIdentifier)]
    try watchdog.run()
    Thread.sleep(forTimeInterval: 1.5)
    check(!FileManager.default.fileExists(atPath: marker), "The watchdog waits while the app is alive")
    kill(watched.processIdentifier, SIGKILL)
    watched.waitUntilExit()
    Thread.sleep(forTimeInterval: 2.5)
    check(FileManager.default.fileExists(atPath: marker), "The watchdog restores after a force quit")
    try? FileManager.default.removeItem(atPath: marker)
    let liveBattery = BatterySnapshot.read()
    print("Agents running here: \(AgentDetector.sample().count)")
    check(liveBattery.sourceKnown, "Native power-source API available")
    print("Live battery: \(liveBattery.percent.map(String.init) ?? "n/a")%; \(liveBattery.description)")
}

print("\(passed) checks passed.")
