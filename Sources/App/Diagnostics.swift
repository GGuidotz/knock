// Diagnostica: un registro breve di ciò che succede (motore, calibrazione, aggiornamenti) e un report in testo semplice
// da allegare a una segnalazione. Solo in memoria, mai dati personali e mai suono: solo stati e conteggi.

import AppKit
import Foundation

enum DiagCategory: String {
    case app, engine, update, feedback
}

@MainActor
final class DiagnosticsLog: ObservableObject {
    static let shared = DiagnosticsLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let category: DiagCategory
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    func add(_ category: DiagCategory, _ message: String) {
        entries.append(Entry(date: Date(), category: category, message: message))
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
    }

    nonisolated static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}

@MainActor
func diag(_ category: DiagCategory, _ message: String) {
    DiagnosticsLog.shared.add(category, message)
}

enum SystemInfo {
    /// "Mac14,2"
    static var model: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static var macOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    static var version: String { info["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { info["CFBundleVersion"] as? String ?? "?" }
    static var commit: String { info["KnockGitCommit"] as? String ?? "?" }

    /// "Knock 0.1.0 (12) · macOS 27.0.1 · Mac14,2 · it"
    static var oneLine: String {
        "Knock \(version) (\(build)) · macOS \(macOS) · \(model) · \(Localization.effectiveCode)"
    }

    /// CPU (percento di un core) e memoria di questa app.
    @MainActor
    static var ownUsage: (cpu: Double, memory: UInt64)? {
        var info = rusage_info_current()
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0) == 0
            }
        }
        guard ok else { return nil }
        return (CPUSampler.shared.percent(cpuTicks:info.ri_user_time + info.ri_system_time), info.ri_phys_footprint)
    }
}

/// Percentuale di CPU tra una lettura e l'altra.
@MainActor
final class CPUSampler {
    static let shared = CPUSampler()
    private var last: (time: Date, cpu: UInt64)?

    private var value = 0.0

    /// `cpuTicks` in unità di mach_absolute_time (così le dà proc_pid_rusage su Apple Silicon).
    func percent(cpuTicks: UInt64) -> Double {
        let now = Date()
        if let last, now.timeIntervalSince(last.time) > 0.5 {
            value = max(0, MotionSensor.hostSeconds(cpuTicks &- last.cpu) / now.timeIntervalSince(last.time) * 100)
        }
        if last == nil || now.timeIntervalSince(last!.time) > 0.5 { last = (now, cpuTicks) }
        return value
    }
}

enum DiagnosticsReport {
    @MainActor
    static func make(model: AppModel) -> String {
        var out: [String] = []
        func section(_ title: String) { out.append(""); out.append("## \(title)") }
        func row(_ key: String, _ value: String) { out.append("- \(key): \(value)") }
        func yesNo(_ b: Bool) -> String { b ? "yes" : "no" }
        let prefs = model.prefs

        out.append("# Knock diagnostics")
        row("Generated", DiagnosticsLog.stamp(Date()))
        section("App")
        row("Version", "\(SystemInfo.version) (build \(SystemInfo.build), commit \(SystemInfo.commit))")
        row("Installed via", Updater.channel == .homebrew ? "Homebrew" : "source build")
        row("Language", "\(prefs.language.rawValue) → \(Localization.effectiveCode)")
        section("Mac")
        row("Model", SystemInfo.model)
        row("macOS", SystemInfo.macOS)
        row("Motion sensor", yesNo(MotionSensor.isAvailable))
        section("Engine")
        row("State", "\(model.engineState)")
        row("Microphone permission", "\(model.micPermission.rawValue)")
        row("Input", model.engine.inputDescription)
        row("Motion running", yesNo(model.engine.motion.isRunning))
        row("Listening", yesNo(prefs.listening))
        row("Sensitivity", String(format: "%.2f", prefs.sensitivity))
        row("Ignore while typing", yesNo(prefs.ignoreWhileTyping))
        if let c = model.classifier {
            row("Calibration", "\(c.samples.count) samples, accuracy \(Int(c.accuracy * 100))%, motion \(yesNo(c.usesMotion))")
        } else {
            row("Calibration", "none")
        }
        row("Events this session", "\(model.events.count) (last 30 kept)")
        if let own = SystemInfo.ownUsage {
            row("This app now", String(format: "%.1f%% CPU, %d MB", own.cpu, Int(own.memory / 1_048_576)))
        }
        section("Updates")
        row("State", "\(model.updater.state)")
        row("Last check", model.updater.lastCheck.map(DiagnosticsLog.stamp) ?? "never")
        section("Log")
        let entries = DiagnosticsLog.shared.entries.suffix(60)
        if entries.isEmpty { out.append("(empty)") }
        for e in entries { out.append("\(DiagnosticsLog.stamp(e.date)) [\(e.category.rawValue)] \(e.message)") }
        return out.joined(separator: "\n") + "\n"
    }

    static var suggestedFileName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "Knock-diagnostics-\(f.string(from: Date())).txt"
    }
}
