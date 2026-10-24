import Foundation

enum TimeEstimateService: Sendable {
    static let unknownSentinel = 65535
    static let minimumWatts = 1.0
    static let maxReasonableMinutes = 36 * 60
    static let nominalPackVoltage = 11.55

    static func sanitizedSystemMinutes(_ value: Int?) -> Int? {
        guard let value, value > 0, value < unknownSentinel, value <= maxReasonableMinutes else {
            return nil
        }
        return value
    }

    static func wattHours(milliAmpHours: Double, voltageMilli: Double, preferNominal: Bool) -> Double {
        let volts = preferNominal ? nominalPackVoltage : min(max(voltageMilli / 1000, 9.5), 13.2)
        return max(0, milliAmpHours) / 1000 * volts
    }

    static func minutesFromEnergy(wattHours: Double, watts: Double) -> Int? {
        guard wattHours > 0.2, watts >= minimumWatts else { return nil }
        let minutes = Int((wattHours / watts * 60).rounded())
        guard minutes > 0, minutes <= maxReasonableMinutes else { return nil }
        return minutes
    }

    static func timeToFullMinutes(
        isCharging: Bool,
        systemMinutes: Int?,
        missingCapacityWh: Double,
        chargeWatts: Double
    ) -> Int? {
        guard isCharging else { return nil }
        if let systemMinutes = sanitizedSystemMinutes(systemMinutes) {
            return systemMinutes
        }
        return minutesFromEnergy(wattHours: missingCapacityWh, watts: chargeWatts)
    }

    static func timeToEmptyMinutes(
        isOnBattery: Bool,
        systemMinutes: Int?,
        remainingCapacityWh: Double,
        averageLoadWatts: Double
    ) -> Int? {
        if isOnBattery, let systemMinutes = sanitizedSystemMinutes(systemMinutes) {
            return systemMinutes
        }
        return minutesFromEnergy(wattHours: remainingCapacityWh, watts: averageLoadWatts)
    }

    /// Underpowered draws from both adapter and battery. Only the battery's
    /// discharge rate drains remaining capacity, so do not use whole-system load.
    static func drainWattsForEmptyEstimate(
        flowMode: EnergyFlowMode,
        dischargeWatts: Double,
        averageLoadWatts: Double
    ) -> Double {
        switch flowMode {
        case .underpowered:
            dischargeWatts
        case .charging, .adapterHold, .discharging:
            averageLoadWatts
        }
    }
}
