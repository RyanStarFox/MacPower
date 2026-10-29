import AppKit
import Foundation
import SwiftUI

/// Percent-banded tint without menu-bar on-battery gating.
struct ValueTintScheme: Codable, Equatable, Sendable {
    var bands: [MenuBarTintBand]

    var sortedBands: [MenuBarTintBand] {
        bands.sorted { $0.throughPercent < $1.throughPercent }
    }

    func fillSwatches(percent: Double) -> (left: MenuBarTintSwatch, right: MenuBarTintSwatch) {
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

    func colors(percent: Double) -> (left: Color, right: Color) {
        let pair = fillSwatches(percent: percent)
        return (pair.left.color, pair.right.color)
    }

    func replacingBand(
        id: UUID,
        throughPercent: Int? = nil,
        blend: MenuBarTintBlend? = nil,
        highRight: MenuBarTintSwatch? = nil,
        highLeft: MenuBarTintSwatch? = nil,
        lowRight: MenuBarTintSwatch? = nil,
        lowLeft: MenuBarTintSwatch? = nil,
        swatch: MenuBarTintSwatch? = nil
    ) -> ValueTintScheme {
        var copy = self
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

    func replacingBand(at index: Int, mutate: (inout MenuBarTintBand) -> Void) -> ValueTintScheme {
        var ordered = sortedBands
        guard ordered.indices.contains(index) else { return self }
        mutate(&ordered[index])
        var copy = self
        copy.bands = ordered
        return copy.normalized()
    }

    func removingBand(id: UUID) -> ValueTintScheme {
        guard bands.count > 1 else { return self }
        var copy = self
        copy.bands.removeAll { $0.id == id }
        return copy.normalized()
    }

    func removingBand(at index: Int) -> ValueTintScheme {
        var ordered = sortedBands
        guard ordered.count > 1, ordered.indices.contains(index) else { return self }
        ordered.remove(at: index)
        var copy = self
        copy.bands = ordered
        return copy.normalized()
    }

    func addingBand() -> ValueTintScheme {
        guard bands.count < 8 else { return self }
        var copy = self
        let ordered = sortedBands
        let last = ordered.last?.throughPercent ?? 100
        let previous = ordered.dropLast().last?.throughPercent ?? 0
        let inserted = max(previous + 1, min(last - 1, (previous + last) / 2))
        copy.bands.append(MenuBarTintBand(throughPercent: inserted, swatch: .systemGreen))
        return copy.normalized()
    }

    func normalized() -> ValueTintScheme {
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
        var copy = self
        copy.bands = unique
        return copy
    }

    func percentRange(for id: UUID) -> ClosedRange<Int> {
        let ordered = sortedBands
        guard let index = ordered.firstIndex(where: { $0.id == id }) else { return 1...100 }
        return percentRange(at: index)
    }

    func percentRange(at index: Int) -> ClosedRange<Int> {
        let ordered = sortedBands
        guard ordered.indices.contains(index) else { return 1...100 }
        if index == ordered.count - 1 { return 100...100 }
        let lower = index == 0 ? 1 : ordered[index - 1].throughPercent + 1
        let upper = ordered[index + 1].throughPercent - 1
        if lower > upper { return upper...upper }
        return lower...upper
    }

    func replacingStops(_ old: [Int], with newStops: [Int]) -> ValueTintScheme {
        let ordered = sortedBands
        guard ordered.map(\.throughPercent) == old, old.count == newStops.count else { return self }
        var copy = self
        copy.bands = zip(ordered, newStops).map { band, stop in
            var next = band
            next.throughPercent = stop
            return next
        }
        return copy.normalized()
    }

    static func constant(_ swatch: MenuBarTintSwatch) -> ValueTintScheme {
        ValueTintScheme(bands: [MenuBarTintBand(throughPercent: 100, swatch: swatch)])
    }

    /// Download ring: blue on the left, lighter blue on the right.
    static let downloadSpeed = ValueTintScheme(bands: [
        MenuBarTintBand(
            throughPercent: 100,
            swatch: .from(color: Color(red: 0.45, green: 0.84, blue: 1)),
            blend: .gradient,
            highLeft: .from(color: Color(red: 0.27, green: 0.58, blue: 0.98))
        )
    ])

    /// Upload ring: orange on the left, lighter orange on the right.
    static let uploadSpeed = ValueTintScheme(bands: [
        MenuBarTintBand(
            throughPercent: 100,
            swatch: .from(color: Color(red: 1, green: 0.78, blue: 0.38)),
            blend: .gradient,
            highLeft: .from(color: Color(red: 0.98, green: 0.58, blue: 0.24))
        )
    ])

    /// Battery ring defaults: ≤10 red, ≤25 orange, ≤40 yellow, else green.
    static func batteryLevel(red: MenuBarTintSwatch, orange: MenuBarTintSwatch, yellow: MenuBarTintSwatch, green: MenuBarTintSwatch) -> ValueTintScheme {
        ValueTintScheme(bands: [
            MenuBarTintBand(throughPercent: 10, swatch: red),
            MenuBarTintBand(throughPercent: 25, swatch: orange),
            MenuBarTintBand(throughPercent: 40, swatch: yellow),
            MenuBarTintBand(throughPercent: 100, swatch: green)
        ]).normalized()
    }

    /// Load ring defaults: ≤60 green, ≤75 yellow, ≤90 orange, else red.
    static func loadLevel(green: MenuBarTintSwatch, yellow: MenuBarTintSwatch, orange: MenuBarTintSwatch, red: MenuBarTintSwatch) -> ValueTintScheme {
        ValueTintScheme(bands: [
            MenuBarTintBand(throughPercent: 60, swatch: green),
            MenuBarTintBand(throughPercent: 75, swatch: yellow),
            MenuBarTintBand(throughPercent: 90, swatch: orange),
            MenuBarTintBand(throughPercent: 100, swatch: red)
        ]).normalized()
    }

    /// Showcase: slide through battery stops.
    static let slidingBattery = ValueTintScheme(bands: [
        MenuBarTintBand(throughPercent: 10, swatch: .systemRed, blend: .slide, lowRight: .systemRed),
        MenuBarTintBand(throughPercent: 25, swatch: .systemOrange, blend: .slide, lowRight: .systemRed),
        MenuBarTintBand(throughPercent: 40, swatch: .systemYellow, blend: .slide, lowRight: .systemOrange),
        MenuBarTintBand(throughPercent: 100, swatch: .systemGreen, blend: .slide, lowRight: .systemYellow)
    ]).normalized()

    static let slidingLoad = ValueTintScheme(bands: [
        MenuBarTintBand(throughPercent: 60, swatch: .systemGreen, blend: .slide, lowRight: .systemGreen),
        MenuBarTintBand(throughPercent: 75, swatch: .systemYellow, blend: .slide, lowRight: .systemGreen),
        MenuBarTintBand(throughPercent: 90, swatch: .systemOrange, blend: .slide, lowRight: .systemYellow),
        MenuBarTintBand(throughPercent: 100, swatch: .systemRed, blend: .slide, lowRight: .systemOrange)
    ]).normalized()

    /// Showcase: circumferential / left-right gradient on each band.
    static let gradientBattery = ValueTintScheme(bands: [
        MenuBarTintBand(
            throughPercent: 100,
            swatch: .systemGreen,
            blend: .gradient,
            highLeft: .systemRed
        )
    ]).normalized()

    static let gradientLoad = ValueTintScheme(bands: [
        MenuBarTintBand(
            throughPercent: 100,
            swatch: .systemRed,
            blend: .gradient,
            highLeft: .systemGreen
        )
    ]).normalized()

    /// Showcase: gradient that also slides with the value.
    static let glideBattery = ValueTintScheme(bands: [
        MenuBarTintBand(
            throughPercent: 40,
            swatch: .systemOrange,
            blend: .slideGradient,
            highLeft: .systemRed,
            lowRight: .systemRed,
            lowLeft: .systemRed
        ),
        MenuBarTintBand(
            throughPercent: 100,
            swatch: .systemGreen,
            blend: .slideGradient,
            highLeft: .systemYellow,
            lowRight: .systemOrange,
            lowLeft: .systemRed
        )
    ]).normalized()

    static let glideLoad = ValueTintScheme(bands: [
        MenuBarTintBand(
            throughPercent: 60,
            swatch: .systemYellow,
            blend: .slideGradient,
            highLeft: .systemGreen,
            lowRight: .systemGreen,
            lowLeft: .systemGreen
        ),
        MenuBarTintBand(
            throughPercent: 100,
            swatch: .systemRed,
            blend: .slideGradient,
            highLeft: .systemOrange,
            lowRight: .systemYellow,
            lowLeft: .systemGreen
        )
    ]).normalized()
}

enum RingKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case battery, cpu, gpu, memory, disk, memoryPressure, swap

    var id: String { rawValue }

    /// Kinds whose glyph can be edited. Extra rings keep the memory glyph.
    static let customizable: [RingKind] = [.battery, .cpu, .gpu, .memory]

    var localizationKey: String {
        switch self {
        case .battery: "ring.battery"
        case .cpu: "ring.cpu"
        case .gpu: "ring.gpu"
        case .memory: "ring.memory"
        case .disk: "ring.disk"
        case .memoryPressure: "ring.pressure"
        case .swap: "ring.swap"
        }
    }

    var captionKey: String {
        switch self {
        case .battery: "ring.caption.battery %lld"
        case .cpu: "ring.caption.cpu %lld"
        case .gpu: "ring.caption.gpu %lld"
        case .memory: "ring.caption.memory %lld"
        case .disk: "ring.caption.disk %lld"
        case .memoryPressure: "ring.caption.pressure %lld"
        case .swap: "ring.caption.swap %lld"
        }
    }
}

enum RingOddRow: String, CaseIterable, Identifiable, Sendable {
    case stagger
    case align

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .stagger: "settings.rings.oddStagger"
        case .align: "settings.rings.oddAlign"
        }
    }
}

