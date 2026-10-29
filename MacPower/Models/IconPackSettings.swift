import AppKit
import Foundation
import UniformTypeIdentifiers

/// A single glyph used in rings or energy-flow nodes.
struct GlyphSlot: Codable, Equatable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        case system
        case asset
        case custom
    }

    static let minScale: Double = 0.5
    static let maxScale: Double = 1.8
    static let defaultScale: Double = 1.0

    var source: Source
    /// SF Symbol name, asset catalog name, or custom file id (`uuid.png`).
    var name: String
    /// Template rendering (tints with primary). Custom uploads default to `false`.
    var template: Bool
    /// Per-glyph size relative to the default, used by the popover panel so
    /// uploaded icons of uneven size can be aligned. Shown as the zoom slider %.
    var scale: Double
    /// Authoring-time optical match for built-in assets vs SF Symbols. Hidden from
    /// the zoom slider so Classic GPUMark still reads as 100% while drawing smaller.
    var opticalScale: Double

    var normalizedScale: Double { Self.clamped(scale) }
    var normalizedOpticalScale: Double { Self.clampedOptical(opticalScale) }
    /// Combined size used when drawing (user zoom × built-in optical fit).
    var renderScale: Double { normalizedScale * normalizedOpticalScale }

    static func clamped(_ scale: Double) -> Double {
        min(max(scale, minScale), maxScale)
    }

    static func clampedOptical(_ scale: Double) -> Double {
        min(max(scale, 0.5), 1.5)
    }

    /// Built-in assets fill their canvas more tightly than SF Symbols, so a 20pt
    /// box looks oversized next to `cpu.fill` at 17pt. These factors keep Classic
    /// presets optically matched at 100% zoom (die ≈ 13.7pt for GPUMark).
    static func opticalScale(forAsset name: String) -> Double {
        switch name {
        case "GPUMark": return 0.86
        case "ChargeMark": return 0.9
        default: return 1.0
        }
    }

    static func system(_ name: String, template: Bool = true, scale: Double = defaultScale) -> GlyphSlot {
        GlyphSlot(source: .system, name: name, template: template, scale: clamped(scale), opticalScale: 1)
    }

    static func asset(_ name: String, template: Bool = true, scale: Double = defaultScale) -> GlyphSlot {
        GlyphSlot(
            source: .asset,
            name: name,
            template: template,
            scale: clamped(scale),
            opticalScale: opticalScale(forAsset: name)
        )
    }

    static func customFile(_ id: String, template: Bool = false, scale: Double = defaultScale) -> GlyphSlot {
        GlyphSlot(source: .custom, name: id, template: template, scale: clamped(scale), opticalScale: 1)
    }

    func withScale(_ scale: Double) -> GlyphSlot {
        var copy = self
        copy.scale = Self.clamped(scale)
        return copy
    }

    enum CodingKeys: String, CodingKey {
        case source, name, template, scale, opticalScale
    }

    init(
        source: Source,
        name: String,
        template: Bool,
        scale: Double = defaultScale,
        opticalScale: Double = 1
    ) {
        self.source = source
        self.name = name
        self.template = template
        self.scale = Self.clamped(scale)
        self.opticalScale = source == .asset
            ? Self.clampedOptical(opticalScale == 1 ? Self.opticalScale(forAsset: name) : opticalScale)
            : Self.clampedOptical(opticalScale)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(Source.self, forKey: .source)
        name = try container.decode(String.self, forKey: .name)
        template = try container.decodeIfPresent(Bool.self, forKey: .template) ?? true
        scale = Self.clamped(try container.decodeIfPresent(Double.self, forKey: .scale) ?? Self.defaultScale)
        if let stored = try container.decodeIfPresent(Double.self, forKey: .opticalScale) {
            opticalScale = Self.clampedOptical(stored)
        } else if source == .asset {
            opticalScale = Self.opticalScale(forAsset: name)
        } else {
            opticalScale = 1
        }
    }
}

