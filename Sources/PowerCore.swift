import Foundation
import IOKit.pwr_mgt
import IOKit.ps

/// Every word a person reads goes through here, keyed by its English text. The
/// translations are in Resources/, and macOS picks the language from System Settings.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

enum AwakeMode: String, CaseIterable, Identifiable {
    case system, display
    var id: String { rawValue }
    var title: String { self == .system ? L("Let display sleep") : L("Keep display on") }
    var assertionType: String {
        self == .system ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
    }
}

enum PowerProfile: String, CaseIterable, Identifiable {
    case battery, adapter
    var id: String { rawValue }
    var argument: String { self == .battery ? "-b" : "-c" }
    var section: String { self == .battery ? "Battery Power" : "AC Power" }
}

struct BatterySnapshot {
    var percent: Int?
    var onAC = true
    var charging = false
    var charged = false
    var minutesRemaining: Int?
    var hasBattery = false
    var sourceKnown = false

    static func read() -> BatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return .init() }
        var result = BatterySnapshot()
        if let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            result.onAC = (source as String) == kIOPSACPowerValue
            result.sourceKnown = true
        }
        guard let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return result }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  d[kIOPSIsPresentKey] as? Bool != false else { continue }
            result.hasBattery = true
            if let current = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 {
                result.percent = min(100, Swift.max(0, Int((Double(current) / Double(max) * 100).rounded())))
            }
            result.charging = d[kIOPSIsChargingKey] as? Bool ?? false
            result.charged = d[kIOPSIsChargedKey] as? Bool ?? false
            let minutes = d[result.charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
            result.minutesRemaining = minutes.flatMap { $0 > 0 ? $0 : nil }
            break
        }
        return result
    }

    var description: String {
        guard sourceKnown else { return L("Power status unavailable") }
        if !hasBattery { return onAC ? L("Plugged in") : L("External backup power") }
        if charging { return L("Plugged in · Charging") }
        if charged { return L("Plugged in · Fully charged") }
        return onAC ? L("Plugged in · Not charging") : L("On battery power")
    }

    /// Only when macOS actually gave an estimate.
    var estimate: String? {
        guard let minutes = minutesRemaining, !(onAC && !charging) else { return nil }
        let duration = minutes >= 60
            ? String(format: L("%d hr %d min"), minutes / 60, minutes % 60)
            : String(format: L("%d min"), minutes)
        return String(format: charging ? L("%@ until full") : L("%@ remaining"), duration)
    }
}

struct PowerSettings {
    var profiles: [String: [String: Int]] = [:]
    init(_ output: String) {
        var section: String?
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix(":") {
                section = String(line.dropLast())
                profiles[section!] = [:]
            } else if let section {
                let fields = line.split(whereSeparator: { $0.isWhitespace })
                if fields.count == 2, let value = Int(fields[1]) { profiles[section]?[String(fields[0])] = value }
            }
        }
    }
    /// Macs that offer High Power Mode report `powermode` (0 automatic, 1 low, 2 high)
    /// instead of `lowpowermode`.
    func lowPower(_ profile: PowerProfile) -> Bool? {
        let section = profiles[profile.section]
        if let value = section?["lowpowermode"] { return value != 0 }
        if let value = section?["powermode"] { return value == 1 }
        return nil
    }
    func lowPowerKey(_ profile: PowerProfile) -> String {
        profiles[profile.section]?["lowpowermode"] != nil ? "lowpowermode" : "powermode"
    }
    static func sleepDisabled(_ output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            if fields.count == 2 && fields[0] == "SleepDisabled", let value = Int(fields[1]) { return value != 0 }
        }
        return nil
    }
}

struct SleepBlocker: Identifiable {
    let id: String
    let process: String
    let reason: String
    static func parse(_ output: String) -> [SleepBlocker] {
        output.split(separator: "\n").compactMap { raw in
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("pid "),
                  ["PreventUserIdleSystemSleep", "NoIdleSleepAssertion", "PreventUserIdleDisplaySleep", "PreventSystemSleep"].contains(where: line.contains),
                  let start = line.firstIndex(of: "("), let end = line.range(of: "): [", range: start..<line.endIndex)?.lowerBound,
                  let named = line.range(of: "named: \"") else { return nil }
            let reason = String(line[named.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            return SleepBlocker(id: line, process: String(line[line.index(after: start)..<end]), reason: reason)
        }
    }
}

enum AwakePolicy {
    static func stopReason(battery: BatterySnapshot, lowBattery: Bool, onlyAC: Bool, deadline: Date?, now: Date) -> String? {
        if let deadline, now >= deadline { return L("Time is up. Your Mac can sleep again.") }
        if onlyAC && (!battery.sourceKnown || !battery.onAC) { return L("Not plugged in, so keep-awake stopped.") }
        if lowBattery && battery.hasBattery && !battery.charging && (battery.percent.map { $0 <= 20 } ?? false) {
            return L("Battery at 20% or below, so keep-awake stopped.")
        }
        return nil
    }
}

final class PowerAssertion {
    private(set) var id: IOPMAssertionID?
    func start(mode: AwakeMode, seconds: TimeInterval = 0, name: String = "RestBar keep-awake") throws {
        var next: IOPMAssertionID = 0
        let code = IOPMAssertionCreateWithDescription(mode.assertionType as CFString, name as CFString,
            "User-requested temporary keep-awake session" as CFString, nil, nil,
            seconds, kIOPMAssertionTimeoutActionRelease as CFString, &next)
        guard code == kIOReturnSuccess else {
            throw NSError(domain: "RestBar", code: Int(code), userInfo: [NSLocalizedDescriptionKey: String(format: L("Couldn't start keep-awake (%d)."), code)])
        }
        stop()
        id = next
    }
    func stop() {
        if let id { IOPMAssertionRelease(id) }
        id = nil
    }
    deinit { stop() }
}

enum LoginDefault {
    /// RestBar starts at login unless the person turned that off. It only sets this up
    /// from an Applications folder, so a copy run from a build folder or a download
    /// doesn't leave a login item pointing at somewhere temporary.
    static func shouldEnable(decided: Bool, bundlePath: String, home: String) -> Bool {
        !decided && (bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix("\(home)/Applications/"))
    }
}

struct CommandResult {
    let status: Int32
    let output: String
}

enum Command {
    // Only fixed executables and validated, internally generated arguments are used.
    static func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return .init(status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
        } catch { return .init(status: -1, output: error.localizedDescription) }
    }
    static func asyncRun(_ executable: String, _ arguments: [String]) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: run(executable, arguments)) }
        }
    }
}
