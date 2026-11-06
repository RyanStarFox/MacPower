import AppKit
import Foundation
import SwiftUI

enum MenuBarDigitPlacement: String, CaseIterable, Identifiable, Sendable {
    case none
    case inside
    case beside

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .none: "settings.icon.digits.none"
        case .inside: "settings.icon.digits.inside"
        case .beside: "settings.icon.digits.beside"
        }
    }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable, Sendable {
    case systemFill
    case systemPercentInside
    case classicBeside
    case outlineFill
    case outlinePercentInside
    case outlineClassicBeside

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .systemFill: "settings.icon.systemFill"
        case .systemPercentInside: "settings.icon.percentInside"
        case .classicBeside: "settings.icon.classic"
        case .outlineFill: "settings.icon.outlineFill"
        case .outlinePercentInside: "settings.icon.outlinePercentInside"
        case .outlineClassicBeside: "settings.icon.outlineClassic"
        }
    }

    var showsPercentInside: Bool { digits == .inside }
    var showsPercentBeside: Bool { digits == .beside }

    var isOutlined: Bool {
        switch self {
        case .outlineFill, .outlinePercentInside, .outlineClassicBeside: true
        default: false
        }
    }

    var digits: MenuBarDigitPlacement {
        switch self {
        case .systemFill, .outlineFill: .none
        case .systemPercentInside, .outlinePercentInside: .inside
        case .classicBeside, .outlineClassicBeside: .beside
        }
    }

    static func from(outlined: Bool, digits: MenuBarDigitPlacement) -> MenuBarIconStyle {
        switch (outlined, digits) {
        case (false, .none): .systemFill
        case (false, .inside): .systemPercentInside
        case (false, .beside): .classicBeside
        case (true, .none): .outlineFill
        case (true, .inside): .outlinePercentInside
        case (true, .beside): .outlineClassicBeside
        }
    }
}

enum MenuBarTintPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case systemDefault
    case defaultSlide
    case defaultGradient
    case defaultSlideGradient
    case off
    case batteryLevel
    case sunset
    case ocean
    case aurora
    case berry
    case amber
    case smoothLevel
    case lava
    case dawn
    case neon
    case custom
    case triColor

    var id: String { rawValue }

    static var pickerCases: [MenuBarTintPreset] {
        allCases.filter { $0 != .triColor }
    }

    var localizationKey: String {
        switch self {
        case .systemDefault: "settings.icon.tint.default"
        case .defaultSlide: "settings.icon.tint.defaultSlide"
        case .defaultGradient: "settings.icon.tint.defaultGradient"
        case .defaultSlideGradient: "settings.icon.tint.defaultSlideGradient"
        case .off: "settings.icon.tint.off"
        case .batteryLevel: "settings.icon.tint.level"
        case .sunset: "settings.icon.tint.sunset"
        case .ocean: "settings.icon.tint.ocean"
        case .aurora: "settings.icon.tint.aurora"
        case .berry: "settings.icon.tint.berry"
        case .amber: "settings.icon.tint.amber"
        case .smoothLevel: "settings.icon.tint.smooth"
        case .lava: "settings.icon.tint.lava"
        case .dawn: "settings.icon.tint.dawn"
        case .neon: "settings.icon.tint.neon"
        case .custom: "settings.icon.tint.custom"
        case .triColor: "settings.icon.tint.tri"
        }
    }
}

enum MenuBarTintMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case onBattery
    case always

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .onBattery: "settings.icon.tint.when.battery"
        case .always: "settings.icon.tint.when.always"
        }
    }
}

enum MenuBarTintSwatch: Codable, Equatable, Hashable, Sendable {
    case menuBar
    case systemRed
    case systemOrange
    case systemYellow
    case systemGreen
    case custom(red: Double, green: Double, blue: Double)

    var followsMenuBar: Bool {
        if case .menuBar = self { return true }
        return false
    }

    var color: Color {
        switch self {
        case .menuBar: Color.primary
        case .systemRed: Color.red
        case .systemOrange: Color.orange
        case .systemYellow: Color.yellow
        case .systemGreen: Color.green
        case .custom(let red, let green, let blue): Color(red: red, green: green, blue: blue)
        }
    }

