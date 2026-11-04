import Foundation

/// Decides whether a coding agent is working on this Mac, from the process list.
/// Reads only process names, the script an interpreter runs, and CPU use, and keeps
/// none of it. Pure, apart from `sample()`, so the rules can be tested.
enum AgentDetector {
    struct Process: Equatable {
        let pid: Int
        let parent: Int
        let cpu: Double
        let name: String
    }
    struct Agent: Equatable {
        let name: String
        let pid: Int
        /// CPU use of the agent and everything it started.
        let cpu: Double
    }

    static let binaries = [
        "aider": "Aider",
        "amp": "Amp",
        "claude": "Claude Code",
        "cline": "Cline",
        "codex": "Codex",
        "crush": "Crush",
        "cursor-agent": "Cursor",
        "droid": "Droid",
        "gemini": "Gemini CLI",
        "goose": "Goose",
        "opencode": "OpenCode",
        "qwen": "Qwen Code",
    ]
    private static let packages = [
        "@anthropic-ai/claude-code": "Claude Code",
        "@google/gemini-cli": "Gemini CLI",
        "@openai/codex": "Codex",
        "@qwen-code/qwen-code": "Qwen Code",
    ]
    private static let interpreters: Set<String> = ["bun", "deno", "node", "python", "python3"]

    /// Output of `ps -axo pid=,ppid=,pcpu=,comm=`. The name may contain spaces.
    static func parseProcesses(_ output: String) -> [Process] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 4, let pid = Int(fields[0]), let parent = Int(fields[1]),
                  let cpu = Double(fields[2].replacingOccurrences(of: ",", with: ".")) else { return nil }
            return Process(pid: pid, parent: parent, cpu: cpu, name: baseName(String(fields[3])))
        }
    }

    /// Output of `ps -o pid=,command= -p <pids>`, for interpreters only.
    static func parseCommands(_ output: String) -> [Int: String] {
        var result: [Int: String] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            if fields.count == 2, let pid = Int(fields[0]) { result[pid] = String(fields[1]) }
        }
        return result
    }

    static func needsCommand(_ process: Process) -> Bool {
        let name = process.name.lowercased()
        return interpreters.contains(name) || name.hasPrefix("python3.")
    }

    /// Only the program itself counts. A path or argument that merely mentions an
    /// agent, such as a folder called claude or `grep codex`, does not.
    private static func agentName(_ process: Process, command: String?) -> String? {
        // Exact case on purpose: the desktop app is "Claude", the command-line agent "claude".
        if let name = binaries[process.name] { return name }
        guard needsCommand(process), let command else { return nil }
        let words = command.split(separator: " ").prefix(4).map(String.init)
        for word in words.dropFirst() {
            if word.hasPrefix("-") { continue }
            if let match = packages.first(where: { word.contains($0.key) }) { return match.value }
            return binaries[baseName(word)]
        }
        return nil
    }

    static func agents(in processes: [Process], commands: [Int: String]) -> [Agent] {
        var children: [Int: [Process]] = [:]
        for process in processes { children[process.parent, default: []].append(process) }
        func total(_ process: Process, depth: Int) -> Double {
            guard depth < 32 else { return process.cpu }
            return process.cpu + (children[process.pid] ?? []).reduce(0) { $0 + total($1, depth: depth + 1) }
        }
        return processes.compactMap { process in
            agentName(process, command: commands[process.pid]).map {
                Agent(name: $0, pid: process.pid, cpu: total(process, depth: 0))
            }
        }
    }

    static func sample() -> [Agent] {
        let list = Command.run("/bin/ps", ["-axo", "pid=,ppid=,pcpu=,comm="])
        guard list.status == 0 else { return [] }
        let processes = parseProcesses(list.output)
        let interpreted = processes.filter(needsCommand).map { String($0.pid) }
        var commands: [Int: String] = [:]
        if !interpreted.isEmpty {
            let result = Command.run("/bin/ps", ["-o", "pid=,command=", "-p", interpreted.joined(separator: ",")])
            commands = parseCommands(result.output)
        }
        return agents(in: processes, commands: commands)
    }

    private static func baseName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

/// Turns samples into "is an agent working". An agent waiting on its model uses almost
/// no CPU, so a quiet spell has to last a while before it counts as finished: letting a
/// Mac sleep in the middle of a run is the failure this app exists to prevent.
struct AgentWatch {
    /// Idle agents measured at or below 0.6% per process on a Mac with 19 sessions open.
    static let workingCPU = 2.0
    static let quietPeriod: TimeInterval = 10 * 60

    private var lastWorking: [String: Date] = [:]

    /// The agents that count as working now, by name.
    mutating func update(_ agents: [AgentDetector.Agent], now: Date) -> [String] {
        for agent in agents where agent.cpu >= Self.workingCPU { lastWorking[agent.name] = now }
        let running = Set(agents.map(\.name))
        lastWorking = lastWorking.filter { running.contains($0.key) && now.timeIntervalSince($0.value) < Self.quietPeriod }
        return lastWorking.keys.sorted()
    }
}

/// Keeping a Mac running with its lid closed takes `pmset disablesleep`, a system setting
/// that outlasts the app. So it has to be switched back without anyone there to type a
/// password, and even if RestBar crashes.
enum LidHold {
    static let rulePath = "/etc/sudoers.d/restbar"
    static let onArguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", "1"]
    static let offArguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]

    /// Allows exactly these two commands, for this one person, and nothing else.
    static func sudoersRule(user: String) -> String? {
        guard !user.isEmpty, user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { return nil }
        return "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
    }

    /// Run as root. sudo refuses every command if a rule file is malformed, so it is
    /// checked with visudo before it goes anywhere near /etc/sudoers.d.
    static func installCommand(rule: String) -> String {
        "t=$(/usr/bin/mktemp) && echo '\(rule)' > $t && /usr/sbin/visudo -cf $t && /usr/bin/install -m 0440 -o root -g wheel $t \(rulePath); s=$?; /bin/rm -f $t; exit $s"
    }
    static let removeCommand = "/bin/rm -f \(rulePath)"

    /// Waits for RestBar to exit, however that happens, and then runs `restore`. A
    /// clean stop ends this first, so it only ever acts after a crash or a force quit.
    static func watchdogScript(restore: String, every seconds: Int = 5) -> String {
        "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep \(seconds); done; \(restore)"
    }
    static let restoreCommand = "/usr/bin/sudo " + offArguments.joined(separator: " ")

    /// Closed in a bag is the danger, so these apply whatever the other options say.
    static func stopReason(battery: BatterySnapshot, thermal: ProcessInfo.ThermalState) -> String? {
        if thermal == .serious || thermal == .critical { return L("Your Mac is running hot, so keep-awake stopped.") }
        if battery.hasBattery && !battery.charging && (battery.percent.map { $0 <= 20 } ?? false) {
            return L("Battery at 20% or below, so keep-awake stopped.")
        }
        return nil
    }

    /// A previous run left the setting on and didn't get to restore it, as after a restart.
    static func needsRestore(owned: Bool, holding: Bool) -> Bool { owned && !holding }
}
