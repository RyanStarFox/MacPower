import Darwin
import Foundation
import IOKit

@MainActor
final class SystemMetricsService {
    private var timer: Timer?
    private var previousCPU: CPUTickSample.Ticks?
    private var lastCPU: Double?
    private var lastGPU: Double = 0
    private var lastMemory: Double = 0
    private var lastDisk: Double = 0
    private var lastPressure: Double = 0
    private var lastSwap: Double = 0
    private var lastSwapBytes: Double = 0
    private var lastDownload: Double = 0
    private var lastUpload: Double = 0
    private var lastNetworkSample: (counters: [String: NetworkInterfaceRates.Counters], time: TimeInterval)?
    private var lastPublished: SystemSnapshot?
    private var lastDiskRead: ContinuousClock.Instant?
    private var gpuEntries: [io_object_t] = []
    private var gpuResolvedAt: ContinuousClock.Instant?

    struct Needs: Equatable, Sendable {
        var cpu = false
        var gpu = false
        var memory = false
        var disk = false
        var pressure = false
        var swap = false
        var network = false

        var samplesAnything: Bool {
            cpu || gpu || memory || disk || pressure || swap || network
        }

        static let all = Needs(
            cpu: true, gpu: true, memory: true, disk: true, pressure: true, swap: true, network: true
        )
    }

    var needs: () -> Needs = { .all }

    var onChange: ((SystemSnapshot) -> Void)?

    func start() {
        previousCPU = Self.cpuTicks()
        // No idle timer: CPU/GPU/memory rings are only visible in the popover.
    }

    func setPopoverOpen(_ open: Bool) {
        timer?.invalidate()
        timer = nil
        guard open, needs().samplesAnything else { return }
        lastDiskRead = nil
        refresh()
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        releaseGPUEntries()
    }

    private func schedule() {
        let interval: TimeInterval = 1
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(handleTimer),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc
    private func handleTimer() {
        guard needs().samplesAnything else { return }
        refresh()
    }

    private func refresh() {
        let wanted = needs()
        if wanted.cpu {
            let cpuTicks = Self.cpuTicks()
            if let resolved = CPUTickSample.resolvedPercent(
                previous: previousCPU,
                current: cpuTicks,
                lastPublished: lastCPU
            ) {
                lastCPU = resolved
            }
            if let cpuTicks {
                previousCPU = cpuTicks
            }
        }

        if wanted.gpu {
            lastGPU = gpuUtilization() ?? lastGPU
        }
        if wanted.memory {
            lastMemory = Self.memoryPercent()
        }
        if wanted.disk {
            let now = ContinuousClock.now
            if lastDiskRead == nil || now - (lastDiskRead ?? now) > .seconds(60) {
                lastDisk = Self.diskPercent() ?? lastDisk
                lastDiskRead = now
            }
        }
        if wanted.pressure {
            lastPressure = Self.memoryPressurePercent()
        }
        if wanted.swap {
            let reading = Self.swapReading()
            lastSwap = reading.percent
            lastSwapBytes = reading.usedBytes
        }
        if wanted.network, let rates = Self.networkRates(since: &lastNetworkSample) {
            lastDownload = rates.download
            lastUpload = rates.upload
        }

        if wanted.cpu, lastCPU == nil { return }
        let next = SystemSnapshot(
            cpuPercent: lastCPU ?? 0,
            gpuPercent: lastGPU,
            memoryPercent: lastMemory,
            diskPercent: lastDisk,
            memoryPressurePercent: lastPressure,
            swapPercent: lastSwap,
            swapUsedBytes: lastSwapBytes,
            downloadBytesPerSecond: lastDownload,
            uploadBytesPerSecond: lastUpload
        )
        if let lastPublished, lastPublished.sameRingDisplay(as: next) {
            return
        }
        lastPublished = next
        onChange?(next)
    }

    private static func cpuTicks() -> CPUTickSample.Ticks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ints in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, ints, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTickSample.Ticks(
            user: Double(info.cpu_ticks.0),
            system: Double(info.cpu_ticks.1),
            idle: Double(info.cpu_ticks.2),
            nice: Double(info.cpu_ticks.3)
        )
    }