    static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> MenuBarTintSwatch {
        .custom(red: red, green: green, blue: blue)
    }

    func nsColor(appearance: NSAppearance) -> NSColor {
        var resolved = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            switch self {
            case .menuBar: resolved = .black
            case .systemRed: resolved = .systemRed
            case .systemOrange: resolved = .systemOrange
            case .systemYellow: resolved = .systemYellow
            case .systemGreen: resolved = .systemGreen
            case .custom(let red, let green, let blue):
                resolved = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
            }
        }
        return resolved
    }

    /// Color used when drawing a non-template glyph. `.menuBar` resolves to the
    /// status-item label color for the current appearance so slides can track it
    /// instead of fading toward opaque black.
    func paintNSColor(appearance: NSAppearance) -> NSColor {
        guard followsMenuBar else { return nsColor(appearance: appearance) }
        var resolved = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            let label = NSColor.labelColor
            if let rgb = label.usingColorSpace(.sRGB) {
                resolved = NSColor(
                    srgbRed: rgb.redComponent,
                    green: rgb.greenComponent,
                    blue: rgb.blueComponent,
                    alpha: 1
                )
            } else {
                resolved = label
            }
        }
        return resolved
    }

    static func from(color: Color) -> MenuBarTintSwatch {
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return .custom(red: 0, green: 0, blue: 0) }
        return .custom(
            red: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent
        )
    }
}

enum MenuBarTintBlend: String, Codable, CaseIterable, Identifiable, Sendable {
    case constant
    case slide
    case gradient
    case slideGradient

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .constant: "settings.icon.tint.blend.constant"
        case .slide: "settings.icon.tint.blend.slide"
        case .gradient: "settings.icon.tint.blend.gradient"
        case .slideGradient: "settings.icon.tint.blend.both"
        }
    }

    var slides: Bool { self == .slide || self == .slideGradient }
    var gradient: Bool { self == .gradient || self == .slideGradient }
}

struct MenuBarResolvedFill: Equatable {
    var left: NSColor
    var right: NSColor
    var isTemplate: Bool

    static let template = MenuBarResolvedFill(left: .black, right: .black, isTemplate: true)

    func withAlpha(_ alpha: CGFloat) -> MenuBarResolvedFill {
        MenuBarResolvedFill(
            left: left.withAlphaComponent(alpha),
            right: right.withAlphaComponent(alpha),
            isTemplate: isTemplate
        )
    }
}

struct MenuBarTintBand: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var throughPercent: Int
    var blend: MenuBarTintBlend
    var highRight: MenuBarTintSwatch
    var highLeft: MenuBarTintSwatch
    var lowRight: MenuBarTintSwatch
    var lowLeft: MenuBarTintSwatch

    var swatch: MenuBarTintSwatch { highRight }

    init(
        id: UUID = UUID(),
        throughPercent: Int,
        swatch: MenuBarTintSwatch,
        blend: MenuBarTintBlend = .constant,
        highLeft: MenuBarTintSwatch? = nil,
        lowRight: MenuBarTintSwatch? = nil,
        lowLeft: MenuBarTintSwatch? = nil
    ) {
        self.id = id
        self.throughPercent = min(100, max(0, throughPercent))
        self.blend = blend
        self.highRight = swatch
        self.highLeft = highLeft ?? swatch
        self.lowRight = lowRight ?? swatch
        self.lowLeft = lowLeft ?? highLeft ?? swatch
    }

    enum CodingKeys: String, CodingKey {
        case id, throughPercent, swatch, blend, highRight, highLeft, lowRight, lowLeft
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        throughPercent = try container.decode(Int.self, forKey: .throughPercent)
        let legacy = try container.decodeIfPresent(MenuBarTintSwatch.self, forKey: .swatch)
        highRight = try container.decodeIfPresent(MenuBarTintSwatch.self, forKey: .highRight) ?? legacy ?? .systemGreen
        highLeft = try container.decodeIfPresent(MenuBarTintSwatch.self, forKey: .highLeft) ?? highRight
        lowRight = try container.decodeIfPresent(MenuBarTintSwatch.self, forKey: .lowRight) ?? highRight
        lowLeft = try container.decodeIfPresent(MenuBarTintSwatch.self, forKey: .lowLeft) ?? highLeft
        blend = try container.decodeIfPresent(MenuBarTintBlend.self, forKey: .blend) ?? .constant
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(throughPercent, forKey: .throughPercent)
        try container.encode(highRight, forKey: .swatch)
        try container.encode(blend, forKey: .blend)
        try container.encode(highRight, forKey: .highRight)
        try container.encode(highLeft, forKey: .highLeft)
        try container.encode(lowRight, forKey: .lowRight)
        try container.encode(lowLeft, forKey: .lowLeft)
    }
}

