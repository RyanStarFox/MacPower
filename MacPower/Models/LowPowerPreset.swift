import Foundation

/// The four Low Power Mode choices System Settings shows.
enum LowPowerPreset: String, CaseIterable, Identifiable, Equatable, Sendable {
    case alwaysPerformance
    case alwaysSave
    case onlyBattery
    case onlyPower

    var id: String { rawValue }

    var localizationKey: String { "popover.lowPower.\(rawValue)" }
    var shortLocalizationKey: String { "popover.lowPower.short.\(rawValue)" }

    var battery: Bool {
        switch self {
        case .alwaysPerformance, .onlyPower: false
        case .alwaysSave, .onlyBattery: true
        }
    }

    var ac: Bool {
        switch self {
        case .alwaysPerformance, .onlyBattery: false
        case .alwaysSave, .onlyPower: true
        }
    }

    func isOverridden(current: Bool?, externalConnected: Bool) -> Bool {
        guard let current else { return false }
        return current != (externalConnected ? ac : battery)
    }

    static func preset(battery: Bool, ac: Bool) -> LowPowerPreset {
        switch (battery, ac) {
        case (false, false): .alwaysPerformance
        case (true, true): .alwaysSave
        case (true, false): .onlyBattery
        case (false, true): .onlyPower
        }
    }

    /// Reads `lowpowermode` under the Battery Power and AC Power sections of `pmset -g custom`.
    static func parse(pmsetOutput: String) -> LowPowerPreset? {
        var section: String?
        var battery: Bool?
        var ac: Bool?
        for raw in pmsetOutput.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "Battery Power:" {
                section = "battery"
            } else if line == "AC Power:" {
                section = "ac"
            } else if line.hasPrefix("lowpowermode") {
                let on = line.split(whereSeparator: \.isWhitespace).last == "1"
                if section == "battery" { battery = on }
                if section == "ac" { ac = on }
            }
        }
        guard let battery, let ac else { return nil }
        return preset(battery: battery, ac: ac)
    }
}

/// How the strategy and low-power buttons share the popover row.
enum LowPowerButtonLayout: String, CaseIterable, Identifiable, Sendable {
    /// Side by side when both labels fit; otherwise one button per row.
    case fitTwoPerRow
    /// Always one button per row, even when the text would fit side by side.
    case alwaysOnePerRow

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .fitTwoPerRow: "settings.lowPower.layout.fit"
        case .alwaysOnePerRow: "settings.lowPower.layout.stack"
        }
    }

    static let fallback = LowPowerButtonLayout.fitTwoPerRow

    static func resolved(stored raw: String?) -> LowPowerButtonLayout {
        guard let raw, let layout = LowPowerButtonLayout(rawValue: raw) else {
            return fallback
        }
        return layout
    }
}

/// Which buttons appear inside the energy-mode block. Hiding both is not a choice.
enum LowPowerButtonVisibility: String, CaseIterable, Identifiable, Sendable {
    case both
    case strategy
    case lowPower

    var id: String { rawValue }

    var showsStrategy: Bool { self != .lowPower }
    var showsLowPower: Bool { self != .strategy }

    var localizationKey: String {
        switch self {
        case .both: "settings.lowPower.buttons.both"
        case .strategy: "settings.lowPower.buttons.strategy"
        case .lowPower: "settings.lowPower.buttons.now"
        }
    }

    static let fallback = LowPowerButtonVisibility.both

    static func resolved(stored raw: String?) -> LowPowerButtonVisibility {
        guard let raw, let visibility = LowPowerButtonVisibility(rawValue: raw) else {
            return fallback
        }
        return visibility
    }
}
