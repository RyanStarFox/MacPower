import Foundation

struct PowerSnapshot: Equatable, Sendable {
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
    var timeToEmptyMinutes: Int?
    var timeToFullMinutes: Int?
    var flowMode: EnergyFlowMode
    /// Battery temperature in °C when AppleSmartBattery publishes a sane reading.
    var batteryTemperatureCelsius: Double? = nil
    /// System thermal pressure while the popover is open. A level, not degrees.
    var thermalState: MacThermalState? = nil
    var cycleCount: Int? = nil
    /// Normalized full charge (mAh) and design capacity, when both keys exist.
    var fullChargeMilliAmpHours: Int? = nil
    var designCapacityMilliAmpHours: Int? = nil

    var chargeWatts: Double { max(0, batteryWatts) }
    var dischargeWatts: Double { max(0, -batteryWatts) }

    static let empty = PowerSnapshot(
        hasBattery: false,
        percent: 0,
        isCharging: false,
        externalConnected: false,
        fullyCharged: false,
        adapterCeilingWatts: 0,
        adapterInWatts: 0,
        systemLoadWatts: 0,
        batteryWatts: 0,
        remainingCapacityWh: 0,
        missingCapacityWh: 0,
        systemTimeToEmptyMinutes: nil,
        systemTimeToFullMinutes: nil,
        timeToEmptyMinutes: nil,
        timeToFullMinutes: nil,
        flowMode: .discharging
    )
}