/// RGB mix only; the menu bar already redraws on integer percent (`MenuBarIconKey`),
/// so sliding never needs its own timer or TimelineView.
enum MenuBarTintMix {
    static func t(percent: Double, lower: Int, upper: Int) -> Double {
        let span = Double(max(1, upper - lower))
        return min(1, max(0, (percent - Double(lower)) / span))
    }

    static func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
        a + (b - a) * t
    }

    static func lerp(_ a: NSColor, _ b: NSColor, t: CGFloat) -> NSColor {
        let sa = a.usingColorSpace(.sRGB) ?? a
        let sb = b.usingColorSpace(.sRGB) ?? b
        return NSColor(
            srgbRed: sa.redComponent + (sb.redComponent - sa.redComponent) * t,
            green: sa.greenComponent + (sb.greenComponent - sa.greenComponent) * t,
            blue: sa.blueComponent + (sb.blueComponent - sa.blueComponent) * t,
            alpha: 1
        )
    }

    static func mix(_ a: MenuBarTintSwatch, _ b: MenuBarTintSwatch, t: Double) -> MenuBarTintSwatch {
        if a == b { return a }
        if t <= 0 { return a }
        if t >= 1 { return b }
        if a.followsMenuBar, b.followsMenuBar { return .menuBar }
        let ca = a.mixRGB
        let cb = b.mixRGB
        return .custom(
            red: lerp(ca.0, cb.0, t: t),
            green: lerp(ca.1, cb.1, t: t),
            blue: lerp(ca.2, cb.2, t: t)
        )
    }

    static func swatches(band: MenuBarTintBand, t: Double) -> (left: MenuBarTintSwatch, right: MenuBarTintSwatch) {
        switch band.blend {
        case .constant:
            return (band.highRight, band.highRight)
        case .slide:
            let mixed = mix(band.lowRight, band.highRight, t: t)
            return (mixed, mixed)
        case .gradient:
            return (band.highLeft, band.highRight)
        case .slideGradient:
            return (
                mix(band.lowLeft, band.highLeft, t: t),
                mix(band.lowRight, band.highRight, t: t)
            )
        }
    }
}

extension MenuBarTintSwatch {
    var mixRGB: (Double, Double, Double) {
        switch self {
        case .custom(let red, let green, let blue):
            return (red, green, blue)
        case .menuBar:
            // Approximate the light-mode menu-bar label for swatch mixing / tests.
            // Actual painting uses `paintNSColor(appearance:)` under the live appearance.
            return (0.0, 0.0, 0.0)
        default:
            guard let appearance = NSAppearance(named: .aqua),
                  let rgb = nsColor(appearance: appearance).usingColorSpace(.sRGB) else {
                return (0, 0, 0)
            }
            return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        }
    }
}

struct MenuBarTintScheme: Codable, Equatable, Sendable {
    var preset: MenuBarTintPreset
    var mode: MenuBarTintMode
    var bands: [MenuBarTintBand]

    static let systemDefault = MenuBarTintScheme(
        preset: .systemDefault,
        mode: .onBattery,
        bands: [
            MenuBarTintBand(throughPercent: 10, swatch: .systemRed),
            MenuBarTintBand(throughPercent: 20, swatch: .systemYellow),
            MenuBarTintBand(throughPercent: 100, swatch: .menuBar)
        ]
    )

