import Darwin
import Foundation
import os

struct TopAppEntry: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var iconPath: String?
    /// Mean energy-impact rate over the samples held for this app. Unitless. Lower is better.
    var impact: Double
}

enum TopAppList: Equatable, Sendable {
    case measuring
    case apps([TopAppEntry])
}

struct ProcessTick: Equatable, Sendable {
    var pid: Int32
    var group: String
    var name: String
    var iconPath: String?
    /// Energy impact over the sample window, already divided by elapsed seconds.
    var impact: Double
}

enum ProcessEnergyFilter {
    private static let spotlight: Set<String> = ["corespotlightd", "mds", "mds_stores"]
    /// CoreServices ships real apps the user recognizes. The rest (WindowManager,
    /// Control Center, Dock) are system shells packaged as `.app`.
    private static let keptCoreServices: Set<String> = ["Finder.app", "Spotlight.app"]

    /// `pm_sample` is the expensive call. Only app-owned processes and Spotlight can appear in the list.
    static func include(path: String, name: String) -> Bool {
        if spotlight.contains(name) { return true }
        guard path.contains(".app/") || path.hasSuffix(".app") else { return false }
        if isSystemShell(path) { return false }
        return true
    }

    private static func isSystemShell(_ path: String) -> Bool {
        let hidden = path.contains("/System/Library/CoreServices/")
            || path.contains("/System/Library/PrivateFrameworks/")
        guard hidden else { return false }
        guard let appName = appBundleName(path) else { return true }
        return !keptCoreServices.contains(appName)
    }

    private static func appBundleName(_ path: String) -> String? {
        let marker = ".app"
        guard let range = path.range(of: marker) else { return nil }
        let bundle = String(path[..<range.upperBound])
        return URL(fileURLWithPath: bundle).lastPathComponent
    }
}

enum TopAppsChartStyle: String, CaseIterable, Identifiable, Sendable {
    case list
    case bars
    case columns

    var id: String { rawValue }
    var localizationKey: String { "settings.topApps.chart.\(rawValue)" }
    static let fallback = TopAppsChartStyle.list

    static func resolved(stored raw: String?) -> TopAppsChartStyle {
        guard let raw, let style = TopAppsChartStyle(rawValue: raw) else { return fallback }
        return style
    }
}

enum TopAppsChartScale {
    /// Share of the tallest bar. The largest impact fills the track; zero stays empty.
    static func fractions(_ impacts: [Double]) -> [Double] {
        let peak = impacts.max() ?? 0
        guard peak > 0 else { return Array(repeating: 0, count: impacts.count) }
        return impacts.map { max($0, 0) / peak }
    }
}

enum ProcessGrouping {
    private static let names = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    /// Processes inside `Something.app` share that app. Anything else stays under its own name.
    static func identity(path: String, fallbackName: String) -> (group: String, name: String, iconPath: String?) {
        if let appPath = enclosingApp(path) {
            let name = displayName(appPath: appPath)
            return (appPath, name, appPath)
        }
        let name = fallbackName.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : fallbackName
        let group = name.isEmpty ? path : name
        return (group, group, nil)
    }

    private static func displayName(appPath: String) -> String {
        if let cached = names.withLock({ $0[appPath] }) { return cached }
        var resolved = FileManager.default.displayName(atPath: appPath)
        if resolved.hasSuffix(".app") { resolved = String(resolved.dropLast(4)) }
        if resolved.isEmpty {
            resolved = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
        }
        let name = resolved
        names.withLock { $0[appPath] = name }
        return name
    }

    private static func enclosingApp(_ path: String) -> String? {
        if let range = path.range(of: ".app/") {
            return String(path[..<range.upperBound].dropLast())
        }
        if path.hasSuffix(".app") {
            return path
        }
        return nil
    }
}

enum EnergyImpact {
    static func label(_ score: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), score)
    }
}

enum PowerSample {
    static let byteCount = 0x1c8
    /// CPU, wakeups, GPU, disk and network. Skips the cumulative nanojoule field so the
    /// component formula — the same one Activity Monitor shows — is used.
    static let flags: UInt64 = 0x1e
    private static let energyField = 0x170

    @_silgen_name("pm_sample_pid")
    private static func pm_sample_pid(_ pid: Int32, _ out: UnsafeMutableRawPointer, _ time: UInt64, _ flags: UInt64) -> Int32

    @_silgen_name("pm_task_subtract")
    private static func pm_task_subtract(
        _ later: UnsafeRawPointer,
        _ earlier: UnsafeRawPointer,
        _ delta: UnsafeMutableRawPointer,
        _ flag: UnsafeMutableRawPointer?
    )

    @_silgen_name("pm_energy_impact")
    private static func pm_energy_impact(_ sample: UnsafeRawPointer) -> Double

