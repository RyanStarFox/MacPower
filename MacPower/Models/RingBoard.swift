import Foundation

enum BluetoothBatteryPart: String, Codable, CaseIterable, Identifiable, Sendable {
    case single
    case left
    case right
    case box

    var id: String { rawValue }

    var sortIndex: Int {
        switch self {
        case .left: 0
        case .right: 1
        case .box: 2
        case .single: 3
        }
    }

    var localizationKey: String {
        switch self {
        case .single: "settings.rings.bluetooth.single"
        case .left: "settings.rings.bluetooth.left"
        case .right: "settings.rings.bluetooth.right"
        case .box: "settings.rings.bluetooth.case"
        }
    }

    var shortLocalizationKey: String {
        switch self {
        case .single: "settings.rings.bluetooth.single"
        case .left: "settings.rings.bluetooth.leftShort"
        case .right: "settings.rings.bluetooth.rightShort"
        case .box: "settings.rings.bluetooth.caseShort"
        }
    }

    static func ordered(_ parts: [BluetoothBatteryPart]) -> [BluetoothBatteryPart] {
        parts.sorted { $0.sortIndex < $1.sortIndex }
    }
}

enum BluetoothDisconnectedStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case hide
    case empty

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .hide: "settings.rings.bluetooth.hide"
        case .empty: "settings.rings.bluetooth.placeholder"
        }
    }
}

/// A merged ring is missing one of its levels, but the device is still connected.
enum BluetoothIncompleteStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case hide
    case showRemaining

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .hide: "settings.rings.bluetooth.incompleteHide"
        case .showRemaining: "settings.rings.bluetooth.incompleteRest"
        }
    }
}

struct RingIconRGB: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

struct BluetoothDisplayRing: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var parts: [BluetoothBatteryPart]
    var whenDisconnected: BluetoothDisconnectedStyle
    var whenIncomplete: BluetoothIncompleteStyle
    /// Center icon for a one-part or three-part ring.
    var glyph: GlyphSlot
    /// Nil follows the system dark or light ink. Used by one-part and three-part rings.
    var iconColor: RingIconRGB?
    /// While true, icons track the device model instead of a manual pick.
    var automaticIcons: Bool
    /// Icons for a two-part ring, one on each half.
    var sideGlyphs: [BluetoothBatteryPart: GlyphSlot]
    /// Custom half colors. Nil follows that half's battery color.
    var sideColors: [BluetoothBatteryPart: RingIconRGB]

    static func make(
        parts: [BluetoothBatteryPart],
        model: HeadphoneModel = .generic,
        whenDisconnected: BluetoothDisconnectedStyle = .hide
    ) -> BluetoothDisplayRing {
        let ordered = BluetoothBatteryPart.ordered(parts)
        var ring = BluetoothDisplayRing(
            id: UUID(),
            parts: ordered,
            whenDisconnected: whenDisconnected,
            whenIncomplete: .showRemaining,
            glyph: .system("headphones"),
            iconColor: nil,
            automaticIcons: true,
            sideGlyphs: [:],
            sideColors: [:]
        )
        ring.applyAutomaticIcons(model: model)
        return ring
    }

    mutating func applyAutomaticIcons(model: HeadphoneModel) {
        guard automaticIcons else { return }
        glyph = HeadphoneSymbols.glyph(model: model, parts: parts)
        if parts.count == 2 {
            var sides: [BluetoothBatteryPart: GlyphSlot] = [:]
            for part in parts {
                sides[part] = HeadphoneSymbols.glyph(model: model, part: part)
            }
            sideGlyphs = sides
        }
    }

    func shownGlyph(model: HeadphoneModel, part: BluetoothBatteryPart) -> GlyphSlot {
        if automaticIcons { return HeadphoneSymbols.glyph(model: model, part: part) }
        return sideGlyphs[part] ?? HeadphoneSymbols.glyph(model: model, part: part)
    }

    func shownGlyph(model: HeadphoneModel, parts shown: [BluetoothBatteryPart]) -> GlyphSlot {
        if automaticIcons { return HeadphoneSymbols.glyph(model: model, parts: shown) }
        return glyph
    }

    private enum CodingKeys: String, CodingKey {
        case id, parts, whenDisconnected, whenIncomplete, glyph, iconColor
        case automaticIcons, sideGlyphs, sideColors
    }

    init(
        id: UUID,
        parts: [BluetoothBatteryPart],
        whenDisconnected: BluetoothDisconnectedStyle,
        whenIncomplete: BluetoothIncompleteStyle,
        glyph: GlyphSlot,
        iconColor: RingIconRGB?,
        automaticIcons: Bool,
        sideGlyphs: [BluetoothBatteryPart: GlyphSlot],
        sideColors: [BluetoothBatteryPart: RingIconRGB]
    ) {
        self.id = id
        self.parts = parts
        self.whenDisconnected = whenDisconnected
        self.whenIncomplete = whenIncomplete
        self.glyph = glyph
        self.iconColor = iconColor
        self.automaticIcons = automaticIcons
        self.sideGlyphs = sideGlyphs
        self.sideColors = sideColors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        parts = try container.decode([BluetoothBatteryPart].self, forKey: .parts)
        whenDisconnected = try container.decode(BluetoothDisconnectedStyle.self, forKey: .whenDisconnected)
        whenIncomplete = try container.decodeIfPresent(BluetoothIncompleteStyle.self, forKey: .whenIncomplete) ?? .showRemaining
        glyph = try container.decode(GlyphSlot.self, forKey: .glyph)
        iconColor = try container.decodeIfPresent(RingIconRGB.self, forKey: .iconColor)
        sideGlyphs = try container.decodeIfPresent([BluetoothBatteryPart: GlyphSlot].self, forKey: .sideGlyphs) ?? [:]
        sideColors = try container.decodeIfPresent([BluetoothBatteryPart: RingIconRGB].self, forKey: .sideColors) ?? [:]
        if let stored = try container.decodeIfPresent(Bool.self, forKey: .automaticIcons) {
            automaticIcons = stored
        } else {
            automaticIcons = Self.isGeneric(glyph)
        }
    }

    private static func isGeneric(_ glyph: GlyphSlot) -> Bool {
        [
            "headphones", "airpods", "earbuds", "ear", "hearingdevice.ear",
            "battery.100", "battery.75", "bolt.fill"
        ].contains(glyph.name)
    }
}