enum RingSlot: String, CaseIterable, Identifiable, Codable, Sendable {
    case battery, cpu, gpu, memory, disk, memoryPressure, swap, download, upload, speedPair

    var id: String { rawValue }

    var metric: RingKind? { RingKind(rawValue: rawValue) }

    var localizationKey: String {
        switch self {
        case .download: "settings.rings.download"
        case .upload: "settings.rings.upload"
        case .speedPair: "settings.rings.speedPair"
        default: metric?.localizationKey ?? rawValue
        }
    }
}

enum PopoverTintPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case semantic
    case system
    case highContrast
    case glassMono
    case smooth
    case gradient
    case glide
    case custom

    var id: String { rawValue }

    static var pickerCases: [PopoverTintPreset] {
        allCases
    }

    var localizationKey: String {
        switch self {
        case .semantic: "settings.palette.semantic"
        case .system: "settings.palette.system"
        case .highContrast: "settings.palette.highContrast"
        case .glassMono: "settings.palette.glassMono"
        case .smooth: "settings.popover.tint.smooth"
        case .gradient: "settings.popover.tint.gradient"
        case .glide: "settings.popover.tint.glide"
        case .custom: "settings.icon.tint.custom"
        }
    }

    init(palette: ThemePalette) {
        switch palette {
        case .semantic: self = .semantic
        case .system: self = .system
        case .highContrast: self = .highContrast
        case .glassMono: self = .glassMono
        }
    }

    var themePalette: ThemePalette? {
        switch self {
        case .semantic: .semantic
        case .system: .system
        case .highContrast: .highContrast
        case .glassMono: .glassMono
        case .smooth, .gradient, .glide, .custom: nil
        }
    }
}

