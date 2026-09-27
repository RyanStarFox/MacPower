import Foundation
import IOKit
import IOKit.ps

struct BatteryReading: Equatable, Sendable {
    var hasBattery: Bool
    var percent: Double
    var isCharging: Bool
    var externalConnected: Bool
    var fullyCharged: Bool
    var adapterCeilingWatts: Double
    var adapterInWatts: Double
    var systemLoadWatts: Double
    var batteryWatts: Double
    var remainingCapacityWh: Double
    var missingCapacityWh: Double
    var systemTimeToEmptyMinutes: Int?
    var systemTimeToFullMinutes: Int?
    var instantAmperageMilli: Int
}

enum BatteryTimeFallback {
    /// Copying the IOPS power-source list is only useful when the smart-battery
    /// snapshot has neither time-to-empty nor time-to-full.
    static func needsPowerSourceTimes(empty: Int?, full: Int?) -> Bool {
        empty == nil && full == nil
    }
}

enum BatteryReader: Sendable {
    static func read(cachedService: inout io_service_t) -> BatteryReading? {
        readSmartBattery(cachedService: &cachedService) ?? readPowerSources()
    }

    static func release(_ service: inout io_service_t) {
        guard service != 0 else { return }
        IOObjectRelease(service)
        service = 0
    }

    private static func readSmartBattery(cachedService: inout io_service_t) -> BatteryReading? {
        guard let nsProps = smartBatteryProperties(cachedService: &cachedService) else {
            return nil
        }

        let hasBattery = bool(nsProps["BatteryInstalled"]) ?? true
        let external = bool(nsProps["ExternalConnected"]) ?? false
        let isCharging = bool(nsProps["IsCharging"]) ?? chargerIsCharging(nsProps)
        let fullyCharged = bool(nsProps["FullyCharged"]) ?? false
        let percent = double(nsProps["CurrentCapacity"]) ?? 0
        let voltageMilli = double(nsProps["Voltage"]) ?? 0
        let instantAmperage = signedMilliAmps(nsProps["InstantAmperage"]) ?? signedMilliAmps(nsProps["Amperage"]) ?? 0

        let adapter = nsProps["AdapterDetails"] as? [String: Any]
        let adapterCeiling = double(adapter?["Watts"]) ?? 0

        let telemetry = nsProps["PowerTelemetryData"] as? [String: Any]
        let systemLoad = milliwattsToWatts(telemetry?["SystemLoad"])
        let systemPowerIn = milliwattsToWatts(telemetry?["SystemPowerIn"])
        let telemetryBattery = milliwattsToWatts(telemetry?["BatteryPower"])

        let viWatts = (Double(instantAmperage) * voltageMilli) / 1_000_000
        // Telemetry can sit at 0 for a long time after unplug; 0 is a real NSNumber
        // so `??` would never fall back to V×I. Treat near-zero as missing.
        let batteryWatts = nonzeroWatts(telemetryBattery) ?? viWatts
        let adapterIn: Double
        if !external {
            adapterIn = 0
        } else {
            adapterIn = nonzeroWatts(systemPowerIn) ?? max(0, abs(viWatts) + max(0, systemLoad ?? 0))
        }
        let load: Double
        if let systemLoad = nonzeroWatts(systemLoad) {
            load = abs(systemLoad)
        } else if isCharging {
            load = max(0, adapterIn - max(0, batteryWatts))
        } else {
            load = abs(min(0, batteryWatts))
        }

        let batteryData = nsProps["BatteryData"] as? [String: Any]
        let remainingMilliAh = double(batteryData?["RemainingCapacity"])
            ?? double(nsProps["AppleRawCurrentCapacity"])
            ?? 0
        let fullMilliAh = double(batteryData?["FullChargeCapacity"])
            ?? double(nsProps["AppleRawMaxCapacity"])
            ?? 0
        let remainingWh = TimeEstimateService.wattHours(
            milliAmpHours: remainingMilliAh,
            voltageMilli: voltageMilli,
            preferNominal: isCharging || external
        )
        let fullWh = TimeEstimateService.wattHours(
            milliAmpHours: fullMilliAh,
            voltageMilli: voltageMilli,
            preferNominal: true
        )
        let missingWh = max(0, fullWh - remainingWh)

        var timeToEmpty = sanitized(int(nsProps["AvgTimeToEmpty"]))
        var timeToFull = sanitized(int(nsProps["AvgTimeToFull"]))
            ?? sanitized(isCharging ? int(nsProps["TimeRemaining"]) : nil)
        if !isCharging, timeToEmpty == nil {
            timeToEmpty = sanitized(int(nsProps["TimeRemaining"]))
        }
        if BatteryTimeFallback.needsPowerSourceTimes(empty: timeToEmpty, full: timeToFull),
           let iops = iopsTimes() {
            timeToEmpty = iops.empty
            timeToFull = iops.full
        }

        return BatteryReading(
            hasBattery: hasBattery,
            percent: min(100, max(0, percent)),
            isCharging: isCharging,
            externalConnected: external,
            fullyCharged: fullyCharged,
            adapterCeilingWatts: adapterCeiling,
            adapterInWatts: adapterIn,
            systemLoadWatts: load,
            batteryWatts: batteryWatts,
            remainingCapacityWh: remainingWh,
            missingCapacityWh: missingWh,
            systemTimeToEmptyMinutes: timeToEmpty,
            systemTimeToFullMinutes: timeToFull,
            instantAmperageMilli: instantAmperage
        )
    }