    static func take(pid: Int32) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let result = bytes.withUnsafeMutableBytes { buffer in
            pm_sample_pid(pid, buffer.baseAddress!, 0, flags)
        }
        return result == 0 ? bytes : nil
    }

    /// The library returns energy accumulated across the window. Divide by seconds to get the rate Activity Monitor shows.
    static func rate(previous: [UInt8], current: [UInt8], elapsed: Double) -> Double {
        guard previous.count == byteCount, current.count == byteCount else { return 0 }
        var delta = [UInt8](repeating: 0, count: byteCount)
        previous.withUnsafeBytes { before in
            current.withUnsafeBytes { after in
                delta.withUnsafeMutableBytes { out in
                    pm_task_subtract(after.baseAddress!, before.baseAddress!, out.baseAddress!, nil)
                }
            }
        }
        for offset in energyField..<(energyField + 8) {
            delta[offset] = 0
        }
        let seconds = max(elapsed, 0.05)
        let impact = delta.withUnsafeBytes { pm_energy_impact($0.baseAddress!) }
        guard impact.isFinite, impact > 0 else { return 0 }
        return impact / seconds
    }
}

struct AppEnergySample: Equatable, Sendable {
    var group: String
    var name: String
    var iconPath: String?
    /// Per-second energy impact for one sample interval, summed across the app's processes.
    var impact: Double
}

struct EnergyInterval: Equatable, Sendable {
    var apps: [AppEnergySample]
}

enum TopAppRanker {
    /// How long a sample stays in the average.
    static let defaultWindow: Duration = .seconds(180)
    /// Background sample period. The average uses however many of these have arrived.
    static let defaultSampleInterval: TimeInterval = 10

    static func collapse(_ ticks: [ProcessTick]) -> [AppEnergySample] {
        struct Bucket {
            var name: String
            var iconPath: String?
            var impact: Double
        }
        var buckets: [String: Bucket] = [:]
        for tick in ticks where tick.impact > 0 {
            var bucket = buckets[tick.group] ?? Bucket(name: tick.name, iconPath: tick.iconPath, impact: 0)
            bucket.impact += tick.impact
            bucket.name = tick.name
            if tick.iconPath != nil { bucket.iconPath = tick.iconPath }
            buckets[tick.group] = bucket
        }
        return buckets.map { group, bucket in
            AppEnergySample(group: group, name: bucket.name, iconPath: bucket.iconPath, impact: bucket.impact)
        }
    }

    /// Mean of the per-interval rates. An app missing from an interval counts as zero for that interval.
    static func rank(intervals: [EnergyInterval], limit: Int) -> [TopAppEntry] {
        guard !intervals.isEmpty else { return [] }
        let count = Double(intervals.count)
        struct Bucket {
            var name: String
            var iconPath: String?
            var total: Double
        }
        var buckets: [String: Bucket] = [:]
        for interval in intervals {
            for app in interval.apps where app.impact > 0 {
                var bucket = buckets[app.group] ?? Bucket(name: app.name, iconPath: app.iconPath, total: 0)
                bucket.total += app.impact
                bucket.name = app.name
                if app.iconPath != nil { bucket.iconPath = app.iconPath }
                buckets[app.group] = bucket
            }
        }
        return buckets
            .map { group, bucket in
                TopAppEntry(id: group, name: bucket.name, iconPath: bucket.iconPath, impact: bucket.total / count)
            }
            .filter { $0.impact > 0 }
            .sorted { lhs, rhs in
                if lhs.impact != rhs.impact { return lhs.impact > rhs.impact }
                return lhs.name < rhs.name
            }
            .prefix(limit)
            .map { $0 }
    }

    static func rank(current: [ProcessTick], limit: Int) -> [TopAppEntry] {
        rank(intervals: [EnergyInterval(apps: collapse(current))], limit: limit)
    }
}

@MainActor
final class TopAppSampler {
    private struct StoredSample {
        var bytes: [UInt8]
        var started: ProcessStart
    }

    private struct ProcessStart: Equatable {
        var seconds: UInt64
        var microseconds: UInt64
    }

    private struct StoredInterval {
        var at: ContinuousClock.Instant
        var sample: EnergyInterval
    }

    private var timer: DispatchSourceTimer?
    private var previous: [Int32: StoredSample] = [:]
    private var previousAt: ContinuousClock.Instant?
    private var intervals: [StoredInterval] = []
    private var sampleInterval = TopAppRanker.defaultSampleInterval
    private var window = TopAppRanker.defaultWindow
    private var limit = 5
    private var lastPublished: TopAppList?
    var onChange: ((TopAppList) -> Void)?

    func configure(interval: TimeInterval, window: Duration, limit: Int) {
        let restart = timer != nil && interval != sampleInterval
        sampleInterval = interval
        self.window = window
        self.limit = limit
        if restart {
            scheduleTimer()
        }
        republishRank()
    }