/// One reusable ring color. A solid, a slide, a gradient, and a sliding gradient are all one scheme.
struct RingColor: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var scheme: ValueTintScheme
}

/// Which catalog color a ring segment paints with.
enum RingColorSegment: String, Codable, CaseIterable, Identifiable, Sendable {
    case battery, cpu, gpu, memory, disk, memoryPressure, swap, download, upload

    var id: String { rawValue }

    init(_ kind: RingKind) {
        self = RingColorSegment(rawValue: kind.rawValue) ?? .memory
    }

    var localizationKey: String {
        switch self {
        case .battery: "ring.battery"
        case .cpu: "ring.cpu"
        case .gpu: "ring.gpu"
        case .memory: "ring.memory"
        case .disk: "ring.disk"
        case .memoryPressure: "ring.pressure"
        case .swap: "ring.swap"
        case .download: "settings.rings.download"
        case .upload: "settings.rings.upload"
        }
    }
}

struct RingTintSettings: Codable, Equatable, Sendable {
    var preset: PopoverTintPreset
    /// Color catalog. Several segments may share one entry.
    var colors: [RingColor]
    /// Segment → `colors` id.
    var assignments: [RingColorSegment: UUID]

    static let semantic = RingTintSettings.preset(.semantic)
    static let system = RingTintSettings.preset(.system)
    static let highContrast = RingTintSettings.preset(.highContrast)
    static let glassMono = RingTintSettings.preset(.glassMono)
    static let smooth = RingTintSettings.preset(.smooth)
    static let gradient = RingTintSettings.preset(.gradient)
    static let glide = RingTintSettings.preset(.glide)

