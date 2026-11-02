import Foundation

struct SystemSnapshot: Equatable, Sendable {
    var cpuPercent: Double
    var gpuPercent: Double
    var memoryPercent: Double
    var diskPercent: Double = 0
    var memoryPressurePercent: Double = 0
    var swapPercent: Double = 0
    var downloadBytesPerSecond: Double = 0
    var uploadBytesPerSecond: Double = 0

    static let empty = SystemSnapshot(cpuPercent: 0, gpuPercent: 0, memoryPercent: 0)

    /// Caption uses the nearest integer. Tint bands truncate. Either change
    /// should redraw the rings; noise inside the same integers should not.
    func sameRingDisplay(as other: SystemSnapshot) -> Bool {
        Self.sameRingPercent(cpuPercent, other.cpuPercent)
            && Self.sameRingPercent(gpuPercent, other.gpuPercent)
            && Self.sameRingPercent(memoryPercent, other.memoryPercent)
            && Self.sameRingPercent(diskPercent, other.diskPercent)
            && Self.sameRingPercent(memoryPressurePercent, other.memoryPressurePercent)
            && Self.sameRingPercent(swapPercent, other.swapPercent)
            && Self.sameRate(downloadBytesPerSecond, other.downloadBytesPerSecond)
            && Self.sameRate(uploadBytesPerSecond, other.uploadBytesPerSecond)
    }

    private static func sameRate(_ lhs: Double, _ rhs: Double) -> Bool {
        Int((lhs / 1024).rounded()) == Int((rhs / 1024).rounded())
    }

    private static func sameRingPercent(_ lhs: Double, _ rhs: Double) -> Bool {
        captionPercent(lhs) == captionPercent(rhs) && tintPercent(lhs) == tintPercent(rhs)
    }

    private static func captionPercent(_ percent: Double) -> Int {
        Int(percent.rounded())
    }

    private static func tintPercent(_ percent: Double) -> Int {
        Int(min(100, max(0, percent)).rounded(.towardZero))
    }
}

enum NetworkRateFormat {
    static func string(bytesPerSecond: Double) -> String {
        let bytes = max(0, bytesPerSecond)
        if bytes < 1024 * 1024 {
            return String(format: "%.0f KB/s", bytes / 1024)
        }
        return String(format: "%.1f MB/s", bytes / (1024 * 1024))
    }

    /// arctan(log10(speed / center)). The center rate sits at 50%; 0 and +∞ approach the ends.
    static func ringPercent(bytesPerSecond: Double, centerBytesPerSecond: Double = 1024 * 1024) -> Double {
        let bytes = max(0, bytesPerSecond)
        guard bytes > 0, centerBytesPerSecond > 0, centerBytesPerSecond.isFinite else { return 0 }
        let unit = atan(log10(bytes / centerBytesPerSecond)) / .pi + 0.5
        return min(100, max(0, unit * 100))
    }

    static func midpointLabel(kilobytesPerSecond: Int) -> String {
        if kilobytesPerSecond >= 1024, kilobytesPerSecond.isMultiple(of: 1024) {
            return "\(kilobytesPerSecond / 1024) MB/s"
        }
        if kilobytesPerSecond >= 1024 {
            return String(format: "%.1f MB/s", Double(kilobytesPerSecond) / 1024)
        }
        return "\(kilobytesPerSecond) KB/s"
    }
}

enum BatteryTemperatureFormat {
    /// Default center. 30°C sits at 50% until the user picks another midpoint.
    static let centerCelsius = 30.0

    /// AppleSmartBattery `Temperature` is centi-Celsius on this machine (3409 → 34.09°C)
    /// and deci-Celsius on others (310 → 31.0°C). Keep the scale that lands in a real
    /// battery range. 0 and negative values are missing.
    static func celsius(raw: Double) -> Double? {
        guard raw > 0, raw.isFinite else { return nil }
        let centi = raw / 100
        let deci = raw / 10
        let centiPlausible = (10...90).contains(centi)
        let deciPlausible = (10...90).contains(deci)
        if centiPlausible, !deciPlausible { return centi }
        if deciPlausible, !centiPlausible { return deci }
        return nil
    }

    static func ringPercent(celsius: Double, centerCelsius: Double = centerCelsius) -> Double {
        guard celsius > 0, celsius.isFinite, centerCelsius > 0, centerCelsius.isFinite else { return 0 }
        let unit = atan(log10(celsius / centerCelsius)) / .pi + 0.5
        return min(100, max(0, unit * 100))
    }

    static func caption(celsius: Double) -> String {
        String(format: "%.0f°C", celsius.rounded())
    }
}