    private static func memoryPercent() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kernel = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ints in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, ints, &count)
            }
        }
        guard kernel == KERN_SUCCESS else { return 0 }

        var memsize: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memsize, &size, nil, 0)
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return MemoryOccupancy.usagePercent(usedBytes: used, totalBytes: memsize)
    }

    private static func diskPercent() -> Double? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage,
            total > 0
        else { return nil }
        let used = max(0, Int64(total) - available)
        return min(100, Double(used) / Double(total) * 100)
    }

    /// Maps the kernel pressure level onto a ring. Normal stays low; critical fills the ring.
    private static func memoryPressurePercent() -> Double {
        var level: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return 0 }
        switch level {
        case 0x2: return 45
        case 0x4: return 75
        case 0x8: return 100
        default: return 15
        }
    }

    private static func swapReading() -> (percent: Double, usedBytes: Double) {
        var diskUsed: Double = 0
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 {
            diskUsed = Double(usage.xsu_used)
        }

        var compressorPages: UInt64 = 0
        var pageBytes: UInt64 = 0
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kernel = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ints in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, ints, &count)
            }
        }
        if kernel == KERN_SUCCESS {
            var pageSize: vm_size_t = 0
            host_page_size(mach_host_self(), &pageSize)
            pageBytes = UInt64(pageSize)
            compressorPages = UInt64(stats.compressor_page_count)
        }

        let used = SwapUsageFormat.usedBytes(
            diskSwapBytes: diskUsed,
            compressorPages: compressorPages,
            pageSize: pageBytes
        )
        let memory = SwapUsageFormat.physicalMemoryBytes()
        let percent = SwapUsageFormat.ringPercent(
            usedBytes: used,
            halfBytes: memory / 4,
            memoryBytes: memory
        )
        return (percent, used)
    }

    private static func networkRates(
        since previous: inout (counters: [String: NetworkInterfaceRates.Counters], time: TimeInterval)?
    ) -> (download: Double, upload: Double)? {
        guard let current = NetworkInterfaceRates.currentCounters() else { return nil }
        let now = Date().timeIntervalSinceReferenceDate
        let prior = previous
        previous = (current, now)
        return NetworkInterfaceRates.rates(
            current: current,
            previous: prior?.counters,
            elapsed: prior.map { now - $0.time } ?? 0
        )
    }

    /// Walks the accelerator tree once, then reads only `PerformanceStatistics` from the entries that have it.
    private func gpuUtilization() -> Double? {
        let now = ContinuousClock.now
        if gpuEntries.isEmpty {
            if let gpuResolvedAt, now - gpuResolvedAt < .seconds(30) { return nil }
            resolveGPUEntries()
            gpuResolvedAt = now
        }
        var best: Double?
        var dead = 0
        for entry in gpuEntries {
            switch readUtilization(from: entry) {
            case .value(let value):
                best = max(best ?? 0, value)
            case .missing:
                break
            case .dead:
                dead += 1
            }
        }
        if dead == gpuEntries.count, !gpuEntries.isEmpty {
            resolveGPUEntries()
            gpuResolvedAt = now
            for entry in gpuEntries {
                if case .value(let value) = readUtilization(from: entry) {
                    best = max(best ?? 0, value)
                }
            }
        }
        return best.map { min(100, max(0, $0)) }
    }

    private func resolveGPUEntries() {
        releaseGPUEntries()
        for className in ["AGXAccelerator", "IOAccelerator", "IOGPU"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching(className),
                &iterator
            ) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            while service != 0 {
                keepGPUEntry(service)
                service = IOIteratorNext(iterator)
            }
            if !gpuEntries.isEmpty { break }
        }
    }

    private func keepGPUEntry(_ service: io_object_t) {
        var keptService = false
        if case .value = readUtilization(from: service) {
            gpuEntries.append(service)
            keptService = true
        }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            if !keptService { IOObjectRelease(service) }
            return
        }
        defer { IOObjectRelease(iterator) }
        var child = IOIteratorNext(iterator)
        while child != 0 {
            if case .value = readUtilization(from: child) {
                gpuEntries.append(child)
            } else {
                IOObjectRelease(child)
            }
            child = IOIteratorNext(iterator)
        }
        if !keptService { IOObjectRelease(service) }
    }

    private func releaseGPUEntries() {
        for entry in gpuEntries {
            IOObjectRelease(entry)
        }
        gpuEntries = []
    }

    private enum GPURead {
        case value(Double)
        case missing
        case dead
    }

    private func readUtilization(from service: io_object_t) -> GPURead {
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "PerformanceStatistics" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return .dead
        }
        guard let stats = property as? [String: Any] else { return .missing }
        let keys = ["Device Utilization %", "Renderer Utilization %", "Tiler Utilization %"]
        var best: Double?
        for key in keys {
            if let number = stats[key] as? NSNumber {
                best = max(best ?? 0, number.doubleValue)
            }
        }
        return best.map { .value($0) } ?? .missing
    }
}

/// Per-interface 64-bit counters. A summed total treats a new virtual interface,
/// or a 32-bit counter wrapping, as throughput for the whole interval.
enum NetworkInterfaceRates {
    struct Counters: Equatable, Sendable {
        var rx: UInt64
        var tx: UInt64
    }

    static func rates(
        current: [String: Counters],
        previous: [String: Counters]?,
        elapsed: TimeInterval
    ) -> (download: Double, upload: Double)? {
        guard let previous else { return (0, 0) }
        guard elapsed > 0.2, elapsed.isFinite else { return nil }
        var download: Double = 0
        var upload: Double = 0
        for (name, now) in current {
            guard let prior = previous[name] else { continue }
            download += increased(now.rx, from: prior.rx)
            upload += increased(now.tx, from: prior.tx)
        }
        return (download / elapsed, upload / elapsed)
    }

    /// A counter that moves backwards was reset. It is not a wrapped total.
    static func increased(_ current: UInt64, from prior: UInt64) -> Double {
        guard current >= prior else { return 0 }
        return Double(current - prior)
    }

    static func currentCounters() -> [String: Counters]? {
        var name: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        for _ in 0..<3 {
            guard sysctl(&name, u_int(name.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: length)
            let copied = length
            let result = buffer.withUnsafeMutableBytes { raw -> Int32 in
                guard let base = raw.baseAddress else { return -1 }
                return sysctl(&name, u_int(name.count), base, &length, nil, 0)
            }
            if result == 0 {
                return parseCounters(buffer, length: min(copied, length))
            }
            guard errno == ENOMEM else { return nil }
        }
        return nil
    }

    private static func parseCounters(_ buffer: [UInt8], length: Int) -> [String: Counters] {
        var counters: [String: Counters] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }
                if header.ifm_type == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if info.ifm_flags & IFF_LOOPBACK == 0 {
                        var ifname = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                        if if_indextoname(UInt32(info.ifm_index), &ifname) != nil {
                            counters[String(cString: ifname)] = Counters(
                                rx: info.ifm_data.ifi_ibytes,
                                tx: info.ifm_data.ifi_obytes
                            )
                        }
                    }
                }
                offset += messageLength
            }
        }
        return counters
    }
}