    private static func readPowerSources() -> BatteryReading? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = desc[kIOPSTypeKey] as? String
            guard type == kIOPSInternalBatteryType else { continue }

            let percent = double(desc[kIOPSCurrentCapacityKey]) ?? 0
            let isCharging = bool(desc[kIOPSIsChargingKey]) ?? false
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let external = state == kIOPSACPowerValue
            let timeToEmpty = sanitized(int(desc[kIOPSTimeToEmptyKey]))
            let timeToFull = sanitized(int(desc[kIOPSTimeToFullChargeKey]))

            return BatteryReading(
                hasBattery: true,
                percent: percent,
                isCharging: isCharging,
                externalConnected: external,
                fullyCharged: percent >= 99.5 && external && !isCharging,
                adapterCeilingWatts: 0,
                adapterInWatts: 0,
                systemLoadWatts: 0,
                batteryWatts: 0,
                remainingCapacityWh: 0,
                missingCapacityWh: 0,
                systemTimeToEmptyMinutes: timeToEmpty,
                systemTimeToFullMinutes: timeToFull,
                instantAmperageMilli: isCharging ? 1 : (external ? 0 : -1)
            )
        }
        return nil
    }

    /// One registry snapshot per read. The service stays open so the next sample
    /// does not look up AppleSmartBattery by name again. A failed copy drops it
    /// and opens a fresh port once.
    private static func smartBatteryProperties(cachedService: inout io_service_t) -> [String: Any]? {
        if let props = copyProperties(cachedService) {
            return props
        }
        release(&cachedService)
        cachedService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard cachedService != 0 else { return nil }
        return copyProperties(cachedService)
    }

    private static func copyProperties(_ service: io_service_t) -> [String: Any]? {
        guard service != 0 else { return nil }
        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any]
        else {
            return nil
        }
        return props
    }

    private static func iopsTimes() -> (empty: Int?, full: Int?)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            return (
                empty: sanitized(int(desc[kIOPSTimeToEmptyKey])),
                full: sanitized(int(desc[kIOPSTimeToFullChargeKey]))
            )
        }
        return nil
    }

    private static func milliwattsToWatts(_ value: Any?) -> Double? {
        guard let milli = signedMilli(value) else { return nil }
        if abs(milli) > 250 {
            return milli / 1000
        }
        return milli
    }

    /// IOKit often publishes `0` as a real number after a power-source change.
    /// That must not win over InstantAmperage × Voltage.
    private static func nonzeroWatts(_ watts: Double?) -> Double? {
        guard let watts, abs(watts) >= 0.4 else { return nil }
        return watts
    }

    private static func signedMilli(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let uint = number.uint64Value
        if uint > UInt64(Int64.max) {
            return Double(Int64(bitPattern: uint))
        }
        return number.doubleValue
    }

    private static func signedMilliAmps(_ value: Any?) -> Int? {
        guard let milli = signedMilli(value) else { return nil }
        return Int(milli.rounded())
    }

    private static func sanitized(_ value: Int?) -> Int? {
        TimeEstimateService.sanitizedSystemMinutes(value)
    }

    private static func chargerIsCharging(_ props: [String: Any]) -> Bool {
        let charger = props["ChargerData"] as? [String: Any]
        return bool(charger?["IsCharging"]) ?? false
    }

    private static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let number as NSNumber: number.boolValue
        case let flag as Bool: flag
        default: nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}