enum HeadphoneModel: Equatable, Sendable {
    /// `artwork` is a filename in the system Bluetooth UI resources, used when SF Symbols has no drawing for that model.
    case airpods(generation: Int, artwork: String?)
    case airpodsPro(generation: Int)
    case airpodsMax
    case powerbeatsPro(generation: Int)
    case powerbeats3
    case powerbeats
    case studioBuds(plus: Bool)
    case fitPro
    case soloBuds
    case beatsHeadphones
    case generic

    static func detect(name: String, productID: String?) -> HeadphoneModel {
        if let id = normalizedID(productID), let known = productIDs[id] { return known }
        let text = name.lowercased()
        if text.contains("airpods max") || text.contains("airpod max") { return .airpodsMax }
        if text.contains("airpods pro") || text.contains("airpod pro") {
            if text.contains("pro 1") || text.contains("第一代") { return .airpodsPro(generation: 1) }
            if text.contains("pro 3") || text.contains("第三代") { return .airpodsPro(generation: 3) }
            return .airpodsPro(generation: 2)
        }
        if text.contains("powerbeats pro") {
            return .powerbeatsPro(generation: text.contains("pro 2") || text.contains("2") ? 2 : 1)
        }
        if text.contains("powerbeats 3") || text.contains("powerbeats3") { return .powerbeats3 }
        if text.contains("studio buds") { return .studioBuds(plus: text.contains("plus") || text.contains("+")) }
        if text.contains("fit pro") || text.contains("fitpro") { return .fitPro }
        if text.contains("solo buds") || text.contains("solobuds") { return .soloBuds }
        if text.contains("powerbeats") { return .powerbeats }
        if text.contains("beats") { return .beatsHeadphones }
        if text.contains("airpods") || text.contains("airpod") {
            if text.range(of: #"airpods\s*5"#, options: .regularExpression) != nil || text.contains("第五代") {
                return .airpods(generation: 5, artwork: "B868m.icns")
            }
            if text.range(of: #"airpods\s*4"#, options: .regularExpression) != nil || text.contains("第四代") {
                return .airpods(generation: 4, artwork: nil)
            }
            if text.range(of: #"airpods\s*3"#, options: .regularExpression) != nil || text.contains("第三代") {
                return .airpods(generation: 3, artwork: nil)
            }
            return .airpods(generation: 2, artwork: nil)
        }
        return .generic
    }