    private static let editableSegments: [RingColorSegment] = [.battery, .cpu, .gpu, .memory]
    private static let memoryFollowers: [RingColorSegment] = [.disk, .memoryPressure, .swap]

    var battery: ValueTintScheme { scheme(forSegment: .battery) }
    var cpu: ValueTintScheme { scheme(forSegment: .cpu) }
    var gpu: ValueTintScheme { scheme(forSegment: .gpu) }
    var memory: ValueTintScheme { scheme(forSegment: .memory) }

    static func preset(_ preset: PopoverTintPreset) -> RingTintSettings {
        switch preset {
        case .custom:
            return semantic.markedCustom()
        case .semantic, .system, .highContrast, .glassMono:
            let theme = AppTheme.resolved(palette: preset.themePalette!, colorScheme: .light)
            let red = MenuBarTintSwatch.from(color: theme.lowBatteryRed)
            let orange = MenuBarTintSwatch.from(color: theme.discharging)
            let yellow = MenuBarTintSwatch.from(color: theme.lowBatteryYellow)
            let green = MenuBarTintSwatch.from(color: theme.charging)
            let battery = ValueTintScheme.batteryLevel(red: red, orange: orange, yellow: yellow, green: green)
            let load = ValueTintScheme.loadLevel(green: green, yellow: yellow, orange: orange, red: red)
            return RingTintSettings(preset: preset, battery: battery, cpu: load, gpu: load, memory: load)
        case .smooth:
            return RingTintSettings(
                preset: .smooth,
                battery: .slidingBattery,
                cpu: .slidingLoad,
                gpu: .slidingLoad,
                memory: .slidingLoad
            )
        case .gradient:
            return RingTintSettings(
                preset: .gradient,
                battery: .gradientBattery,
                cpu: .gradientLoad,
                gpu: .gradientLoad,
                memory: .gradientLoad
            )
        case .glide:
            return RingTintSettings(
                preset: .glide,
                battery: .glideBattery,
                cpu: .glideLoad,
                gpu: .glideLoad,
                memory: .glideLoad
            )
        }
    }

    init(
        preset: PopoverTintPreset,
        battery: ValueTintScheme,
        cpu: ValueTintScheme,
        gpu: ValueTintScheme,
        memory: ValueTintScheme,
        download: ValueTintScheme = .downloadSpeed,
        upload: ValueTintScheme = .uploadSpeed
    ) {
        self.preset = preset
        var colors: [RingColor] = []
        func adopt(_ scheme: ValueTintScheme) -> UUID {
            let normalized = scheme.normalized()
            if let existing = colors.first(where: { $0.scheme == normalized }) {
                return existing.id
            }
            let id = UUID()
            colors.append(RingColor(id: id, scheme: normalized))
            return id
        }
        let batteryID = adopt(battery)
        let cpuID = adopt(cpu)
        let gpuID = adopt(gpu)
        let memoryID = adopt(memory)
        let downloadID = adopt(download)
        let uploadID = adopt(upload)
        self.colors = colors
        assignments = [
            .battery: batteryID,
            .cpu: cpuID,
            .gpu: gpuID,
            .memory: memoryID,
            .disk: memoryID,
            .memoryPressure: memoryID,
            .swap: memoryID,
            .download: downloadID,
            .upload: uploadID,
        ]
    }

    func scheme(for kind: RingKind) -> ValueTintScheme {
        scheme(forSegment: RingColorSegment(kind))
    }

    func scheme(forSegment segment: RingColorSegment) -> ValueTintScheme {
        if let id = assignments[segment], let color = colors.first(where: { $0.id == id }) {
            return color.scheme
        }
        return colors.first?.scheme ?? .constant(.systemGreen)
    }