    func start() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        previous = [:]
        previousAt = nil
        intervals = []
        lastPublished = .measuring
        onChange?(.measuring)
        publish()
        scheduleTimer()
    }

    func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        previous = [:]
        previousAt = nil
        intervals = []
        lastPublished = nil
    }

    private func scheduleTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
        let interval = sampleInterval
        let leeway = min(1, interval / 5)
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(leeway * 1_000)))
        source.setEventHandler { [weak self] in
            self?.publish()
        }
        source.resume()
        timer = source
    }

    private func publish() {
        let now = ContinuousClock().now
        let ticks = Self.snapshot(previous: previous, elapsed: elapsedSincePrevious(now))
        let hadBaseline = !previous.isEmpty
        previous = ticks.samples
        previousAt = now
        guard hadBaseline else { return }
        intervals.append(StoredInterval(at: now, sample: EnergyInterval(apps: TopAppRanker.collapse(ticks.processes))))
        republishRank(now: now)
    }

    private func republishRank(now: ContinuousClock.Instant = ContinuousClock().now) {
        guard timer != nil || !intervals.isEmpty else { return }
        intervals.removeAll { now - $0.at > window }
        let next: TopAppList
        if intervals.isEmpty {
            next = .measuring
        } else {
            next = .apps(TopAppRanker.rank(intervals: intervals.map(\.sample), limit: limit))
        }
        guard next != lastPublished else { return }
        lastPublished = next
        onChange?(next)
    }

    private func elapsedSincePrevious(_ now: ContinuousClock.Instant) -> Double {
        guard let previousAt else { return sampleInterval }
        let parts = (now - previousAt).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    private static let spotlightPath = "/System/Library/CoreServices/Spotlight.app"
    private static let spotlightDaemons: Set<String> = ["corespotlightd", "mds", "mds_stores"]

    private static func snapshot(previous: [Int32: StoredSample], elapsed: Double) -> (samples: [Int32: StoredSample], processes: [ProcessTick]) {
        let saved = dup(STDERR_FILENO)
        let sink = open("/dev/null", O_WRONLY)
        if saved >= 0, sink >= 0 { dup2(sink, STDERR_FILENO) }
        defer {
            if saved >= 0 {
                dup2(saved, STDERR_FILENO)
                close(saved)
            }
            if sink >= 0 { close(sink) }
        }

        let capacity = 4096
        var pids = [pid_t](repeating: 0, count: capacity)
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(capacity * MemoryLayout<pid_t>.size))
        let count = max(0, Int(byteCount) / MemoryLayout<pid_t>.size)
        var samples: [Int32: StoredSample] = [:]
        var ticks: [ProcessTick] = []
        var ownerPaths: [pid_t: String] = [:]
        var ownerNames: [pid_t: String] = [:]
        samples.reserveCapacity(min(count, 128))
        for pid in pids.prefix(count) where pid > 0 {
            let owner = responsiblePid(for: pid)
            let path = ownerPaths[owner] ?? {
                let resolved = executablePath(pid: owner)
                ownerPaths[owner] = resolved
                return resolved
            }()
            if !ProcessEnergyFilter.include(path: path, name: "") {
                let name = ownerNames[owner] ?? {
                    let resolved = processName(pid: owner)
                    ownerNames[owner] = resolved
                    return resolved
                }()
                guard ProcessEnergyFilter.include(path: path, name: name) else { continue }
            }
            guard let started = processStart(pid: pid), let sample = PowerSample.take(pid: pid) else { continue }
            samples[pid] = StoredSample(bytes: sample, started: started)
            guard let before = previous[pid], before.started == started else { continue }
            let impact = PowerSample.rate(previous: before.bytes, current: sample, elapsed: elapsed)
            guard impact > 0 else { continue }
            let fallback = ownerNames[owner] ?? {
                let resolved = processName(pid: owner)
                ownerNames[owner] = resolved
                return resolved
            }()
            var identity = ProcessGrouping.identity(path: path, fallbackName: fallback)
            if identity.iconPath == nil, spotlightDaemons.contains(fallback) || spotlightDaemons.contains(identity.name) {
                identity = ProcessGrouping.identity(path: spotlightPath, fallbackName: "Spotlight")
            }
            guard identity.iconPath != nil else { continue }
            ticks.append(ProcessTick(
                pid: pid,
                group: identity.group,
                name: identity.name,
                iconPath: identity.iconPath,
                impact: impact
            ))
        }
        return (samples, ticks)
    }

    @_silgen_name("responsibility_get_pid_responsible_for_pid")
    private static func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

    private static func responsiblePid(for pid: pid_t) -> pid_t {
        let owner = responsibility_get_pid_responsible_for_pid(pid)
        return owner > 0 ? owner : pid
    }

    private static func executablePath(pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }

    private static func processStart(pid: pid_t) -> ProcessStart? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return ProcessStart(seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
    }

    private static func processName(pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }
}