    func symbolName(part: BluetoothBatteryPart) -> String {
        switch self {
        case .generic:
            return part == .box ? "battery.100" : "headphones"
        case .airpodsMax:
            return "airpods.max"
        case .airpods(let generation, _):
            switch part {
            case .left: return generation >= 4 ? "airpods.gen4.left" : (generation == 3 ? "airpod.gen3.left" : "airpod.left")
            case .right: return generation >= 4 ? "airpods.gen4.right" : (generation == 3 ? "airpod.gen3.right" : "airpod.right")
            case .box: return generation >= 4 ? "airpods.gen4.chargingcase.wireless" : (generation == 3 ? "airpods.gen3.chargingcase.wireless" : "airpods.chargingcase")
            case .single: return generation >= 4 ? "airpods.gen4" : (generation == 3 ? "airpods.gen3" : "airpods")
            }
        case .airpodsPro(let generation):
            let stem = generation <= 1 ? "airpods.pro.gen1" : (generation >= 3 ? "airpods.pro.gen3" : "airpods.pro")
            switch part {
            case .left: return stem + ".left"
            case .right: return stem + ".right"
            case .box: return stem + ".chargingcase.wireless"
            case .single: return stem
            }
        case .powerbeatsPro(let generation):
            let stem = generation >= 2 ? "beats.powerbeats.pro.2" : "beats.powerbeats.pro"
            switch part {
            case .left: return stem + ".left"
            case .right: return stem + ".right"
            case .box: return stem + ".chargingcase"
            case .single: return stem
            }
        case .powerbeats3:
            switch part {
            case .left: return "beats.powerbeats3.left"
            case .right: return "beats.powerbeats3.right"
            default: return "beats.powerbeats3"
            }
        case .powerbeats:
            switch part {
            case .left: return "beats.powerbeats.left"
            case .right: return "beats.powerbeats.right"
            default: return "beats.powerbeats"
            }
        case .studioBuds(let plus):
            let stem = plus ? "beats.studiobuds.plus" : "beats.studiobuds"
            switch part {
            case .left: return stem + ".left"
            case .right: return stem + ".right"
            case .box: return stem + ".chargingcase"
            case .single: return stem
            }
        case .fitPro:
            switch part {
            case .left: return "beats.fitpro.left"
            case .right: return "beats.fitpro.right"
            case .box: return "beats.fitpro.chargingcase"
            case .single: return "beats.fitpro"
            }
        case .soloBuds:
            switch part {
            case .left: return "beats.solobuds.left"
            case .right: return "beats.solobuds.right"
            case .box: return "beats.solobuds.chargingcase"
            case .single: return "beats.solobuds"
            }
        case .beatsHeadphones:
            return "beats.headphones"
        }
    }

    func symbolName(parts: [BluetoothBatteryPart]) -> String {
        if parts.count == 1, let part = parts.first { return symbolName(part: part) }
        switch self {
        case .generic: return "headphones"
        case .airpodsMax: return "airpods.max"
        case .airpods(let generation, _):
            return generation >= 4 ? "airpods.gen4" : (generation == 3 ? "airpods.gen3" : "airpods")
        case .airpodsPro(let generation): return generation <= 1 ? "airpods.pro.gen1" : (generation >= 3 ? "airpods.pro.gen3" : "airpods.pro")
        case .powerbeatsPro(let generation): return generation >= 2 ? "beats.powerbeats.pro.2" : "beats.powerbeats.pro"
        case .powerbeats3: return "beats.powerbeats3"
        case .powerbeats: return "beats.powerbeats"
        case .studioBuds(let plus): return plus ? "beats.studiobuds.plus" : "beats.studiobuds"
        case .fitPro: return "beats.fitpro"
        case .soloBuds: return "beats.solobuds"
        case .beatsHeadphones: return "beats.headphones"
        }
    }