/// IOKit often publishes 0W for a few samples after unplug. Keep the last real
/// load on screen instead of flashing 0.00 W.
enum HeldLoadWatts {
    static let floor = 0.4

    static func hold(current: Double, previous: Double?) -> Double {
        if current >= floor { return current }
        guard let previous, previous >= floor else { return current }
        return previous
    }
}

@MainActor
final class PowerTelemetryService {
    private var liveTimer: Timer?
    private var idleTimer: Timer?
    private var powerSourceLoop: CFRunLoopSource?
    private var powerSourceCallback: PowerSourceCallback?
    private var smoothed: PowerSnapshot?
    private var estimateLoadWatts: Double?
    private var popoverOpen = false
    private var batteryService: io_service_t = 0

    var onChange: ((PowerSnapshot) -> Void)?

    func start() {
        refresh(smooth: false)
        listenForPowerSourceChanges()
        scheduleIdleTimer()
    }

    func setPopoverOpen(_ open: Bool) {
        popoverOpen = open
        liveTimer?.invalidate()
        liveTimer = nil
        idleTimer?.invalidate()
        idleTimer = nil

        if open {
            refresh(smooth: true)
            liveTimer = makeTimer(interval: 1.0, tolerance: 0.25, selector: #selector(handleLiveTimer))
        } else {
            scheduleIdleTimer()
        }
    }

    func stop() {
        liveTimer?.invalidate()
        idleTimer?.invalidate()
        liveTimer = nil
        idleTimer = nil
        powerSourceCallback?.invalidate()
        if let powerSourceLoop {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceLoop, .defaultMode)
            self.powerSourceLoop = nil
        }
        powerSourceCallback = nil
        BatteryReader.release(&batteryService)
    }

