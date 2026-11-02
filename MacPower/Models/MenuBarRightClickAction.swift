import Foundation

/// Where the popover draws the control that opens Settings.
/// The menu-bar icon's right-click menu always contains Open Settings and Quit.
enum SettingsButtonPlacement: String, CaseIterable, Identifiable, Sendable {
    /// A sortable panel block: one left-aligned text row, like the system battery menu.
    case ownBlock
    /// The gear lives inside one existing panel block.
    case insideBlock
    /// No settings control in the panel. Right-click the menu-bar icon to open Settings.
    case rightClickOnly

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .ownBlock: "settings.button.ownBlock"
        case .insideBlock: "settings.button.insideBlock"
        case .rightClickOnly: "settings.button.rightClickOnly"
        }
    }

    /// Unknown or missing stored values stay on the right-click menu.
    static func resolved(stored raw: String?) -> SettingsButtonPlacement {
        guard let raw, let placement = SettingsButtonPlacement(rawValue: raw) else {
            return .rightClickOnly
        }
        return placement
    }

    /// Gear cell inside the ring grid. A hidden ring block does not invent a floating button.
    func drawsRingGear(host: SettingsButtonHost, ringsVisible: Bool) -> Bool {
        self == .insideBlock && host == .rings && ringsVisible
    }

    /// Gear beside the energy-flow ribbon. A hidden flow block draws nothing.
    func drawsFlowGear(host: SettingsButtonHost, flowVisible: Bool) -> Bool {
        self == .insideBlock && host == .flow && flowVisible
    }

    /// Small title-row button for a content block. A hidden host draws no empty shell.
    func drawsHeader(host: SettingsButtonHost, section: SettingsButtonHost, sectionVisible: Bool) -> Bool {
        self == .insideBlock && host == section && sectionVisible
    }

    /// Standalone settings block. Hidden in the panel list, or any other placement, draws nothing.
    func drawsOwnBlock(blockVisible: Bool) -> Bool {
        self == .ownBlock && blockVisible
    }

    /// Menu-style label: the settings title plus an ellipsis, matching 「电池设置...」.
    static func standaloneRowTitle(_ base: String) -> String {
        if base.hasSuffix("…") || base.hasSuffix("...") { return base }
        return base + "…"
    }
}

/// Existing panel block that can host the settings button. The settings block itself is not a host.
enum SettingsButtonHost: String, CaseIterable, Identifiable, Sendable {
    case rings
    case flow
    case topApps
    case lowPower
    case localIP
    case batteryCycle

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .rings: "settings.tab.rings"
        case .flow: "settings.tab.flow"
        case .topApps: "settings.tab.topApps"
        case .lowPower: "settings.tab.lowPower"
        case .localIP: "settings.tab.localIP"
        case .batteryCycle: "settings.tab.batteryCycle"
        }
    }

    /// Unknown or missing stored values keep the button in the ring grid.
    static func resolved(stored raw: String?) -> SettingsButtonHost {
        guard let raw, let host = SettingsButtonHost(rawValue: raw) else {
            return .rings
        }
        return host
    }

    var popoverBlock: PopoverBlock {
        switch self {
        case .rings: .rings
        case .flow: .flow
        case .topApps: .topApps
        case .lowPower: .lowPower
        case .localIP: .localIP
        case .batteryCycle: .batteryCycle
        }
    }

    /// Next shown host after `host`, wrapping once. Skips hidden blocks and the settings block.
    static func nextVisible(
        after host: SettingsButtonHost,
        order: [PopoverBlock],
        isVisible: (PopoverBlock) -> Bool
    ) -> SettingsButtonHost? {
        let count = order.count
        guard count > 0 else { return nil }
        let start = order.firstIndex(where: { $0.settingsHost == host }) ?? -1
        let steps = start < 0 ? count : count - 1
        let begin = start < 0 ? 0 : start + 1
        for offset in 0..<steps {
            let block = order[(begin + offset) % count]
            guard let candidate = block.settingsHost, candidate != host, isVisible(block) else { continue }
            return candidate
        }
        return nil
    }
}