    func markedCustom() -> RingTintSettings {
        var copy = self
        copy.preset = .custom
        return copy
    }

    func replacing(_ kind: RingKind, with scheme: ValueTintScheme) -> RingTintSettings {
        var copy = markedCustom()
        let segment = RingColorSegment(kind)
        let followers = segment == .memory ? Self.memoryFollowers : []
        copy.write(scheme.normalized(), to: segment, followers: followers)
        return copy
    }

    func replacingAll(with scheme: ValueTintScheme) -> RingTintSettings {
        var copy = markedCustom()
        let id = UUID()
        copy.colors.append(RingColor(id: id, scheme: scheme.normalized()))
        for segment in Self.editableSegments + Self.memoryFollowers {
            copy.assignments[segment] = id
        }
        copy.pruneUnusedColors()
        return copy
    }

    /// Transforms each catalog color used by the battery, CPU, GPU, or memory segment once.
    /// Shared segments stay shared.
    func mapAll(_ transform: (ValueTintScheme) -> ValueTintScheme) -> RingTintSettings {
        var copy = markedCustom()
        let ids = Set(Self.editableSegments.compactMap { copy.assignments[$0] })
        copy.colors = copy.colors.map { color in
            guard ids.contains(color.id) else { return color }
            var next = color
            next.scheme = transform(color.scheme).normalized()
            return next
        }
        return copy
    }

    var allSchemes: [ValueTintScheme] { [battery, cpu, gpu, memory] }

    /// Edits one catalog entry. Every segment pointing at it changes together.
    func updatingColor(id: UUID, scheme: ValueTintScheme) -> RingTintSettings {
        var copy = markedCustom()
        guard let index = copy.colors.firstIndex(where: { $0.id == id }) else { return self }
        copy.colors[index].scheme = scheme.normalized()
        return copy
    }

    func assigning(_ segment: RingColorSegment, to colorID: UUID) -> RingTintSettings {
        guard colors.contains(where: { $0.id == colorID }) else { return self }
        var copy = markedCustom()
        copy.assignments[segment] = colorID
        return copy
    }

    /// Appends a copy of `sourceID`, or of the last color. The copy stays unused until a segment selects it.
    func addingColor(copying sourceID: UUID?) -> RingTintSettings {
        var copy = markedCustom()
        let source = copy.colors.first(where: { $0.id == sourceID }) ?? copy.colors.last
        let scheme = source?.scheme ?? .constant(.systemGreen)
        copy.colors.append(RingColor(id: UUID(), scheme: scheme))
        return copy
    }

    /// Drops a catalog entry. Segments that used it move to another remaining color.
    func removingColor(id: UUID) -> RingTintSettings {
        guard colors.count > 1, let fallback = colors.first(where: { $0.id != id }) else { return self }
        var copy = markedCustom()
        for segment in RingColorSegment.allCases where copy.assignments[segment] == id {
            copy.assignments[segment] = fallback.id
        }
        copy.colors.removeAll { $0.id == id }
        return copy
    }

    /// Older defaults used 9/24/39 and 59/74/89 so `<=` matched half-open AppTheme bands.
    /// Remap those exact stop lists to round fives without touching custom schemes.
    func withRoundedDefaultStops() -> RingTintSettings {
        var copy = self
        copy.colors = colors.map { color in
            var next = color
            next.scheme = color.scheme
                .replacingStops([9, 24, 39, 100], with: [10, 25, 40, 100])
                .replacingStops([59, 74, 89, 100], with: [60, 75, 90, 100])
            return next
        }
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case preset, colors, assignments
        case battery, cpu, gpu, memory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preset = try container.decode(PopoverTintPreset.self, forKey: .preset)
        if container.contains(.colors) {
            var migrated = RingTintSettings(
                preset: preset,
                colors: try container.decode([RingColor].self, forKey: .colors),
                assignments: try container.decode([RingColorSegment: UUID].self, forKey: .assignments)
            )
            migrated.ensureSegments()
            self = migrated
            return
        }
        let battery = try container.decode(ValueTintScheme.self, forKey: .battery)
        let cpu = try container.decode(ValueTintScheme.self, forKey: .cpu)
        let gpu = try container.decode(ValueTintScheme.self, forKey: .gpu)
        let memory = try container.decode(ValueTintScheme.self, forKey: .memory)
        self.init(preset: preset, battery: battery, cpu: cpu, gpu: gpu, memory: memory)
    }