enum RingIconPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case classic
    case devices
    case outlined
    case circles
    case custom

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .classic: "settings.icons.ring.classic"
        case .devices: "settings.icons.ring.devices"
        case .outlined: "settings.icons.ring.outlined"
        case .circles: "settings.icons.ring.circles"
        case .custom: "settings.icon.tint.custom"
        }
    }
}

enum FlowIconPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case classic
    case plug
    case bolt
    case minimal
    case custom

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .classic: "settings.icons.flow.classic"
        case .plug: "settings.icons.flow.plug"
        case .bolt: "settings.icons.flow.bolt"
        case .minimal: "settings.icons.flow.minimal"
        case .custom: "settings.icon.tint.custom"
        }
    }
}

struct RingIconSettings: Codable, Equatable, Sendable {
    var preset: RingIconPreset
    var battery: GlyphSlot
    var cpu: GlyphSlot
    var gpu: GlyphSlot
    var memory: GlyphSlot

    static let classic = RingIconSettings.preset(.classic)

    static func preset(_ preset: RingIconPreset) -> RingIconSettings {
        switch preset {
        case .custom:
            return classic.markedCustom()
        case .classic:
            return RingIconSettings(
                preset: .classic,
                battery: .system("laptopcomputer"),
                cpu: .system("cpu.fill"),
                gpu: .asset("GPUMark"),
                memory: .system("memorychip.fill")
            )
        case .devices:
            return RingIconSettings(
                preset: .devices,
                battery: .system("macbook"),
                cpu: .system("cpu"),
                gpu: .system("gamecontroller.fill"),
                memory: .system("internaldrive.fill")
            )
        case .outlined:
            return RingIconSettings(
                preset: .outlined,
                battery: .system("laptopcomputer"),
                cpu: .system("cpu"),
                gpu: .system("square.3.layers.3d"),
                memory: .system("memorychip")
            )
        case .circles:
            return RingIconSettings(
                preset: .circles,
                battery: .system("bolt.circle.fill"),
                cpu: .system("gauge.with.dots.needle.67percent"),
                gpu: .system("circle.hexagongrid.fill"),
                memory: .system("cylinder.fill")
            )
        }
    }

    func slot(for kind: RingKind) -> GlyphSlot {
        switch kind {
        case .battery: battery
        case .cpu: cpu
        case .gpu: gpu
        case .memory: memory
        case .disk: .system("internaldrive.fill")
        case .memoryPressure: .system("gauge.with.dots.needle.67percent")
        case .swap: .system("arrow.left.arrow.right")
        }
    }

    func replacing(_ kind: RingKind, with slot: GlyphSlot) -> RingIconSettings {
        var copy = markedCustom()
        switch kind {
        case .battery: copy.battery = slot
        case .cpu: copy.cpu = slot
        case .gpu: copy.gpu = slot
        case .memory: copy.memory = slot
        case .disk, .memoryPressure, .swap: break
        }
        return copy
    }

    func withScale(_ scale: Double, for kind: RingKind) -> RingIconSettings {
        replacing(kind, with: slot(for: kind).withScale(scale))
    }

    func markedCustom() -> RingIconSettings {
        var copy = self
        copy.preset = .custom
        return copy
    }

    /// Drop obsolete pack-level `scale` if present in older saves.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = try container.decode(RingIconPreset.self, forKey: .preset)
        battery = try container.decode(GlyphSlot.self, forKey: .battery)
        cpu = try container.decode(GlyphSlot.self, forKey: .cpu)
        gpu = try container.decode(GlyphSlot.self, forKey: .gpu)
        memory = try container.decode(GlyphSlot.self, forKey: .memory)
        if let legacy = try container.decodeIfPresent(Double.self, forKey: .legacyPackScale),
           abs(legacy - 1) > 0.001 {
            battery = battery.withScale(battery.scale * legacy)
            cpu = cpu.withScale(cpu.scale * legacy)
            gpu = gpu.withScale(gpu.scale * legacy)
            memory = memory.withScale(memory.scale * legacy)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset, forKey: .preset)
        try container.encode(battery, forKey: .battery)
        try container.encode(cpu, forKey: .cpu)
        try container.encode(gpu, forKey: .gpu)
        try container.encode(memory, forKey: .memory)
    }

    private enum CodingKeys: String, CodingKey {
        case preset, battery, cpu, gpu, memory
        case legacyPackScale = "scale"
    }

    init(preset: RingIconPreset, battery: GlyphSlot, cpu: GlyphSlot, gpu: GlyphSlot, memory: GlyphSlot) {
        self.preset = preset
        self.battery = battery
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
    }
}