    /// Same stops/colors as `systemDefault`, sliding inside each band.
    static let defaultSlide = MenuBarTintScheme(
        preset: .defaultSlide,
        mode: .onBattery,
        bands: [
            MenuBarTintBand(
                throughPercent: 10,
                swatch: .systemRed,
                blend: .slide,
                lowRight: .systemRed
            ),
            MenuBarTintBand(
                throughPercent: 20,
                swatch: .systemYellow,
                blend: .slide,
                lowRight: .systemRed
            ),
            MenuBarTintBand(
                throughPercent: 100,
                swatch: .menuBar,
                blend: .slide,
                lowRight: .systemYellow
            )
        ]
    )

    /// Same stops/colors as `systemDefault`, left→right gradient per band.
    static let defaultGradient = MenuBarTintScheme(
        preset: .defaultGradient,
        mode: .onBattery,
        bands: [
            MenuBarTintBand(
                throughPercent: 10,
                swatch: .systemYellow,
                blend: .gradient,
                highLeft: .systemRed
            ),
            MenuBarTintBand(
                throughPercent: 20,
                swatch: .menuBar,
                blend: .gradient,
                highLeft: .systemYellow
            ),
            MenuBarTintBand(
                throughPercent: 100,
                swatch: .menuBar,
                blend: .gradient,
                highLeft: .menuBar
            )
        ]
    )

    /// Same stops/colors as `systemDefault`, gradient that also slides with charge.
    static let defaultSlideGradient = MenuBarTintScheme(
        preset: .defaultSlideGradient,
        mode: .onBattery,
        bands: [
            MenuBarTintBand(
                throughPercent: 10,
                swatch: .systemRed,
                blend: .slideGradient,
                highLeft: .systemRed,
                lowRight: .systemRed,
                lowLeft: .systemRed
            ),
            MenuBarTintBand(
                throughPercent: 20,
                swatch: .systemYellow,
                blend: .slideGradient,
                highLeft: .systemRed,
                lowRight: .systemRed,
                lowLeft: .systemRed
            ),
            MenuBarTintBand(
                throughPercent: 100,
                swatch: .menuBar,
                blend: .slideGradient,
                highLeft: .systemYellow,
                lowRight: .systemYellow,
                lowLeft: .systemRed
            )
        ]
    )

    static let off = MenuBarTintScheme(preset: .off, mode: .onBattery, bands: [
        MenuBarTintBand(throughPercent: 100, swatch: .menuBar)
    ])

    static let batteryLevel = MenuBarTintScheme(
        preset: .batteryLevel,
        mode: .always,
        bands: [
            MenuBarTintBand(throughPercent: 10, swatch: .systemRed),
            MenuBarTintBand(throughPercent: 25, swatch: .systemOrange),
            MenuBarTintBand(throughPercent: 40, swatch: .systemYellow),
            MenuBarTintBand(throughPercent: 100, swatch: .systemGreen)
        ]
    )

    static let sunset = MenuBarTintScheme(
        preset: .sunset,
        mode: .always,
        bands: [
            MenuBarTintBand(throughPercent: 15, swatch: .rgb(0.78, 0.12, 0.28)),
            MenuBarTintBand(throughPercent: 35, swatch: .rgb(0.95, 0.38, 0.22)),
            MenuBarTintBand(throughPercent: 65, swatch: .rgb(0.96, 0.62, 0.18)),
            MenuBarTintBand(throughPercent: 100, swatch: .rgb(0.98, 0.80, 0.52))
        ]
    )

    static let ocean = MenuBarTintScheme(
        preset: .ocean,
        mode: .always,
        bands: [
            MenuBarTintBand(throughPercent: 15, swatch: .rgb(0.10, 0.18, 0.48)),
            MenuBarTintBand(throughPercent: 40, swatch: .rgb(0.16, 0.42, 0.88)),
            MenuBarTintBand(throughPercent: 70, swatch: .rgb(0.12, 0.70, 0.78)),
            MenuBarTintBand(throughPercent: 100, swatch: .rgb(0.42, 0.86, 0.84))
        ]
    )

    static let aurora = MenuBarTintScheme(
        preset: .aurora,
        mode: .always,
        bands: [
            MenuBarTintBand(throughPercent: 20, swatch: .rgb(0.48, 0.22, 0.88)),
            MenuBarTintBand(throughPercent: 45, swatch: .rgb(0.18, 0.78, 0.90)),
            MenuBarTintBand(throughPercent: 75, swatch: .rgb(0.28, 0.90, 0.58)),
            MenuBarTintBand(throughPercent: 100, swatch: .rgb(0.62, 0.95, 0.72))
        ]
    )