    private init(preset: PopoverTintPreset, colors: [RingColor], assignments: [RingColorSegment: UUID]) {
        self.preset = preset
        self.colors = colors
        self.assignments = assignments
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset, forKey: .preset)
        try container.encode(colors, forKey: .colors)
        try container.encode(assignments, forKey: .assignments)
    }

    /// Fills segments missing from an older catalog. Disk, pressure, and swap follow memory.
    private mutating func ensureSegments() {
        if colors.isEmpty {
            let id = UUID()
            colors = [RingColor(id: id, scheme: .constant(.systemGreen))]
        }
        func resolved(_ segment: RingColorSegment, fallback: UUID) -> UUID {
            if let id = assignments[segment], colors.contains(where: { $0.id == id }) {
                return id
            }
            return fallback
        }
        let fallback = colors[0].id
        let batteryID = resolved(.battery, fallback: fallback)
        let cpuID = resolved(.cpu, fallback: batteryID)
        let gpuID = resolved(.gpu, fallback: cpuID)
        let memoryID = resolved(.memory, fallback: cpuID)
        assignments[.battery] = batteryID
        assignments[.cpu] = cpuID
        assignments[.gpu] = gpuID
        assignments[.memory] = memoryID
        for follower in Self.memoryFollowers {
            assignments[follower] = resolved(follower, fallback: memoryID)
        }
        if let downloadID = assignments[.download], colors.contains(where: { $0.id == downloadID }) {
            assignments[.download] = downloadID
        } else {
            assignments[.download] = adopt(.downloadSpeed)
        }
        if let uploadID = assignments[.upload], colors.contains(where: { $0.id == uploadID }) {
            assignments[.upload] = uploadID
        } else {
            assignments[.upload] = adopt(.uploadSpeed)
        }
    }

    private mutating func adopt(_ scheme: ValueTintScheme) -> UUID {
        let normalized = scheme.normalized()
        if let existing = colors.first(where: { $0.scheme == normalized }) {
            return existing.id
        }
        let id = UUID()
        colors.append(RingColor(id: id, scheme: normalized))
        return id
    }

    /// Writes `scheme` onto `segment`. When that color is also used by another
    /// editable ring, this segment gets its own copy. Memory's followers move with it.
    private mutating func write(
        _ scheme: ValueTintScheme,
        to segment: RingColorSegment,
        followers: [RingColorSegment]
    ) {
        let current = assignments[segment]
        let shared = Self.editableSegments.contains { $0 != segment && assignments[$0] == current }
        if shared {
            let id = UUID()
            colors.append(RingColor(id: id, scheme: scheme))
            assignments[segment] = id
            for follower in followers {
                assignments[follower] = id
            }
            pruneUnusedColors()
            return
        }
        if let current, let index = colors.firstIndex(where: { $0.id == current }) {
            colors[index].scheme = scheme
            return
        }
        let id = UUID()
        colors.append(RingColor(id: id, scheme: scheme))
        assignments[segment] = id
        for follower in followers {
            assignments[follower] = id
        }
    }

    private mutating func pruneUnusedColors() {
        let used = Set(assignments.values)
        colors.removeAll { !used.contains($0.id) }
    }
}

enum FlowEditorTarget: String, CaseIterable, Identifiable, Sendable {
    case charging, discharging, adapterHold, underpowered, all

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .charging: "settings.flow.tint.charging"
        case .discharging: "settings.flow.tint.discharging"
        case .adapterHold: "settings.flow.tint.hold"
        case .underpowered: "settings.flow.tint.underpowered"
        case .all: "settings.tint.selection.all"
        }
    }

    var mode: EnergyFlowMode? {
        switch self {
        case .charging: .charging
        case .discharging: .discharging
        case .adapterHold: .adapterHold
        case .underpowered: .underpowered
        case .all: nil
        }
    }
}

struct FlowTintSettings: Codable, Equatable, Sendable {
    var preset: PopoverTintPreset
    var charging: ValueTintScheme
    var discharging: ValueTintScheme
    var adapterHold: ValueTintScheme
    var underpowered: ValueTintScheme
    /// `nil` keeps the motion style’s built-in gradient / solid / white pigment.
    var motionColor: MenuBarTintSwatch?