struct FlowIconSettings: Codable, Equatable, Sendable {
    var preset: FlowIconPreset
    var supply: GlyphSlot
    var battery: GlyphSlot
    var batteryCharging: GlyphSlot
    var mac: GlyphSlot

    static let classic = FlowIconSettings.preset(.classic)

    static func preset(_ preset: FlowIconPreset) -> FlowIconSettings {
        switch preset {
        case .custom:
            return classic.markedCustom()
        case .classic:
            return FlowIconSettings(
                preset: .classic,
                supply: .asset("ChargeMark"),
                battery: .system("battery.100percent"),
                batteryCharging: .system("battery.100percent.bolt"),
                mac: .system("laptopcomputer")
            )
        case .plug:
            return FlowIconSettings(
                preset: .plug,
                supply: .system("powerplug.fill"),
                battery: .system("battery.75percent"),
                batteryCharging: .system("battery.100percent.bolt"),
                mac: .system("desktopcomputer")
            )
        case .bolt:
            return FlowIconSettings(
                preset: .bolt,
                supply: .system("bolt.fill"),
                battery: .system("bolt.batteryblock.fill"),
                batteryCharging: .system("bolt.batteryblock.fill"),
                mac: .system("macbook")
            )
        case .minimal:
            return FlowIconSettings(
                preset: .minimal,
                supply: .system("circle.fill"),
                battery: .system("minus.circle.fill"),
                batteryCharging: .system("plus.circle.fill"),
                mac: .system("circle.fill")
            )
        }
    }

    func slot(for role: FlowIconRole) -> GlyphSlot {
        switch role {
        case .supply: supply
        case .battery: battery
        case .mac: mac
        }
    }

    func slot(forBubbleID id: String, charging: Bool) -> GlyphSlot {
        switch id {
        case "supply": supply
        case "battery": charging ? batteryCharging : battery
        case "mac": mac
        default: .system("questionmark")
        }
    }

    /// Updates one of the three user-facing roles. Pass `syncCharging` when a
    /// custom upload should cover both idle and charging battery nodes.
    func replacing(_ role: FlowIconRole, with slot: GlyphSlot, syncCharging: Bool = false) -> FlowIconSettings {
        var copy = markedCustom()
        switch role {
        case .supply:
            copy.supply = slot
        case .battery:
            copy.battery = slot
            if syncCharging {
                copy.batteryCharging = slot
            }
        case .mac:
            copy.mac = slot
        }
        return copy
    }

    func withScale(_ scale: Double, for role: FlowIconRole) -> FlowIconSettings {
        var copy = markedCustom()
        switch role {
        case .supply:
            copy.supply = supply.withScale(scale)
        case .mac:
            copy.mac = mac.withScale(scale)
        case .battery:
            // Keep charging/idle battery glyphs visually matched.
            copy.battery = battery.withScale(scale)
            copy.batteryCharging = batteryCharging.withScale(scale)
        }
        return copy
    }

    func markedCustom() -> FlowIconSettings {
        var copy = self
        copy.preset = .custom
        return copy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = try container.decode(FlowIconPreset.self, forKey: .preset)
        supply = try container.decode(GlyphSlot.self, forKey: .supply)
        battery = try container.decode(GlyphSlot.self, forKey: .battery)
        batteryCharging = try container.decode(GlyphSlot.self, forKey: .batteryCharging)
        mac = try container.decode(GlyphSlot.self, forKey: .mac)
        if let legacy = try container.decodeIfPresent(Double.self, forKey: .legacyPackScale),
           abs(legacy - 1) > 0.001 {
            supply = supply.withScale(supply.scale * legacy)
            battery = battery.withScale(battery.scale * legacy)
            batteryCharging = batteryCharging.withScale(batteryCharging.scale * legacy)
            mac = mac.withScale(mac.scale * legacy)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset, forKey: .preset)
        try container.encode(supply, forKey: .supply)
        try container.encode(battery, forKey: .battery)
        try container.encode(batteryCharging, forKey: .batteryCharging)
        try container.encode(mac, forKey: .mac)
    }