    static let berry = MenuBarTintScheme(
        preset: .berry,
        mode: .always,
        bands: [
            MenuBarTintBand(throughPercent: 15, swatch: .rgb(0.46, 0.10, 0.36)),
            MenuBarTintBand(throughPercent: 40, swatch: .rgb(0.80, 0.18, 0.48)),
            MenuBarTintBand(throughPercent: 70, swatch: .rgb(0.94, 0.40, 0.60)),
            MenuBarTintBand(throughPercent: 100, swatch: .rgb(0.98, 0.70, 0.80))
        ]
    )

    static let amber = MenuBarTintScheme(
        preset: .amber,
        mode: .always,
        bands: [
            MenuBarTintBand(throughPercent: 15, swatch: .rgb(0.72, 0.10, 0.06)),
            MenuBarTintBand(throughPercent: 45, swatch: .rgb(0.94, 0.46, 0.08)),
            MenuBarTintBand(throughPercent: 100, swatch: .rgb(0.98, 0.76, 0.16))
        ]
    )

    static let smoothLevel = MenuBarTintScheme(
        preset: .smoothLevel,
        mode: .always,
        bands: [
            MenuBarTintBand(
                throughPercent: 20,
                swatch: .systemOrange,
                blend: .slide,
                lowRight: .systemRed
            ),
            MenuBarTintBand(
                throughPercent: 55,
                swatch: .systemYellow,
                blend: .slide,
                lowRight: .systemOrange
            ),
            MenuBarTintBand(
                throughPercent: 100,
                swatch: .systemGreen,
                blend: .slide,
                lowRight: .systemYellow
            )
        ]
    )

    static let lava = MenuBarTintScheme(
        preset: .lava,
        mode: .always,
        bands: [
            MenuBarTintBand(
                throughPercent: 100,
                swatch: .rgb(0.98, 0.62, 0.12),
                blend: .gradient,
                highLeft: .rgb(0.55, 0.06, 0.04)
            )
        ]
    )

    static let dawn = MenuBarTintScheme(
        preset: .dawn,
        mode: .always,
        bands: [
            MenuBarTintBand(
                throughPercent: 45,
                swatch: .rgb(0.96, 0.58, 0.22),
                blend: .slideGradient,
                highLeft: .rgb(0.92, 0.28, 0.38),
                lowRight: .rgb(0.55, 0.12, 0.48),
                lowLeft: .rgb(0.28, 0.08, 0.42)
            ),
            MenuBarTintBand(
                throughPercent: 100,
                swatch: .rgb(0.98, 0.86, 0.58),
                blend: .slideGradient,
                highLeft: .rgb(0.98, 0.72, 0.38),
                lowRight: .rgb(0.96, 0.58, 0.22),
                lowLeft: .rgb(0.92, 0.28, 0.38)
            )
        ]
    )

    static let neon = MenuBarTintScheme(
        preset: .neon,
        mode: .always,
        bands: [
            MenuBarTintBand(
                throughPercent: 50,
                swatch: .rgb(0.12, 0.92, 0.95),
                blend: .slide,
                lowRight: .rgb(0.92, 0.12, 0.78)
            ),
            MenuBarTintBand(
                throughPercent: 100,
                swatch: .rgb(0.55, 0.98, 0.22),
                blend: .slide,
                lowRight: .rgb(0.12, 0.92, 0.95)
            )
        ]
    )

    static func preset(_ preset: MenuBarTintPreset) -> MenuBarTintScheme {
        switch preset {
        case .systemDefault: .systemDefault
        case .defaultSlide: .defaultSlide
        case .defaultGradient: .defaultGradient
        case .defaultSlideGradient: .defaultSlideGradient
        case .off: .off
        case .batteryLevel, .triColor: .batteryLevel
        case .sunset: .sunset
        case .ocean: .ocean
        case .aurora: .aurora
        case .berry: .berry
        case .amber: .amber
        case .smoothLevel: .smoothLevel
        case .lava: .lava
        case .dawn: .dawn
        case .neon: .neon
        case .custom: .systemDefault.markedCustom()
        }
    }