    private func scheduleIdleTimer() {
        // IOPS notifications cover plug/charge flips; this is only a backup for
        // integer percent drift while the panel is closed. Keep it rare so App Nap
        // is not woken every minute for a full AppleSmartBattery read.
        idleTimer = makeTimer(interval: 300, tolerance: 60, selector: #selector(handleIdleTimer))
    }

    private func makeTimer(interval: TimeInterval, tolerance: TimeInterval, selector: Selector) -> Timer {
        let timer = Timer(timeInterval: interval, target: self, selector: selector, userInfo: nil, repeats: true)
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    @objc
    private func handleLiveTimer() {
        refresh(smooth: true)
    }

    @objc
    private func handleIdleTimer() {
        refresh(smooth: true)
    }

    private func listenForPowerSourceChanges() {
        let callback = PowerSourceCallback { [weak self] in
            self?.refresh(smooth: false)
        }
        powerSourceCallback = callback
        let context = Unmanaged.passUnretained(callback).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerSourceCallback>.fromOpaque(context).takeUnretainedValue().invoke()
        }, context)?.takeRetainedValue() else {
            powerSourceCallback = nil
            return
        }
        powerSourceLoop = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func refresh(smooth: Bool) {
        guard let reading = BatteryReader.read(cachedService: &batteryService) else {
            onChange?(.empty)
            return
        }

        let mode = EnergyFlowMode.derive(
            hasBattery: reading.hasBattery,
            externalConnected: reading.externalConnected,
            isCharging: reading.isCharging,
            instantAmperageMilli: reading.instantAmperageMilli,
            batteryWatts: reading.batteryWatts
        )

        var snapshot = PowerSnapshot(
            hasBattery: reading.hasBattery,
            percent: reading.percent,
            isCharging: reading.isCharging,
            externalConnected: reading.externalConnected,
            fullyCharged: reading.fullyCharged,
            adapterCeilingWatts: reading.adapterCeilingWatts,
            adapterInWatts: reading.adapterInWatts,
            systemLoadWatts: reading.systemLoadWatts,
            batteryWatts: reading.batteryWatts,
            remainingCapacityWh: reading.remainingCapacityWh,
            missingCapacityWh: reading.missingCapacityWh,
            systemTimeToEmptyMinutes: reading.systemTimeToEmptyMinutes,
            systemTimeToFullMinutes: reading.systemTimeToFullMinutes,
            timeToEmptyMinutes: nil,
            timeToFullMinutes: nil,
            flowMode: mode
        )

        let instantEstimateLoad = max(snapshot.systemLoadWatts, snapshot.dischargeWatts)
        let heldLoad = HeldLoadWatts.hold(current: instantEstimateLoad, previous: estimateLoadWatts)
        if instantEstimateLoad >= HeldLoadWatts.floor {
            if let previousEstimate = estimateLoadWatts, smooth {
                estimateLoadWatts = ema(previousEstimate, instantEstimateLoad, alpha: 0.06)
            } else {
                estimateLoadWatts = instantEstimateLoad
            }
        } else if estimateLoadWatts == nil {
            estimateLoadWatts = instantEstimateLoad
        }

        if instantEstimateLoad < HeldLoadWatts.floor, heldLoad >= HeldLoadWatts.floor {
            snapshot.systemLoadWatts = max(snapshot.systemLoadWatts, heldLoad)
            if !snapshot.externalConnected, snapshot.dischargeWatts < HeldLoadWatts.floor {
                snapshot.batteryWatts = -heldLoad
            }
        }

        snapshot.timeToFullMinutes = TimeEstimateService.timeToFullMinutes(
            isCharging: snapshot.isCharging,
            systemMinutes: snapshot.systemTimeToFullMinutes,
            missingCapacityWh: snapshot.missingCapacityWh,
            chargeWatts: snapshot.chargeWatts
        )
        snapshot.timeToEmptyMinutes = TimeEstimateService.timeToEmptyMinutes(
            isOnBattery: !snapshot.externalConnected || snapshot.flowMode == .discharging || snapshot.flowMode == .underpowered,
            systemMinutes: snapshot.systemTimeToEmptyMinutes,
            remainingCapacityWh: snapshot.remainingCapacityWh,
            averageLoadWatts: estimateLoadWatts ?? instantEstimateLoad
        )

        // Panel closed: keep internal EMA state, but skip UI publishes when the
        // menu-bar glyph would not change (watts jitter is invisible there).
        if !popoverOpen, let previous = smoothed, Self.menuBarEqual(previous, snapshot) {
            smoothed = snapshot
            return
        }

        smoothed = snapshot
        onChange?(snapshot)
    }

    private static func menuBarEqual(_ a: PowerSnapshot, _ b: PowerSnapshot) -> Bool {
        Int(a.percent.rounded(.towardZero)) == Int(b.percent.rounded(.towardZero))
            && a.flowMode == b.flowMode
            && a.hasBattery == b.hasBattery
    }

    private func ema(_ previous: Double, _ next: Double, alpha: Double) -> Double {
        previous * (1 - alpha) + next * alpha
    }
}

/// IOPS delivers on the run loop we registered (main). Keep a dedicated trampoline so
/// `stop()` can drop the handler before the CF source is released — no Task hop, no
/// `Unmanaged` of the `@MainActor` service itself.
private final class PowerSourceCallback: @unchecked Sendable {
    private var handler: (@MainActor () -> Void)?

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    func invalidate() {
        handler = nil
    }

    func invoke() {
        guard let handler else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated(handler)
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated(handler)
            }
        }
    }
}