    static let semantic = FlowTintSettings.preset(.semantic)
    static let system = FlowTintSettings.preset(.system)
    static let highContrast = FlowTintSettings.preset(.highContrast)
    static let glassMono = FlowTintSettings.preset(.glassMono)
    static let smooth = FlowTintSettings.preset(.smooth)
    static let gradient = FlowTintSettings.preset(.gradient)
    static let glide = FlowTintSettings.preset(.glide)

    static func preset(_ preset: PopoverTintPreset) -> FlowTintSettings {
        switch preset {
        case .custom:
            return semantic.markedCustom()
        case .semantic, .system, .highContrast, .glassMono:
            let theme = AppTheme.resolved(palette: preset.themePalette!, colorScheme: .light)
            return FlowTintSettings(
                preset: preset,
                charging: .constant(.from(color: theme.charging)),
                discharging: .constant(.from(color: theme.discharging)),
                adapterHold: .constant(.from(color: theme.adapterHold)),
                underpowered: .constant(.from(color: theme.underpowered)),
                motionColor: nil
            )
        case .smooth:
            // Per-mode slide across battery percent with vivid endpoints.
            return FlowTintSettings(
                preset: .smooth,
                charging: ValueTintScheme(bands: [
                    MenuBarTintBand(
                        throughPercent: 100,
                        swatch: .rgb(0.20, 0.92, 0.55),
                        blend: .slide,
                        lowRight: .rgb(0.10, 0.55, 0.95)
                    )
                ]),
                discharging: ValueTintScheme(bands: [
                    MenuBarTintBand(
                        throughPercent: 100,
                        swatch: .rgb(0.98, 0.72, 0.18),
                        blend: .slide,
                        lowRight: .rgb(0.95, 0.25, 0.18)
                    )
                ]),
                adapterHold: ValueTintScheme(bands: [
                    MenuBarTintBand(
                        throughPercent: 100,
                        swatch: .rgb(0.55, 0.78, 1.00),
                        blend: .slide,
                        lowRight: .rgb(0.22, 0.38, 0.95)
                    )
                ]),
                underpowered: ValueTintScheme(bands: [
                    MenuBarTintBand(
                        throughPercent: 100,
                        swatch: .rgb(0.70, 0.55, 1.00),
                        blend: .slide,
                        lowRight: .rgb(0.95, 0.35, 0.55)
                    )
                ]),
                motionColor: nil
            )
        case .gradient:
            // Strong left→right contrast so charging forks stay readable on the right.
            return FlowTintSettings(
                preset: .gradient,
                charging: ValueTintScheme(bands: [
                    MenuBarTintBand(
                        throughPercent: 100,
                        swatch: .rgb(0.15, 0.95, 0.85),
                        blend: .gradient,
                        highLeft: .rgb(0.12, 0.72, 0.28)
                    )
                ]),
                discharging: ValueTintScheme(bands: [
                    MenuBarTintBand(
                        throughPercent: 100,
                        swatch: .rgb(1.00, 0.82, 0.20),
                        blend: .gradient,
                        highLeft: .rgb(0.92, 0.22, 0.12)
                    )
                ]),
                adapterHold: ValueTintScheme(bands: [
                    MenuBarTintBand(
                        throughPercent: 100,
                        swatch: .rgb(0.55, 0.88, 1.00),
                        blend: .gradient,
                        highLeft: .rgb(0.18, 0.32, 0.92)
                    )
                ]),
                underpowered: ValueTintScheme(bands: [
                    MenuBarTintBand(
                        throughPercent: 100,
                        swatch: .rgb(0.95, 0.55, 0.95),
                        blend: .gradient,
                        highLeft: .rgb(0.45, 0.20, 0.95)
                    )
                ]),
                motionColor: nil
            )
        case .glide:
            return FlowTintSettings(
                preset: .glide,
                charging: ValueTintScheme(bands: [
                    MenuBarTintBand(
                        throughPercent: 100,
                        swatch: .rgb(0.25, 0.98, 0.70),
                        blend: .slideGradient,
                        highLeft: .rgb(0.10, 0.85, 0.35),
                        lowRight: .rgb(0.10, 0.45, 0.95),
                        lowLeft: .rgb(0.08, 0.28, 0.72)
                    )
                ]),
                discharging: ValueTintScheme(bands: [
                    MenuBarTintBand(
                        throughPercent: 100,
                        swatch: .rgb(1.00, 0.78, 0.22),
                        blend: .slideGradient,
                        highLeft: .rgb(0.98, 0.45, 0.10),
                        lowRight: .rgb(0.90, 0.15, 0.20),
                        lowLeft: .rgb(0.70, 0.08, 0.20)
                    )
                ]),
                adapterHold: ValueTintScheme(bands: [
                    MenuBarTintBand(
                        throughPercent: 100,
                        swatch: .rgb(0.65, 0.90, 1.00),
                        blend: .slideGradient,
                        highLeft: .rgb(0.30, 0.55, 0.98),
                        lowRight: .rgb(0.20, 0.30, 0.85),
                        lowLeft: .rgb(0.12, 0.18, 0.65)
                    )
                ]),
                underpowered: ValueTintScheme(bands: [
                    MenuBarTintBand(
                        throughPercent: 100,
                        swatch: .rgb(0.98, 0.65, 0.90),
                        blend: .slideGradient,
                        highLeft: .rgb(0.70, 0.35, 0.98),
                        lowRight: .rgb(0.92, 0.25, 0.45),
                        lowLeft: .rgb(0.55, 0.12, 0.55)
                    )
                ]),
                motionColor: nil
            )
        }
    }