    var isEditable: Bool { preset != .off }

    var sortedBands: [MenuBarTintBand] {
        bands.sorted { $0.throughPercent < $1.throughPercent }
    }

    func markedCustom() -> MenuBarTintScheme {
        var copy = self
        copy.preset = .custom
        return copy
    }

    func swatch(percent: Double, flowMode: EnergyFlowMode) -> MenuBarTintSwatch {
        fillSwatches(percent: percent, flowMode: flowMode).right
    }

    func fill(percent: Double, flowMode: EnergyFlowMode, appearance: NSAppearance, lowPowerMode: Bool = false) -> MenuBarResolvedFill {
        if preset == .off { return .template }
        if lowPowerMode {
            var configured = self
            configured.mode = .always
            let chosen = configured.fill(percent: percent, flowMode: flowMode, appearance: appearance)
            if !chosen.isTemplate { return chosen }
            let yellow = MenuBarTintSwatch.systemYellow.paintNSColor(appearance: appearance)
            return MenuBarResolvedFill(left: yellow, right: yellow, isTemplate: false)
        }
        if mode == .onBattery, flowMode != .discharging, flowMode != .underpowered {
            return .template
        }
        let value = Double(Int(min(100, max(0, percent)).rounded(.towardZero)))
        let ordered = sortedBands
        guard let index = ordered.firstIndex(where: { value <= Double($0.throughPercent) }) else {
            let last = ordered.last?.highRight ?? .menuBar
            if last.followsMenuBar { return .template }
            let color = last.paintNSColor(appearance: appearance)
            return MenuBarResolvedFill(left: color, right: color, isTemplate: false)
        }
        let band = ordered[index]
        let lower = index == 0 ? 0 : ordered[index - 1].throughPercent
        let t = CGFloat(MenuBarTintMix.t(percent: value, lower: lower, upper: band.throughPercent))
        func paint(_ swatch: MenuBarTintSwatch) -> NSColor {
            swatch.paintNSColor(appearance: appearance)
        }
        switch band.blend {
        case .constant:
            if band.highRight.followsMenuBar { return .template }
            let c = paint(band.highRight)
            return MenuBarResolvedFill(left: c, right: c, isTemplate: false)
        case .slide:
            if band.lowRight.followsMenuBar, band.highRight.followsMenuBar { return .template }
            if t >= 1, band.highRight.followsMenuBar { return .template }
            if t <= 0, band.lowRight.followsMenuBar { return .template }
            let c = MenuBarTintMix.lerp(paint(band.lowRight), paint(band.highRight), t: t)
            return MenuBarResolvedFill(left: c, right: c, isTemplate: false)
        case .gradient:
            if band.highLeft.followsMenuBar, band.highRight.followsMenuBar { return .template }
            return MenuBarResolvedFill(left: paint(band.highLeft), right: paint(band.highRight), isTemplate: false)
        case .slideGradient:
            if band.lowLeft.followsMenuBar, band.highLeft.followsMenuBar,
               band.lowRight.followsMenuBar, band.highRight.followsMenuBar {
                return .template
            }
            let leftFollows = (t >= 1 && band.highLeft.followsMenuBar) || (t <= 0 && band.lowLeft.followsMenuBar)
            let rightFollows = (t >= 1 && band.highRight.followsMenuBar) || (t <= 0 && band.lowRight.followsMenuBar)
            if leftFollows, rightFollows { return .template }
            return MenuBarResolvedFill(
                left: MenuBarTintMix.lerp(paint(band.lowLeft), paint(band.highLeft), t: t),
                right: MenuBarTintMix.lerp(paint(band.lowRight), paint(band.highRight), t: t),
                isTemplate: false
            )
        }
    }

