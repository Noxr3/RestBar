import Foundation
import IOKit.pwr_mgt
import IOKit.ps

enum AwakeMode: String, CaseIterable, Identifiable {
    case system = "允许屏幕熄灭", display = "屏幕也常亮"
    var id: String { rawValue }
    var assertionType: String {
        self == .system ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
    }
}

enum PowerProfile: String, CaseIterable, Identifiable {
    case battery = "使用电池", adapter = "接通电源"
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
        guard sourceKnown else { return "电源状态暂不可用" }
        if !hasBattery { return onAC ? "接通电源" : "外部备用电源" }
        if charging { return "接通电源 · 正在充电" }
        if charged { return "接通电源 · 已充满" }
        return onAC ? "接通电源 · 未在充电" : "正在使用电池"
    }

    var estimate: String {
        guard let minutes = minutesRemaining else { return "续航时间由 macOS 估算" }
        if onAC && !charging { return "充电由 macOS 或其他电池工具管理" }
        let duration = minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
        return charging ? "预计 \(duration)充满" : "预计还可使用 \(duration)"
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
    func lowPower(_ profile: PowerProfile) -> Bool? {
        guard let value = profiles[profile.section]?["lowpowermode"] else { return nil }
        return value != 0
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
        if let deadline, now >= deadline { return "定时结束，已允许自动休眠" }
        if onlyAC && (!battery.sourceKnown || !battery.onAC) { return "未接通电源，已停止保持唤醒" }
        if lowBattery && battery.hasBattery && !battery.charging && (battery.percent.map { $0 <= 20 } ?? false) {
            return "电量不高于 20%，已停止保持唤醒"
        }
        return nil
    }
}

final class PowerAssertion {
    private(set) var id: IOPMAssertionID?
    func start(mode: AwakeMode, seconds: TimeInterval = 0, name: String = "RestBar · 保持唤醒") throws {
        var next: IOPMAssertionID = 0
        let code = IOPMAssertionCreateWithDescription(mode.assertionType as CFString, name as CFString,
            "User-requested temporary keep-awake session" as CFString, nil, nil,
            seconds, kIOPMAssertionTimeoutActionRelease as CFString, &next)
        guard code == kIOReturnSuccess else {
            throw NSError(domain: "RestBar", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "无法建立防休眠请求（\(code)）"])
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