    private enum CodingKeys: String, CodingKey {
        case preset, supply, battery, batteryCharging, mac
        case legacyPackScale = "scale"
    }

    init(
        preset: FlowIconPreset,
        supply: GlyphSlot,
        battery: GlyphSlot,
        batteryCharging: GlyphSlot,
        mac: GlyphSlot
    ) {
        self.preset = preset
        self.supply = supply
        self.battery = battery
        self.batteryCharging = batteryCharging
        self.mac = mac
    }
}

enum CustomIconStore {
    private static let folderName = "CustomIcons"

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("MacPower", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for id: String) -> URL {
        directory.appendingPathComponent(id)
    }

    static func image(id: String) -> NSImage? {
        let path = url(for: id).path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }

    /// Saves a user image as PNG (max 128px). Returns the file id.
    static func save(image: NSImage) -> String? {
        guard let png = pngData(from: image, maxSide: 128) else { return nil }
        let id = UUID().uuidString + ".png"
        do {
            try png.write(to: url(for: id), options: .atomic)
            return id
        } catch {
            return nil
        }
    }

    static func save(fromFile url: URL) -> String? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return save(image: image)
    }

    static func pngData(from image: NSImage, maxSide: CGFloat) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = NSSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }
        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            image.draw(
                in: NSRect(origin: .zero, size: target),
                from: .zero,
                operation: .copy,
                fraction: 1
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    static func pickImage(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .webP, .gif, .heic]
        panel.title = title
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

enum FlowIconRole: String, CaseIterable, Identifiable, Sendable {
    case supply, battery, mac

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .supply: "settings.icons.flow.supply"
        case .battery: "settings.icons.flow.battery"
        case .mac: "settings.icons.flow.mac"
        }
    }

    var symbolChoices: [GlyphSlot] {
        switch self {
        case .supply:
            [
                .asset("ChargeMark"),
                .system("powerplug.fill"),
                .system("bolt.fill"),
                .system("bolt.circle.fill"),
                .system("cable.connector"),
                .system("circle.fill")
            ]
        case .battery:
            [
                .system("battery.100percent"),
                .system("battery.100percent.bolt"),
                .system("battery.75percent"),
                .system("bolt.batteryblock.fill"),
                .system("minus.circle.fill"),
                .system("plus.circle.fill")
            ]
        case .mac:
            [
                .system("laptopcomputer"),
                .system("macbook"),
                .system("desktopcomputer"),
                .system("display"),
                .system("circle.fill")
            ]
        }
    }
}

extension RingKind {
    var symbolChoices: [GlyphSlot] {
        switch self {
        case .battery:
            [
                .system("laptopcomputer"),
                .system("macbook"),
                .system("bolt.circle.fill"),
                .system("battery.100percent"),
                .system("powerplug.fill")
            ]
        case .cpu:
            [
                .system("cpu.fill"),
                .system("cpu"),
                .system("gauge.with.dots.needle.67percent"),
                .system("memorychip.fill")
            ]
        case .gpu:
            [
                .asset("GPUMark"),
                .system("gamecontroller.fill"),
                .system("square.3.layers.3d"),
                .system("circle.hexagongrid.fill"),
                .system("cube.fill")
            ]
        case .memory:
            [
                .system("memorychip.fill"),
                .system("memorychip"),
                .system("internaldrive.fill"),
                .system("cylinder.fill"),
                .system("externaldrive.fill")
            ]
        case .disk:
            [.system("internaldrive.fill")]
        case .memoryPressure:
            [.system("gauge.with.dots.needle.67percent")]
        case .swap:
            [.system("arrow.left.arrow.right")]
        }
    }
}