    func choiceNames() -> [String] {
        var names = [symbolName(parts: [.single, .left])]
        for part in [BluetoothBatteryPart.left, .right, .box, .single] {
            names.append(symbolName(part: part))
        }
        if self == .generic {
            names.append(contentsOf: ["earbuds", "hearingdevice.ear"])
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private static let productIDs: [String: HeadphoneModel] = [
        "2002": .airpods(generation: 1, artwork: nil),
        "200f": .airpods(generation: 2, artwork: nil),
        "2013": .airpods(generation: 3, artwork: nil),
        "2030": .airpods(generation: 5, artwork: "B868m.icns"),
        "2032": .airpods(generation: 5, artwork: "B868m.icns"),
        "2036": .airpods(generation: 5, artwork: "B868e.icns"),
        "2037": .airpods(generation: 5, artwork: "B868e.icns"),
        "200e": .airpodsPro(generation: 1),
        "2014": .airpodsPro(generation: 2),
        "200a": .airpodsMax
    ]

    private static func normalizedID(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !text.isEmpty else { return nil }
        if text.hasPrefix("0x") { text.removeFirst(2) }
        if text.allSatisfy(\.isNumber), let value = Int(text), value >= 0x1000 {
            return String(format: "%x", value)
        }
        return text
    }
}

struct BluetoothRingDevice: Codable, Equatable, Identifiable, Sendable {
    var address: String
    var name: String
    /// True when the device reports left, right, or a case, not one battery.
    var multi: Bool
    var rings: [BluetoothDisplayRing]
    var productID: String?

    var id: String { address }
    var model: HeadphoneModel { HeadphoneModel.detect(name: name, productID: productID) }

    private enum CodingKeys: String, CodingKey {
        case address, name, multi, rings, parts, whenDisconnected, productID
    }

    init(address: String, name: String, multi: Bool, rings: [BluetoothDisplayRing], productID: String? = nil) {
        self.address = address
        self.name = name
        self.multi = multi
        self.rings = rings
        self.productID = productID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(String.self, forKey: .address)
        name = try container.decode(String.self, forKey: .name)
        if let rings = try container.decodeIfPresent([BluetoothDisplayRing].self, forKey: .rings) {
            self.rings = rings
            multi = try container.decodeIfPresent(Bool.self, forKey: .multi)
                ?? rings.contains { ring in ring.parts.contains { $0 != .single } }
        } else {
            let parts = try container.decodeIfPresent([BluetoothBatteryPart].self, forKey: .parts) ?? []
            let style = try container.decodeIfPresent(BluetoothDisconnectedStyle.self, forKey: .whenDisconnected) ?? .hide
            let chosen = parts.isEmpty ? [BluetoothBatteryPart.single] : BluetoothBatteryPart.ordered(parts)
            multi = chosen.contains { $0 != .single }
            rings = chosen.map { BluetoothDisplayRing.make(parts: [$0], whenDisconnected: style) }
        }
        productID = try container.decodeIfPresent(String.self, forKey: .productID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(address, forKey: .address)
        try container.encode(name, forKey: .name)
        try container.encode(multi, forKey: .multi)
        try container.encode(rings, forKey: .rings)
        try container.encodeIfPresent(productID, forKey: .productID)
    }
}

struct RingItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    var slot: RingSlot?
    var address: String?
    var ringID: UUID?
    /// Older saves named one part instead of a display ring.
    var part: BluetoothBatteryPart?

    var id: String {
        if let slot { return "slot:\(slot.rawValue)" }
        if let ringID { return "device:\(address ?? ""):\(ringID.uuidString)" }
        return "device:\(address ?? ""):\(part?.rawValue ?? "")"
    }

    static func slot(_ slot: RingSlot) -> RingItem {
        RingItem(slot: slot, address: nil, ringID: nil, part: nil)
    }

    static func bluetooth(address: String, ringID: UUID) -> RingItem {
        RingItem(slot: nil, address: address, ringID: ringID, part: nil)
    }

    var ringSlot: RingSlot? { slot }
}

struct BluetoothSeenDevice: Equatable, Identifiable, Sendable {
    var address: String
    var name: String
    var connected: Bool
    var levels: [BluetoothBatteryPart: Int]
    var productID: String?

    init(address: String, name: String, connected: Bool, levels: [BluetoothBatteryPart: Int], productID: String? = nil) {
        self.address = address
        self.name = name
        self.connected = connected
        self.levels = levels
        self.productID = productID
    }

    var id: String { address }
    var reportedParts: Set<BluetoothBatteryPart> { Set(levels.keys) }
    var isMulti: Bool { levels.keys.contains { $0 != .single } }
    var model: HeadphoneModel { HeadphoneModel.detect(name: name, productID: productID) }
}

struct BluetoothRingFace: Equatable, Sendable {
    var parts: [BluetoothBatteryPart]
    var levels: [BluetoothBatteryPart: Int]
    var isPlaceholder: Bool
}

enum RingBoard {
    static func migratedRows(order: [RingSlot], twoRows: Bool) -> [[RingItem]] {
        let items = order.map(RingItem.slot)
        guard twoRows, items.count >= 2 else { return [items] }
        let columns = (items.count + 1) / 2
        return [Array(items.prefix(columns)), Array(items.dropFirst(columns))].filter { !$0.isEmpty }
    }

    static func face(
        ring: BluetoothDisplayRing,
        connected: Bool,
        levels: [BluetoothBatteryPart: Int]
    ) -> BluetoothRingFace? {
        let wanted = BluetoothBatteryPart.ordered(ring.parts)
        guard !wanted.isEmpty else { return nil }
        let available = wanted.filter { levels[$0] != nil }
        if !connected || available.isEmpty {
            switch ring.whenDisconnected {
            case .hide:
                return nil
            case .empty:
                return BluetoothRingFace(parts: wanted, levels: [:], isPlaceholder: true)
            }
        }
        if available.count < wanted.count, ring.whenIncomplete == .hide {
            return nil
        }
        let shown = available.count < wanted.count ? available : wanted
        let kept = Dictionary(uniqueKeysWithValues: shown.compactMap { part -> (BluetoothBatteryPart, Int)? in
            guard let level = levels[part] else { return nil }
            return (part, level)
        })
        return BluetoothRingFace(parts: shown, levels: kept, isPlaceholder: false)
    }

    /// Rows actually drawn. A row whose rings are all hidden is dropped.
    static func visibleRows(
        rows: [[RingItem]],
        devices: [BluetoothRingDevice],
        seen: [BluetoothSeenDevice]
    ) -> [[RingItem]] {
        let saved = Dictionary(uniqueKeysWithValues: devices.map { ($0.address, $0) })
        let live = Dictionary(uniqueKeysWithValues: seen.map { ($0.address, $0) })
        return rows.compactMap { row in
            let kept = row.filter { item in
                guard item.slot == nil else { return true }
                return resolve(item, saved: saved).flatMap { ring in
                    let reading = item.address.flatMap { live[$0] }
                    return face(
                        ring: ring,
                        connected: reading?.connected == true,
                        levels: reading?.levels ?? [:]
                    )
                } != nil
            }
            return kept.isEmpty ? nil : kept
        }
    }

    static func resolve(_ item: RingItem, devices: [BluetoothRingDevice]) -> BluetoothDisplayRing? {
        resolve(item, saved: Dictionary(uniqueKeysWithValues: devices.map { ($0.address, $0) }))
    }

    private static func resolve(
        _ item: RingItem,
        saved: [String: BluetoothRingDevice]
    ) -> BluetoothDisplayRing? {
        guard let address = item.address, let device = saved[address] else { return nil }
        if let ringID = item.ringID {
            return device.rings.first { $0.id == ringID }
        }
        if let part = item.part {
            return device.rings.first { $0.parts == [part] }
        }
        return nil
    }

    /// Point old part-based row items at the rings created for those parts.
    static func linkedRows(_ rows: [[RingItem]], devices: [BluetoothRingDevice]) -> [[RingItem]] {
        rows.map { row in
            row.compactMap { item in
                guard item.slot == nil, item.ringID == nil else { return item }
                guard let address = item.address, let ring = resolve(item, devices: devices) else { return nil }
                return .bluetooth(address: address, ringID: ring.id)
            }
        }
    }
}
