import SwiftUI

struct AppTheme: Equatable, Sendable {
    var charging: Color
    var discharging: Color
    var adapterHold: Color
    var underpowered: Color
    var lowBatteryYellow: Color
    var lowBatteryRed: Color
    var sheen: Color

    func color(for mode: EnergyFlowMode) -> Color {
        switch mode {
        case .charging: charging
        case .discharging: discharging
        case .adapterHold: adapterHold
        case .underpowered: underpowered
        }
    }

    /// Solid motion marks: deep green / blue / orange, no traveling wash.
    func motionSolid(for mode: EnergyFlowMode) -> Color {
        color(for: mode).mixed(with: .black, by: 0.42)
    }

    static func resolved(palette: ThemePalette, colorScheme: ColorScheme) -> AppTheme {
        let isDark = colorScheme == .dark
        switch palette {
        case .semantic:
            return AppTheme(
                charging: Color(red: isDark ? 0.42 : 0.18, green: isDark ? 0.84 : 0.67, blue: isDark ? 0.55 : 0.39),
                discharging: Color(red: isDark ? 0.98 : 0.86, green: isDark ? 0.67 : 0.48, blue: isDark ? 0.31 : 0.16),
                adapterHold: Color(red: isDark ? 0.45 : 0.18, green: isDark ? 0.68 : 0.48, blue: isDark ? 0.98 : 0.86),
                underpowered: Color(red: isDark ? 0.55 : 0.22, green: isDark ? 0.72 : 0.50, blue: isDark ? 0.98 : 0.90),
                // Match system Low Power menu-bar yellow `#FFD702`.
                lowBatteryYellow: Color(red: 1.00, green: 215.0 / 255.0, blue: 2.0 / 255.0),
                lowBatteryRed: isDark ? Color(red: 1.00, green: 0.42, blue: 0.38) : Color(red: 0.82, green: 0.16, blue: 0.15),
                sheen: .white.opacity(isDark ? 0.55 : 0.70)
            )
        case .system:
            return AppTheme(
                charging: Color.green,
                discharging: Color.orange,
                adapterHold: Color.accentColor,
                underpowered: Color.accentColor.opacity(0.85),
                lowBatteryYellow: Color.yellow,
                lowBatteryRed: Color.red,
                sheen: .white.opacity(0.6)
            )
        case .highContrast:
            return AppTheme(
                charging: isDark ? Color(red: 0.20, green: 0.98, blue: 0.48) : Color(red: 0.00, green: 0.48, blue: 0.18),
                discharging: isDark ? Color(red: 1.00, green: 0.72, blue: 0.10) : Color(red: 0.72, green: 0.32, blue: 0.00),
                adapterHold: isDark ? Color(red: 0.45, green: 0.78, blue: 1.00) : Color(red: 0.00, green: 0.28, blue: 0.72),
                underpowered: isDark ? Color(red: 0.70, green: 0.85, blue: 1.00) : Color(red: 0.10, green: 0.20, blue: 0.62),
                lowBatteryYellow: isDark ? Color.yellow : Color(red: 0.70, green: 0.45, blue: 0.00),
                lowBatteryRed: isDark ? Color(red: 1.00, green: 0.30, blue: 0.28) : Color(red: 0.70, green: 0.05, blue: 0.05),
                sheen: .white.opacity(0.8)
            )
        case .glassMono:
            let fill = isDark ? Color.white.opacity(0.72) : Color.black.opacity(0.55)
            return AppTheme(
                charging: fill,
                discharging: fill,
                adapterHold: fill,
                underpowered: fill,
                lowBatteryYellow: isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.7),
                lowBatteryRed: isDark ? Color.white : Color.black,
                sheen: isDark ? Color.white.opacity(0.45) : Color.white.opacity(0.65)
            )
        }
    }

    func batteryFill(percent: Double, mode: EnergyFlowMode, lowBatteryTintEnabled: Bool) -> Color {
        if lowBatteryTintEnabled, mode == .discharging || mode == .underpowered {
            if percent <= 10 { return lowBatteryRed }
            if percent <= 20 { return lowBatteryYellow }
        }
        return color(for: mode)
    }

    /// Battery ring: 100–40 green, 40–25 yellow, 25–10 orange, 10–0 red.
    func batteryLevelFill(percent: Double) -> Color {
        switch percent {
        case 40...: charging
        case 25...: lowBatteryYellow
        case 10...: discharging
        default: lowBatteryRed
        }
    }

    /// CPU / GPU / memory: 0–60 green, 60–75 yellow, 75–90 orange, 90–100 red.
    func loadFill(percent: Double) -> Color {
        switch percent {
        case 90...: lowBatteryRed
        case 75...: discharging
        case 60...: lowBatteryYellow
        default: charging
        }
    }
}
