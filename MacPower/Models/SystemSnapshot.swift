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

    /// arctan(log10(speed / 1 MB/s)). 1 MB/s sits at 50%; 0 and +∞ approach the ends.
    static func ringPercent(bytesPerSecond: Double) -> Double {
        let bytes = max(0, bytesPerSecond)
        guard bytes > 0 else { return 0 }
        let megabyte = 1024.0 * 1024.0
        let unit = atan(log10(bytes / megabyte)) / .pi + 0.5
        return min(100, max(0, unit * 100))
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