    func fillSwatches(percent: Double, flowMode: EnergyFlowMode) -> (left: MenuBarTintSwatch, right: MenuBarTintSwatch) {
        if preset == .off { return (.menuBar, .menuBar) }
        if mode == .onBattery, flowMode != .discharging, flowMode != .underpowered {
            return (.menuBar, .menuBar)
        }
        let value = Double(Int(min(100, max(0, percent)).rounded(.towardZero)))
        let ordered = sortedBands
        guard let index = ordered.firstIndex(where: { value <= Double($0.throughPercent) }) else {
            let last = ordered.last?.highRight ?? .menuBar
            return (last, last)
        }
        let band = ordered[index]
        let lower = index == 0 ? 0 : ordered[index - 1].throughPercent
        let t = MenuBarTintMix.t(percent: value, lower: lower, upper: band.throughPercent)
        return MenuBarTintMix.swatches(band: band, t: t)
    }

    func replacingBand(
        id: UUID,
        throughPercent: Int? = nil,
        swatch: MenuBarTintSwatch? = nil,
        blend: MenuBarTintBlend? = nil,
        highRight: MenuBarTintSwatch? = nil,
        highLeft: MenuBarTintSwatch? = nil,
        lowRight: MenuBarTintSwatch? = nil,
        lowLeft: MenuBarTintSwatch? = nil
    ) -> MenuBarTintScheme {
        var copy = markedCustom()
        copy.bands = copy.bands.map { band in
            guard band.id == id else { return band }
            var next = band
            if let throughPercent { next.throughPercent = throughPercent }
            if let blend { next.blend = blend }
            if let swatch {
                next.highRight = swatch
                if next.blend == .constant {
                    next.highLeft = swatch
                    next.lowRight = swatch
                    next.lowLeft = swatch
                }
            }
            if let highRight { next.highRight = highRight }
            if let highLeft { next.highLeft = highLeft }
            if let lowRight { next.lowRight = lowRight }
            if let lowLeft { next.lowLeft = lowLeft }
            return next
        }
        return copy.normalized()
    }

    func removingBand(id: UUID) -> MenuBarTintScheme {
        guard bands.count > 1 else { return markedCustom() }
        var copy = markedCustom()
        copy.bands.removeAll { $0.id == id }
        return copy.normalized()
    }

    func addingBand() -> MenuBarTintScheme {
        guard bands.count < 8 else { return markedCustom() }
        var copy = markedCustom()
        let ordered = sortedBands
        let last = ordered.last?.throughPercent ?? 100
        let previous = ordered.dropLast().last?.throughPercent ?? 0
        let inserted = max(previous + 1, min(last - 1, (previous + last) / 2))
        copy.bands.append(MenuBarTintBand(throughPercent: inserted, swatch: .systemGreen))
        return copy.normalized()
    }

    func normalized() -> MenuBarTintScheme {
        if preset == .triColor {
            return Self.batteryLevel
        }
        var copy = self
        var ordered = sortedBands
        if ordered.isEmpty {
            ordered = [MenuBarTintBand(throughPercent: 100, swatch: .menuBar)]
        }
        var unique: [MenuBarTintBand] = []
        var seen = Set<Int>()
        for band in ordered {
            var next = band
            if seen.contains(next.throughPercent) {
                next.throughPercent = min(100, next.throughPercent + 1)
            }
            seen.insert(next.throughPercent)
            unique.append(next)
        }
        unique[unique.count - 1].throughPercent = 100
        copy.bands = unique
        return copy
    }

    func percentRange(for id: UUID) -> ClosedRange<Int> {
        let ordered = sortedBands
        guard let index = ordered.firstIndex(where: { $0.id == id }) else { return 1...100 }
        if index == ordered.count - 1 { return 100...100 }
        let lower = index == 0 ? 1 : ordered[index - 1].throughPercent + 1
        let upper = ordered[index + 1].throughPercent - 1
        if lower > upper { return upper...upper }
        return lower...upper
    }
}

enum MenuBarTintPercentInput {
    static func commit(_ raw: String, range: ClosedRange<Int>, fallback: Int) -> Int {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return fallback }
        text = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        text = text.replacingOccurrences(of: " ", with: "")
        text = text.replacingOccurrences(of: "％", with: "%")
        for prefix in ["≤", "<=", "<"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if text.hasSuffix("%") {
            text.removeLast()
        }
        let sign = text.hasPrefix("-") ? "-" : ""
        let digits = (sign.isEmpty ? text : String(text.dropFirst())).prefix { $0.isNumber }
        guard let value = Int(sign + digits), !digits.isEmpty else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
