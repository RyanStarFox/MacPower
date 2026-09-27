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
    private var lastPublished: SystemSnapshot?
    private var heavySampling = false

    var onChange: ((SystemSnapshot) -> Void)?

    func start() {
        previousCPU = Self.cpuTicks()
        // No idle timer: CPU/GPU/memory rings are only visible in the popover.
    }

    func setPopoverOpen(_ open: Bool) {
        timer?.invalidate()
        timer = nil
        if open {
            refresh(heavy: true)
            schedule(heavy: true)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func schedule(heavy: Bool) {
        heavySampling = heavy
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
        refresh(heavy: heavySampling)
    }

    private func refresh(heavy: Bool) {
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

        if heavy {
            lastGPU = Self.gpuUtilization() ?? lastGPU
            lastMemory = Self.memoryPercent()
        }

        guard let lastCPU else { return }
        let next = SystemSnapshot(
            cpuPercent: lastCPU,
            gpuPercent: lastGPU,
            memoryPercent: lastMemory
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

    private static func gpuUtilization() -> Double? {
        var best: Double?
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
                if let value = utilization(from: service) {
                    best = max(best ?? 0, value)
                }
                let child = childUtilization(service)
                if let child {
                    best = max(best ?? 0, child)
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            if best != nil { break }
        }
        return best.map { min(100, max(0, $0)) }
    }

    private static func childUtilization(_ service: io_object_t) -> Double? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        var child = IOIteratorNext(iterator)
        while child != 0 {
            if let value = utilization(from: child) {
                best = max(best ?? 0, value)
            }
            IOObjectRelease(child)
            child = IOIteratorNext(iterator)
        }
        return best
    }

    private static func utilization(from service: io_object_t) -> Double? {
        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any]
        else {
            return nil
        }
        let stats = props["PerformanceStatistics"] as? [String: Any]
        let keys = ["Device Utilization %", "Renderer Utilization %", "Tiler Utilization %"]
        var best: Double?
        for key in keys {
            if let number = stats?[key] as? NSNumber {
                best = max(best ?? 0, number.doubleValue)
            }
        }
        return best
    }
}