    func scheme(for mode: EnergyFlowMode) -> ValueTintScheme {
        switch mode {
        case .charging: charging
        case .discharging: discharging
        case .adapterHold: adapterHold
        case .underpowered: underpowered
        }
    }

    func markedCustom() -> FlowTintSettings {
        var copy = self
        copy.preset = .custom
        return copy
    }

    func replacing(_ mode: EnergyFlowMode, with scheme: ValueTintScheme) -> FlowTintSettings {
        var copy = markedCustom()
        switch mode {
        case .charging: copy.charging = scheme.normalized()
        case .discharging: copy.discharging = scheme.normalized()
        case .adapterHold: copy.adapterHold = scheme.normalized()
        case .underpowered: copy.underpowered = scheme.normalized()
        }
        return copy
    }

    func mapAll(_ transform: (ValueTintScheme) -> ValueTintScheme) -> FlowTintSettings {
        var copy = markedCustom()
        copy.charging = transform(charging).normalized()
        copy.discharging = transform(discharging).normalized()
        copy.adapterHold = transform(adapterHold).normalized()
        copy.underpowered = transform(underpowered).normalized()
        return copy
    }

    var allSchemes: [ValueTintScheme] { [charging, discharging, adapterHold, underpowered] }
}

/// Field-wise merge for "select all" editors. `nil` means mixed → show "-".
struct MergedTintBand: Identifiable, Equatable {
    var id: Int
    var throughPercent: Int?
    var blend: MenuBarTintBlend?
    var highRight: MenuBarTintSwatch?
    var highLeft: MenuBarTintSwatch?
    var lowRight: MenuBarTintSwatch?
    var lowLeft: MenuBarTintSwatch?
    var presentInAll: Bool
}

enum TintSchemeMerge {
    static func bands(from schemes: [ValueTintScheme]) -> [MergedTintBand] {
        guard let first = schemes.first else { return [] }
        let count = schemes.map(\.sortedBands.count).max() ?? 0
        return (0..<count).map { index in
            let bands: [MenuBarTintBand] = schemes.compactMap { scheme in
                let ordered = scheme.sortedBands
                guard ordered.indices.contains(index) else { return nil }
                return ordered[index]
            }
            let presentInAll = bands.count == schemes.count
            return MergedTintBand(
                id: index,
                throughPercent: common(bands.map(\.throughPercent)),
                blend: common(bands.map(\.blend)),
                highRight: common(bands.map(\.highRight)),
                highLeft: common(bands.map(\.highLeft)),
                lowRight: common(bands.map(\.lowRight)),
                lowLeft: common(bands.map(\.lowLeft)),
                presentInAll: presentInAll
            )
        }
    }

    private static func common<T: Equatable>(_ values: [T]) -> T? {
        guard let first = values.first else { return nil }
        return values.allSatisfy { $0 == first } ? first : nil
    }
}