/// `ProcessInfo.thermalState` is a pressure level, not a temperature.
enum MacThermalState: Int, Equatable, Sendable {
    case nominal = 0
    case fair
    case serious
    case critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }

    /// Fill for this level. Defaults match 25 / 50 / 75 / 100 until the user changes them.
    var ringPercent: Double {
        ringPercent(nominal: 25, fair: 50, serious: 75, critical: 100)
    }

    func ringPercent(nominal: Int, fair: Int, serious: Int, critical: Int) -> Double {
        let raw: Int
        switch self {
        case .nominal: raw = nominal
        case .fair: raw = fair
        case .serious: raw = serious
        case .critical: raw = critical
        }
        return Double(min(100, max(0, raw)))
    }

    var captionKey: String {
        switch self {
        case .nominal: "ring.thermal.nominal"
        case .fair: "ring.thermal.fair"
        case .serious: "ring.thermal.serious"
        case .critical: "ring.thermal.critical"
        }
    }
}

enum BatteryCapacityFormat {
    /// Current full charge over design capacity. Nil when design is missing or zero.
    static func percent(fullChargeMilliAmpHours: Int, designMilliAmpHours: Int) -> Double? {
        guard designMilliAmpHours > 0, fullChargeMilliAmpHours >= 0 else { return nil }
        return Double(fullChargeMilliAmpHours) / Double(designMilliAmpHours) * 100
    }

    /// NominalChargeCapacity is the normalized full charge in the battery dictionary.
    /// AppleRawMaxCapacity, then FullChargeCapacity, are the uncompensated fallbacks.
    static func fullChargeMilliAmpHours(nominal: Int?, appleRawMax: Int?, fullCharge: Int?) -> Int? {
        for value in [nominal, appleRawMax, fullCharge] {
            if let value, value > 0 { return value }
        }
        return nil
    }

    static func detail(fullChargeMilliAmpHours: Int, designMilliAmpHours: Int) -> String? {
        text(
            fullChargeMilliAmpHours: fullChargeMilliAmpHours,
            designMilliAmpHours: designMilliAmpHours,
            style: .both
        )
    }

    static func text(
        fullChargeMilliAmpHours: Int,
        designMilliAmpHours: Int,
        style: BatteryCapacityStyle
    ) -> String? {
        guard let percent = percent(
            fullChargeMilliAmpHours: fullChargeMilliAmpHours,
            designMilliAmpHours: designMilliAmpHours
        ) else { return nil }
        let percentText = "\(Int(percent.rounded()))%"
        let ratioText = "\(fullChargeMilliAmpHours)/\(designMilliAmpHours) mAh"
        switch style {
        case .percent: return percentText
        case .milliampHours: return ratioText
        case .both: return "\(percentText) · \(ratioText)"
        }
    }
}

/// How the cycle block writes maximum capacity.
enum BatteryCapacityStyle: String, CaseIterable, Identifiable, Sendable {
    case percent
    case milliampHours
    case both

    var id: String { rawValue }

    var localizationKey: String { "settings.batteryCycle.format.\(rawValue)" }

    static let fallback = BatteryCapacityStyle.both

    static func resolved(stored raw: String?) -> BatteryCapacityStyle {
        guard let raw, let style = BatteryCapacityStyle(rawValue: raw) else { return fallback }
        return style
    }
}

enum CPUTickSample: Equatable, Sendable {
    struct Ticks: Equatable, Sendable {
        var user: Double
        var system: Double
        var idle: Double
        var nice: Double
    }

    static func usagePercent(previous: Ticks, current: Ticks) -> Double {
        let user = max(0, current.user - previous.user)
        let system = max(0, current.system - previous.system)
        let idle = max(0, current.idle - previous.idle)
        let nice = max(0, current.nice - previous.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return min(100, (user + system + nice) / total * 100)
    }

    /// Returns a CPU percent only when ticks actually advanced.
    /// Identical samples would otherwise look like 0% and flash the UI.
    static func resolvedPercent(previous: Ticks?, current: Ticks?, lastPublished: Double?) -> Double? {
        guard let previous, let current else { return lastPublished }
        let user = max(0, current.user - previous.user)
        let system = max(0, current.system - previous.system)
        let idle = max(0, current.idle - previous.idle)
        let nice = max(0, current.nice - previous.nice)
        guard user + system + idle + nice > 0 else { return lastPublished }
        return usagePercent(previous: previous, current: current)
    }
}

enum MemoryOccupancy: Equatable, Sendable {
    static func usagePercent(usedBytes: UInt64, totalBytes: UInt64) -> Double {
        guard totalBytes > 0 else { return 0 }
        return min(100, Double(usedBytes) / Double(totalBytes) * 100)
    }
}
