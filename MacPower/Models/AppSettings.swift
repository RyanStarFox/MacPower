import Foundation
import Observation

enum PopoverBlock: String, CaseIterable, Identifiable, Codable, Sendable {
    case rings
    case flow
    case topApps
    case lowPower
    case localIP
    case batteryCycle
    case settings

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .rings: "settings.popover.showRings"
        case .flow: "settings.popover.showFlow"
        case .topApps: "settings.popover.showTopApps"
        case .lowPower: "settings.popover.showLowPower"
        case .localIP: "settings.popover.showLocalIP"
        case .batteryCycle: "settings.popover.showBatteryCycle"
        case .settings: "settings.title"
        }
    }

    var settingsHost: SettingsButtonHost? {
        switch self {
        case .rings: .rings
        case .flow: .flow
        case .topApps: .topApps
        case .lowPower: .lowPower
        case .localIP: .localIP
        case .batteryCycle: .batteryCycle
        case .settings: nil
        }
    }
}

@Observable
final class AppSettings {
    static let defaultRingOrder: [RingSlot] = [.battery, .cpu, .gpu, .memory, .disk, .download, .upload, .thermalState]

    private static func restoredRingOrder(from defaults: UserDefaults) -> [RingSlot] {
        let stored = defaults.stringArray(forKey: Keys.visibleRings)?.compactMap(RingSlot.init(rawValue:)) ?? []
        var seen = Set<RingSlot>()
        var order = stored.filter { seen.insert($0).inserted }
        if order.isEmpty {
            order = defaultRingOrder
        } else if !defaults.bool(forKey: Keys.ringOrderMigrated) {
            let showDownload = defaults.object(forKey: Keys.showDownloadSpeed) == nil
                || defaults.bool(forKey: Keys.showDownloadSpeed)
            let showUpload = defaults.object(forKey: Keys.showUploadSpeed) == nil
                || defaults.bool(forKey: Keys.showUploadSpeed)
            if showDownload, !order.contains(.download) { order.append(.download) }
            if showUpload, !order.contains(.upload) { order.append(.upload) }
        }
        // One-shot: existing saved orders predate this ring, so show it once.
        // A later hide is stored without the slot and is left alone.
        if !defaults.bool(forKey: Keys.thermalStateRingMigrated) {
            if !order.contains(.thermalState) {
                order.append(.thermalState)
            }
            defaults.set(order.map(\.rawValue), forKey: Keys.visibleRings)
            defaults.set(true, forKey: Keys.thermalStateRingMigrated)
        }
        return order
    }
    private enum Keys {
        static let iconStyle = "iconStyle"
        static let iconOutlined = "iconOutlined"
        static let digitPlacement = "digitPlacement"
        static let menuBarTint = "menuBarTint"
        static let palette = "palette"
        static let ringTint = "ringTint"
        static let flowTint = "flowTint"
        static let ringIcons = "ringIcons"
        static let flowIcons = "flowIcons"
        static let savedTintLibrary = "savedTintLibrary"
        static let savedIconLibrary = "savedIconLibrary"
        static let menuBarActiveSavedTint = "menuBarActiveSavedTint"
        static let ringActiveSavedTint = "ringActiveSavedTint"
        static let flowActiveSavedTint = "flowActiveSavedTint"
        static let ringActiveSavedIcon = "ringActiveSavedIcon"
        static let flowActiveSavedIcon = "flowActiveSavedIcon"
        static let lowBatteryTintEnabled = "lowBatteryTintEnabled"
        static let showChargeGlyphs = "showChargeGlyphs"
        static let motionStyle = "motionStyle"
        static let motionFrameRate = "motionFrameRate"
        static let pulseFlowIcons = "pulseFlowIcons"
        static let flowIconScale = "flowIconScale"
        static let showPopoverArrow = "showPopoverArrow"
        static let showStatusRings = "showStatusRings"
        static let twoRingRows = "twoRingRows"
        static let ringOddRow = "ringOddRow"
        static let visibleRings = "visibleRings"
        static let showDownloadSpeed = "showDownloadSpeed"
        static let showUploadSpeed = "showUploadSpeed"
        static let ringOrderMigrated = "ringOrderMigrated"
        static let thermalStateRingMigrated = "thermalStateRingMigrated"
        static let ringCatalog = "ringCatalog"
        static let showEnergyFlow = "showEnergyFlow"
        static let showTopApps = "showTopApps"
        static let showLowPower = "showLowPower"
        static let lowPowerStrategy = "lowPowerStrategy"
        static let lowPowerButtonLayout = "lowPowerButtonLayout"
        static let lowPowerButtonVisibility = "lowPowerButtonVisibility"
        static let showLocalIP = "showLocalIP"
        static let showBatteryCycle = "showBatteryCycle"
        static let batteryCapacityStyle = "batteryCapacityStyle"
        static let ipScopes = "ipScopes"
        static let ipFamilies = "ipFamilies"
        static let popoverOrder = "popoverOrder"
        static let topAppWindowMinutes = "topAppWindowMinutes"
        static let topAppIntervalSeconds = "topAppIntervalSeconds"
        static let topAppLimit = "topAppLimit"
        static let topAppsChart = "topAppsChart"
        static let downloadHalfKilobytes = "downloadHalfKilobytes"
        static let uploadHalfKilobytes = "uploadHalfKilobytes"
        static let temperatureHalfCelsius = "temperatureHalfCelsius"
        static let thermalNominalPercent = "thermalNominalPercent"
        static let thermalFairPercent = "thermalFairPercent"
        static let thermalSeriousPercent = "thermalSeriousPercent"
        static let thermalCriticalPercent = "thermalCriticalPercent"
        static let settingsButtonPlacement = "settingsButtonPlacement"
        static let settingsButtonHost = "settingsButtonHost"
        static let showSettingsBlock = "showSettingsBlock"
        static let automaticallyCheckForUpdates = "automaticallyCheckForUpdates"
        static let language = "appLanguage"
        static let appleLanguages = "AppleLanguages"
        static let legacyEnergyMotion = "energyMotion"
    }

    @ObservationIgnored
    private let store: UserDefaults

    /// Menu-bar glyph fields changed (outline / digits / tint / charge glyphs).
    /// Wired by `AppState` so we never need a polling snapshot watch.
    @ObservationIgnored
    var onMenuBarChromeChange: (() -> Void)?

    /// Sampling window, interval, count, or the top-apps switch changed.
    @ObservationIgnored
    var onTopAppSamplingChange: (() -> Void)?

    /// Local IP block visibility or which address kinds to show.
    @ObservationIgnored
    var onLocalIPChange: (() -> Void)?

    static let defaultTopAppWindowMinutes = 3
    static let defaultTopAppIntervalSeconds = 10
    static let defaultTopAppLimit = 5
    static let topAppWindowRange = 1...30
    static let topAppIntervalRange = 5...120
    static let topAppLimitRange = 1...12
    static let halfSpeedRange = 64...102_400
    static let defaultHalfSpeedKilobytes = 1024
    static let temperatureHalfRange = 10...80
    static let defaultTemperatureHalfCelsius = 30
    static let thermalPercentRange = 0...100

    var iconOutlined: Bool {
        didSet {
            store.set(iconOutlined, forKey: Keys.iconOutlined)
            store.set(iconStyle.rawValue, forKey: Keys.iconStyle)
            onMenuBarChromeChange?()
        }
    }

    var digitPlacement: MenuBarDigitPlacement {
        didSet {
            store.set(digitPlacement.rawValue, forKey: Keys.digitPlacement)
            store.set(iconStyle.rawValue, forKey: Keys.iconStyle)
            onMenuBarChromeChange?()
        }
    }

    var iconStyle: MenuBarIconStyle {
        MenuBarIconStyle.from(outlined: iconOutlined, digits: digitPlacement)
    }

    var menuBarTint: MenuBarTintScheme {
        didSet {
            persistTint()
            onMenuBarChromeChange?()
        }
    }

    var palette: ThemePalette {
        didSet { store.set(palette.rawValue, forKey: Keys.palette) }
    }

    var ringTint: RingTintSettings {
        didSet {
            persistRingTint()
        }
    }

    var flowTint: FlowTintSettings {
        didSet {
            persistFlowTint()
        }
    }

    var ringIcons: RingIconSettings {
        didSet { persistRingIcons() }
    }

    var flowIcons: FlowIconSettings {
        didSet { persistFlowIcons() }
    }

    var savedTintLibrary: SavedTintLibrary {
        didSet { persistSavedTintLibrary() }
    }

    var savedIconLibrary: SavedIconLibrary {
        didSet { persistSavedIconLibrary() }
    }

    var menuBarActiveSavedID: UUID? {
        didSet { store.set(menuBarActiveSavedID?.uuidString, forKey: Keys.menuBarActiveSavedTint) }
    }

    var ringActiveSavedID: UUID? {
        didSet { store.set(ringActiveSavedID?.uuidString, forKey: Keys.ringActiveSavedTint) }
    }

    var flowActiveSavedID: UUID? {
        didSet { store.set(flowActiveSavedID?.uuidString, forKey: Keys.flowActiveSavedTint) }
    }

    var ringActiveSavedIconID: UUID? {
        didSet { store.set(ringActiveSavedIconID?.uuidString, forKey: Keys.ringActiveSavedIcon) }
    }

    var flowActiveSavedIconID: UUID? {
        didSet { store.set(flowActiveSavedIconID?.uuidString, forKey: Keys.flowActiveSavedIcon) }
    }

    @ObservationIgnored
    private var isApplyingSavedTint = false

    @ObservationIgnored
    private var isApplyingSavedIcon = false

    var showChargeGlyphs: Bool {
        didSet {
            store.set(showChargeGlyphs, forKey: Keys.showChargeGlyphs)
            onMenuBarChromeChange?()
        }
    }

    var motionStyle: EnergyMotionStyle {
        didSet { store.set(motionStyle.rawValue, forKey: Keys.motionStyle) }
    }

    var motionFrameRate: EnergyMotionFrameRate {
        didSet { store.set(motionFrameRate.rawValue, forKey: Keys.motionFrameRate) }
    }

    var pulseFlowIcons: Bool {
        didSet { store.set(pulseFlowIcons, forKey: Keys.pulseFlowIcons) }
    }

    /// Shared size of the glyphs drawn on the energy ribbon. 1 is the default.
    /// Typed values may sit outside the slider; the slider pins to its own ends.
    static let flowIconScaleBounds: ClosedRange<Double> = 0.1...10
    static let flowIconScaleSliderBounds: ClosedRange<Double> = 0.5...2.5

    var flowIconScale: Double {
        didSet {
            let clamped = min(max(flowIconScale, Self.flowIconScaleBounds.lowerBound), Self.flowIconScaleBounds.upperBound)
            if clamped != flowIconScale {
                flowIconScale = clamped
                return
            }
            store.set(flowIconScale, forKey: Keys.flowIconScale)
        }
    }

    var showPopoverArrow: Bool {
        didSet { store.set(showPopoverArrow, forKey: Keys.showPopoverArrow) }
    }

    var showStatusRings: Bool {
        didSet { commitPopoverVisibility(.rings, key: Keys.showStatusRings) }
    }

    /// When set, rings and the settings button split into two rows.
    var twoRingRows: Bool {
        didSet { store.set(twoRingRows, forKey: Keys.twoRingRows) }
    }

    /// Where the shorter second row sits when the cell count is odd.
    var ringOddRow: RingOddRow {
        didSet { store.set(ringOddRow.rawValue, forKey: Keys.ringOddRow) }
    }

    /// Every ring and speed slot, in the order shown in settings. Enabled ones
    /// keep this order in the popover.
    var ringCatalog: [RingSlot] {
        didSet {
            let unique = Self.uniqueSlots(ringCatalog)
            if unique != ringCatalog {
                ringCatalog = unique
                return
            }
            store.set(unique.map(\.rawValue), forKey: Keys.ringCatalog)
            storeVisibleRings()
        }
    }

    var enabledRingSlots: Set<RingSlot> {
        didSet { storeVisibleRings() }
    }

    /// Enabled slots in popover order.
    var ringOrder: [RingSlot] {
        ringCatalog.filter { enabledRingSlots.contains($0) }
    }

    func setRingSlot(_ slot: RingSlot, visible: Bool) {
        if visible {
            enabledRingSlots.insert(slot)
        } else {
            enabledRingSlots.remove(slot)
        }
    }

    func moveRingCatalogItem(_ slot: RingSlot, to target: RingSlot) {
        guard slot != target,
              let from = ringCatalog.firstIndex(of: slot),
              let destination = ringCatalog.firstIndex(of: target)
        else { return }
        var items = ringCatalog
        items.move(fromOffsets: IndexSet(integer: from), toOffset: destination > from ? destination + 1 : destination)
        ringCatalog = items
    }

    private func storeVisibleRings() {
        store.set(ringOrder.map(\.rawValue), forKey: Keys.visibleRings)
        store.set(true, forKey: Keys.ringOrderMigrated)
    }

    private static func uniqueSlots(_ slots: [RingSlot]) -> [RingSlot] {
        var seen = Set<RingSlot>()
        var unique = slots.filter { seen.insert($0).inserted }
        for slot in RingSlot.allCases where !seen.contains(slot) {
            unique.append(slot)
        }
        return unique
    }

    var showEnergyFlow: Bool {
        didSet { commitPopoverVisibility(.flow, key: Keys.showEnergyFlow) }
    }

    var showTopApps: Bool {
        didSet {
            commitPopoverVisibility(.topApps, key: Keys.showTopApps) {
                self.onTopAppSamplingChange?()
            }
        }
    }

    var showLowPower: Bool {
        didSet { commitPopoverVisibility(.lowPower, key: Keys.showLowPower) }
    }

    var showBatteryCycle: Bool {
        didSet { commitPopoverVisibility(.batteryCycle, key: Keys.showBatteryCycle) }
    }

    /// Percent, milliamp-hour ratio, or both, for the cycle block's capacity line.
    var batteryCapacityStyle: BatteryCapacityStyle {
        didSet { store.set(batteryCapacityStyle.rawValue, forKey: Keys.batteryCapacityStyle) }
    }

    /// Saved plug-in / battery policy. Nil until the user sets it or overrides the current mode.
    var lowPowerStrategy: LowPowerPreset? {
        didSet {
            if let lowPowerStrategy {
                store.set(lowPowerStrategy.rawValue, forKey: Keys.lowPowerStrategy)
            } else {
                store.removeObject(forKey: Keys.lowPowerStrategy)
            }
        }
    }

    /// Side by side when the labels fit, or always one button per row.
    var lowPowerButtonLayout: LowPowerButtonLayout {
        didSet { store.set(lowPowerButtonLayout.rawValue, forKey: Keys.lowPowerButtonLayout) }
    }

    /// Both energy-mode buttons, or exactly one of them.
    var lowPowerButtonVisibility: LowPowerButtonVisibility {
        didSet { store.set(lowPowerButtonVisibility.rawValue, forKey: Keys.lowPowerButtonVisibility) }
    }

    var showLocalIP: Bool {
        didSet {
            commitPopoverVisibility(.localIP, key: Keys.showLocalIP) {
                self.onLocalIPChange?()
            }
        }
    }

    /// Which address kinds the IP block lists. More than one can be on.
    var ipScopes: Set<IPAddressScope> {
        didSet {
            store.set(ipScopes.map(\.rawValue).sorted(), forKey: Keys.ipScopes)
            onLocalIPChange?()
        }
    }

    var ipFamilies: Set<IPAddressFamily> {
        didSet {
            store.set(ipFamilies.map(\.rawValue).sorted(), forKey: Keys.ipFamilies)
            onLocalIPChange?()
        }
    }

    var popoverOrder: [PopoverBlock] {
        didSet { store.set(popoverOrder.map(\.rawValue), forKey: Keys.popoverOrder) }
    }

    var topAppWindowMinutes: Int {
        didSet { storeClamped(\.topAppWindowMinutes, range: Self.topAppWindowRange, key: Keys.topAppWindowMinutes) }
    }

    var topAppIntervalSeconds: Int {
        didSet { storeClamped(\.topAppIntervalSeconds, range: Self.topAppIntervalRange, key: Keys.topAppIntervalSeconds) }
    }

    var topAppLimit: Int {
        didSet { storeClamped(\.topAppLimit, range: Self.topAppLimitRange, key: Keys.topAppLimit) }
    }

    /// List, horizontal bars, or vertical columns for the energy-impact block.
    var topAppsChart: TopAppsChartStyle {
        didSet { store.set(topAppsChart.rawValue, forKey: Keys.topAppsChart) }
    }

    /// Download rate that fills the ring to 50%.
    var downloadHalfKilobytes: Int {
        didSet { storeRingScale(\.downloadHalfKilobytes, range: Self.halfSpeedRange, key: Keys.downloadHalfKilobytes) }
    }

    /// Upload rate that fills the ring to 50%.
    var uploadHalfKilobytes: Int {
        didSet { storeRingScale(\.uploadHalfKilobytes, range: Self.halfSpeedRange, key: Keys.uploadHalfKilobytes) }
    }

    /// Battery temperature that fills the ring to 50%.
    var temperatureHalfCelsius: Int {
        didSet { storeRingScale(\.temperatureHalfCelsius, range: Self.temperatureHalfRange, key: Keys.temperatureHalfCelsius) }
    }

    var thermalNominalPercent: Int {
        didSet { storeRingScale(\.thermalNominalPercent, range: Self.thermalPercentRange, key: Keys.thermalNominalPercent) }
    }

    var thermalFairPercent: Int {
        didSet { storeRingScale(\.thermalFairPercent, range: Self.thermalPercentRange, key: Keys.thermalFairPercent) }
    }

    var thermalSeriousPercent: Int {
        didSet { storeRingScale(\.thermalSeriousPercent, range: Self.thermalPercentRange, key: Keys.thermalSeriousPercent) }
    }

    var thermalCriticalPercent: Int {
        didSet { storeRingScale(\.thermalCriticalPercent, range: Self.thermalPercentRange, key: Keys.thermalCriticalPercent) }
    }

    func movePopoverBlock(_ block: PopoverBlock, to target: PopoverBlock) {
        guard block != target,
              let from = popoverOrder.firstIndex(of: block),
              let destination = popoverOrder.firstIndex(of: target)
        else { return }
        var items = popoverOrder
        items.move(fromOffsets: IndexSet(integer: from), toOffset: destination > from ? destination + 1 : destination)
        popoverOrder = items
    }

    func isPopoverBlockVisible(_ block: PopoverBlock) -> Bool {
        switch block {
        case .rings: showStatusRings
        case .flow: showEnergyFlow
        case .topApps: showTopApps
        case .lowPower: showLowPower
        case .localIP: showLocalIP
        case .batteryCycle: showBatteryCycle
        case .settings: showSettingsBlock
        }
    }

    /// Hosts the settings picker may offer. Hidden blocks and the settings block are left out.
    var visibleSettingsHosts: [SettingsButtonHost] {
        popoverOrder.compactMap { block in
            guard let host = block.settingsHost, isPopoverBlockVisible(block) else { return nil }
            return host
        }
    }

    /// True when this block is shown and it is the only one. Its toggle stays on.
    func isSoleVisiblePopoverBlock(_ block: PopoverBlock) -> Bool {
        isPopoverBlockVisible(block) && !popoverOrder.contains { $0 != block && isPopoverBlockVisible($0) }
    }

    private func commitPopoverVisibility(_ block: PopoverBlock, key: String, sideEffect: (() -> Void)? = nil) {
        if !isPopoverBlockVisible(block), !popoverOrder.contains(where: isPopoverBlockVisible) {
            revealPopoverBlock(block)
            return
        }
        store.set(isPopoverBlockVisible(block), forKey: key)
        sideEffect?()
        keepSettingsButtonOffHiddenHost()
    }

    /// Stored panels with every block off come back with the first block in order (rings if the order is empty).
    private func ensureOnePopoverBlockVisible() {
        if popoverOrder.contains(where: isPopoverBlockVisible) { return }
        let target = popoverOrder.first ?? .rings
        revealPopoverBlock(target)
        store.set(true, forKey: visibilityKey(for: target))
    }

    private func visibilityKey(for block: PopoverBlock) -> String {
        switch block {
        case .rings: Keys.showStatusRings
        case .flow: Keys.showEnergyFlow
        case .topApps: Keys.showTopApps
        case .lowPower: Keys.showLowPower
        case .localIP: Keys.showLocalIP
        case .batteryCycle: Keys.showBatteryCycle
        case .settings: Keys.showSettingsBlock
        }
    }

    private func revealPopoverBlock(_ block: PopoverBlock) {
        switch block {
        case .rings: showStatusRings = true
        case .flow: showEnergyFlow = true
        case .topApps: showTopApps = true
        case .lowPower: showLowPower = true
        case .localIP: showLocalIP = true
        case .batteryCycle: showBatteryCycle = true
        case .settings: showSettingsBlock = true
        }
    }

    /// A hidden host does not keep the button. Move forward through the panel order, then wrap once.
    private func keepSettingsButtonOffHiddenHost() {
        guard settingsButtonPlacement == .insideBlock else { return }
        guard !isPopoverBlockVisible(settingsButtonHost.popoverBlock) else { return }
        if let next = SettingsButtonHost.nextVisible(
            after: settingsButtonHost,
            order: popoverOrder,
            isVisible: isPopoverBlockVisible
        ) {
            settingsButtonHost = next
        } else {
            settingsButtonPlacement = .ownBlock
            if !showSettingsBlock {
                showSettingsBlock = true
            }
        }
    }

    private func storeRingScale(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>, range: ClosedRange<Int>, key: String) {
        let clamped = min(range.upperBound, max(range.lowerBound, self[keyPath: keyPath]))
        if clamped != self[keyPath: keyPath] {
            self[keyPath: keyPath] = clamped
            return
        }
        store.set(clamped, forKey: key)
    }

    private func storeClamped(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>, range: ClosedRange<Int>, key: String) {
        let clamped = min(range.upperBound, max(range.lowerBound, self[keyPath: keyPath]))
        if clamped != self[keyPath: keyPath] {
            self[keyPath: keyPath] = clamped
            return
        }
        store.set(clamped, forKey: key)
        onTopAppSamplingChange?()
    }

    private static func restoredPopoverOrder(from defaults: UserDefaults) -> [PopoverBlock] {
        let stored = defaults.stringArray(forKey: Keys.popoverOrder)?.compactMap(PopoverBlock.init(rawValue:)) ?? []
        var seen = Set<PopoverBlock>()
        var order = stored.filter { seen.insert($0).inserted }
        for block in PopoverBlock.allCases where !seen.contains(block) {
            order.append(block)
        }
        return order
    }

    private static func clampedStoredInteger(
        _ defaults: UserDefaults,
        key: String,
        fallback: Int,
        range: ClosedRange<Int>
    ) -> Int {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return min(range.upperBound, max(range.lowerBound, defaults.integer(forKey: key)))
    }

    /// Ring cell unless the user picks another placement. Unknown stored values read as the ring cell.
    var settingsButtonPlacement: SettingsButtonPlacement {
        didSet {
            store.set(settingsButtonPlacement.rawValue, forKey: Keys.settingsButtonPlacement)
            if settingsButtonPlacement == .insideBlock {
                keepSettingsButtonOffHiddenHost()
            }
        }
    }

    /// Host block used when the button sits inside an existing block.
    var settingsButtonHost: SettingsButtonHost {
        didSet { store.set(settingsButtonHost.rawValue, forKey: Keys.settingsButtonHost) }
    }

    /// Show or hide the standalone settings block in the panel list.
    var showSettingsBlock: Bool {
        didSet { commitPopoverVisibility(.settings, key: Keys.showSettingsBlock) }
    }

    var automaticallyCheckForUpdates: Bool {
        didSet { store.set(automaticallyCheckForUpdates, forKey: Keys.automaticallyCheckForUpdates) }
    }

    var language: AppLanguage {
        didSet {
            store.set(language.rawValue, forKey: Keys.language)
            clearLegacyAppleLanguages()
        }
    }

    var resolvedLocale: Locale { language.resolvedLocale }

    init(defaults: UserDefaults = .standard) {
        store = defaults
        let iconRaw = defaults.string(forKey: Keys.iconStyle) ?? MenuBarIconStyle.systemPercentInside.rawValue
        let legacyStyle = MenuBarIconStyle(rawValue: iconRaw) ?? .systemPercentInside
        let outlined: Bool
        if defaults.object(forKey: Keys.iconOutlined) == nil {
            outlined = legacyStyle.isOutlined
        } else {
            outlined = defaults.bool(forKey: Keys.iconOutlined)
        }
        let digits: MenuBarDigitPlacement
        if let storedDigits = defaults.string(forKey: Keys.digitPlacement),
           let parsed = MenuBarDigitPlacement(rawValue: storedDigits) {
            digits = parsed
        } else {
            digits = legacyStyle.digits
        }
        iconOutlined = outlined
        digitPlacement = digits

        let paletteRaw = defaults.string(forKey: Keys.palette) ?? ThemePalette.semantic.rawValue
        let resolvedPalette = ThemePalette(rawValue: paletteRaw) ?? .semantic
        palette = resolvedPalette

        let seededPreset = PopoverTintPreset(palette: resolvedPalette)
        if let data = defaults.data(forKey: Keys.ringTint),
           let decoded = try? JSONDecoder().decode(RingTintSettings.self, from: data) {
            ringTint = decoded.withRoundedDefaultStops()
        } else {
            ringTint = .preset(seededPreset)
        }
        if let data = defaults.data(forKey: Keys.flowTint),
           let decoded = try? JSONDecoder().decode(FlowTintSettings.self, from: data) {
            flowTint = decoded
        } else {
            flowTint = .preset(seededPreset)
        }

        if let data = defaults.data(forKey: Keys.ringIcons),
           let decoded = try? JSONDecoder().decode(RingIconSettings.self, from: data) {
            ringIcons = decoded
        } else {
            ringIcons = .classic
        }
        if let data = defaults.data(forKey: Keys.flowIcons),
           let decoded = try? JSONDecoder().decode(FlowIconSettings.self, from: data) {
            flowIcons = decoded
        } else {
            flowIcons = .classic
        }

        let tint: MenuBarTintScheme
        if let data = defaults.data(forKey: Keys.menuBarTint),
           let scheme = try? JSONDecoder().decode(MenuBarTintScheme.self, from: data) {
            tint = scheme.normalized()
        } else if defaults.object(forKey: Keys.lowBatteryTintEnabled) != nil,
                  defaults.bool(forKey: Keys.lowBatteryTintEnabled) == false {
            tint = .off
        } else {
            tint = .systemDefault
        }
        menuBarTint = tint

        let library: SavedTintLibrary
        if let data = defaults.data(forKey: Keys.savedTintLibrary),
           let decoded = try? JSONDecoder().decode(SavedTintLibrary.self, from: data) {
            library = decoded
        } else {
            library = .empty
        }
        savedTintLibrary = library

        let iconLibrary: SavedIconLibrary
        if let data = defaults.data(forKey: Keys.savedIconLibrary),
           let decoded = try? JSONDecoder().decode(SavedIconLibrary.self, from: data) {
            iconLibrary = decoded
        } else {
            iconLibrary = .empty
        }
        savedIconLibrary = iconLibrary

        if let raw = defaults.string(forKey: Keys.menuBarActiveSavedTint),
           let id = UUID(uuidString: raw),
           library.menuBar.contains(where: { $0.id == id }) {
            menuBarActiveSavedID = id
        } else {
            menuBarActiveSavedID = nil
        }
        if let raw = defaults.string(forKey: Keys.ringActiveSavedTint),
           let id = UUID(uuidString: raw),
           library.ring.contains(where: { $0.id == id }) {
            ringActiveSavedID = id
        } else {
            ringActiveSavedID = nil
        }
        if let raw = defaults.string(forKey: Keys.flowActiveSavedTint),
           let id = UUID(uuidString: raw),
           library.flow.contains(where: { $0.id == id }) {
            flowActiveSavedID = id
        } else {
            flowActiveSavedID = nil
        }
        if let raw = defaults.string(forKey: Keys.ringActiveSavedIcon),
           let id = UUID(uuidString: raw),
           iconLibrary.ring.contains(where: { $0.id == id }) {
            ringActiveSavedIconID = id
        } else {
            ringActiveSavedIconID = nil
        }
        if let raw = defaults.string(forKey: Keys.flowActiveSavedIcon),
           let id = UUID(uuidString: raw),
           iconLibrary.flow.contains(where: { $0.id == id }) {
            flowActiveSavedIconID = id
        } else {
            flowActiveSavedIconID = nil
        }

        if defaults.object(forKey: Keys.showChargeGlyphs) == nil {
            showChargeGlyphs = true
        } else {
            showChargeGlyphs = defaults.bool(forKey: Keys.showChargeGlyphs)
        }

        if defaults.object(forKey: Keys.pulseFlowIcons) == nil {
            pulseFlowIcons = true
        } else {
            pulseFlowIcons = defaults.bool(forKey: Keys.pulseFlowIcons)
        }

        if defaults.object(forKey: Keys.flowIconScale) == nil {
            flowIconScale = 1
        } else {
            flowIconScale = defaults.double(forKey: Keys.flowIconScale)
        }

        if defaults.object(forKey: Keys.showPopoverArrow) == nil {
            showPopoverArrow = true
        } else {
            showPopoverArrow = defaults.bool(forKey: Keys.showPopoverArrow)
        }

        if defaults.object(forKey: Keys.showStatusRings) == nil {
            showStatusRings = true
        } else {
            showStatusRings = defaults.bool(forKey: Keys.showStatusRings)
        }

        if defaults.object(forKey: Keys.twoRingRows) == nil {
            twoRingRows = false
        } else {
            twoRingRows = defaults.bool(forKey: Keys.twoRingRows)
        }

        ringOddRow = RingOddRow(rawValue: defaults.string(forKey: Keys.ringOddRow) ?? "") ?? .stagger

        let enabled = Self.restoredRingOrder(from: defaults)
        enabledRingSlots = Set(enabled)
        if let storedCatalog = defaults.stringArray(forKey: Keys.ringCatalog)?.compactMap(RingSlot.init(rawValue:)),
           !storedCatalog.isEmpty {
            ringCatalog = Self.uniqueSlots(storedCatalog)
        } else {
            ringCatalog = enabled + RingSlot.allCases.filter { !enabled.contains($0) }
        }

        if defaults.object(forKey: Keys.showEnergyFlow) == nil {
            showEnergyFlow = true
        } else {
            showEnergyFlow = defaults.bool(forKey: Keys.showEnergyFlow)
        }

        if defaults.object(forKey: Keys.showTopApps) == nil {
            showTopApps = true
        } else {
            showTopApps = defaults.bool(forKey: Keys.showTopApps)
        }

        if defaults.object(forKey: Keys.showLowPower) == nil {
            showLowPower = true
        } else {
            showLowPower = defaults.bool(forKey: Keys.showLowPower)
        }
        lowPowerStrategy = defaults.string(forKey: Keys.lowPowerStrategy).flatMap(LowPowerPreset.init(rawValue:))
        lowPowerButtonLayout = LowPowerButtonLayout.resolved(
            stored: defaults.string(forKey: Keys.lowPowerButtonLayout)
        )
        lowPowerButtonVisibility = LowPowerButtonVisibility.resolved(
            stored: defaults.string(forKey: Keys.lowPowerButtonVisibility)
        )

        if defaults.object(forKey: Keys.showLocalIP) == nil {
            showLocalIP = true
        } else {
            showLocalIP = defaults.bool(forKey: Keys.showLocalIP)
        }

        if defaults.object(forKey: Keys.showBatteryCycle) == nil {
            showBatteryCycle = true
        } else {
            showBatteryCycle = defaults.bool(forKey: Keys.showBatteryCycle)
        }
        if defaults.object(forKey: Keys.showSettingsBlock) == nil {
            showSettingsBlock = true
        } else {
            showSettingsBlock = defaults.bool(forKey: Keys.showSettingsBlock)
        }
        batteryCapacityStyle = BatteryCapacityStyle.resolved(
            stored: defaults.string(forKey: Keys.batteryCapacityStyle)
        )
        if defaults.object(forKey: Keys.ipScopes) == nil {
            ipScopes = [.local]
        } else {
            ipScopes = Set(defaults.stringArray(forKey: Keys.ipScopes)?.compactMap(IPAddressScope.init(rawValue:)) ?? [])
        }
        if defaults.object(forKey: Keys.ipFamilies) == nil {
            ipFamilies = [.ipv4, .ipv6]
        } else {
            ipFamilies = Set(defaults.stringArray(forKey: Keys.ipFamilies)?.compactMap(IPAddressFamily.init(rawValue:)) ?? [])
        }

        popoverOrder = Self.restoredPopoverOrder(from: defaults)
        topAppWindowMinutes = Self.clampedStoredInteger(
            defaults,
            key: Keys.topAppWindowMinutes,
            fallback: Self.defaultTopAppWindowMinutes,
            range: Self.topAppWindowRange
        )
        topAppIntervalSeconds = Self.clampedStoredInteger(
            defaults,
            key: Keys.topAppIntervalSeconds,
            fallback: Self.defaultTopAppIntervalSeconds,
            range: Self.topAppIntervalRange
        )
        topAppLimit = Self.clampedStoredInteger(
            defaults,
            key: Keys.topAppLimit,
            fallback: Self.defaultTopAppLimit,
            range: Self.topAppLimitRange
        )
        topAppsChart = TopAppsChartStyle.resolved(stored: defaults.string(forKey: Keys.topAppsChart))
        downloadHalfKilobytes = Self.clampedStoredInteger(
            defaults,
            key: Keys.downloadHalfKilobytes,
            fallback: Self.defaultHalfSpeedKilobytes,
            range: Self.halfSpeedRange
        )
        uploadHalfKilobytes = Self.clampedStoredInteger(
            defaults,
            key: Keys.uploadHalfKilobytes,
            fallback: Self.defaultHalfSpeedKilobytes,
            range: Self.halfSpeedRange
        )
        temperatureHalfCelsius = Self.clampedStoredInteger(
            defaults,
            key: Keys.temperatureHalfCelsius,
            fallback: Self.defaultTemperatureHalfCelsius,
            range: Self.temperatureHalfRange
        )
        thermalNominalPercent = Self.clampedStoredInteger(
            defaults,
            key: Keys.thermalNominalPercent,
            fallback: 25,
            range: Self.thermalPercentRange
        )
        thermalFairPercent = Self.clampedStoredInteger(
            defaults,
            key: Keys.thermalFairPercent,
            fallback: 50,
            range: Self.thermalPercentRange
        )
        thermalSeriousPercent = Self.clampedStoredInteger(
            defaults,
            key: Keys.thermalSeriousPercent,
            fallback: 75,
            range: Self.thermalPercentRange
        )
        thermalCriticalPercent = Self.clampedStoredInteger(
            defaults,
            key: Keys.thermalCriticalPercent,
            fallback: 100,
            range: Self.thermalPercentRange
        )

        settingsButtonPlacement = SettingsButtonPlacement.resolved(
            stored: defaults.string(forKey: Keys.settingsButtonPlacement)
        )
        settingsButtonHost = SettingsButtonHost.resolved(
            stored: defaults.string(forKey: Keys.settingsButtonHost)
        )

        if defaults.object(forKey: Keys.automaticallyCheckForUpdates) == nil {
            automaticallyCheckForUpdates = true
        } else {
            automaticallyCheckForUpdates = defaults.bool(forKey: Keys.automaticallyCheckForUpdates)
        }

        let storedMotion = defaults.string(forKey: Keys.motionStyle)
            ?? defaults.string(forKey: Keys.legacyEnergyMotion)
        let resolvedMotion = EnergyMotionStyle.resolved(stored: storedMotion)
        motionStyle = resolvedMotion
        if defaults.object(forKey: Keys.motionFrameRate) == nil {
            motionFrameRate = .hz60
        } else {
            motionFrameRate = EnergyMotionFrameRate.resolved(stored: defaults.integer(forKey: Keys.motionFrameRate))
        }
        language = AppLanguage.resolved(stored: defaults.string(forKey: Keys.language))
        ensureOnePopoverBlockVisible()
        keepSettingsButtonOffHiddenHost()

        store.set(resolvedMotion.rawValue, forKey: Keys.motionStyle)
        store.set(settingsButtonPlacement.rawValue, forKey: Keys.settingsButtonPlacement)
        store.set(settingsButtonHost.rawValue, forKey: Keys.settingsButtonHost)
        store.set(showSettingsBlock, forKey: Keys.showSettingsBlock)
        store.set(lowPowerButtonLayout.rawValue, forKey: Keys.lowPowerButtonLayout)
        store.set(lowPowerButtonVisibility.rawValue, forKey: Keys.lowPowerButtonVisibility)
        store.set(batteryCapacityStyle.rawValue, forKey: Keys.batteryCapacityStyle)
        store.set(MenuBarIconStyle.from(outlined: outlined, digits: digits).rawValue, forKey: Keys.iconStyle)
        store.set(outlined, forKey: Keys.iconOutlined)
        store.set(digits.rawValue, forKey: Keys.digitPlacement)
        persistTint()
        persistRingTint()
        persistFlowTint()
        persistSavedTintLibrary()
        persistRingIcons()
        persistFlowIcons()
        if defaults.object(forKey: Keys.legacyEnergyMotion) != nil {
            store.removeObject(forKey: Keys.legacyEnergyMotion)
        }
        clearLegacyAppleLanguages()
    }

    var lowBatteryTintEnabled: Bool {
        menuBarTint.preset != .off
    }

    func applyTintPreset(_ preset: MenuBarTintPreset) {
        menuBarActiveSavedID = nil
        if preset == .custom {
            if menuBarTint.preset == .off {
                menuBarTint = MenuBarTintScheme.systemDefault.markedCustom()
            } else {
                menuBarTint = menuBarTint.markedCustom()
            }
            return
        }
        menuBarTint = .preset(preset)
    }

    func applyRingTintPreset(_ preset: PopoverTintPreset) {
        ringActiveSavedID = nil
        if preset == .custom {
            ringTint = ringTint.markedCustom()
            return
        }
        ringTint = .preset(preset)
        if let themePalette = preset.themePalette {
            palette = themePalette
        }
    }

    func applyFlowTintPreset(_ preset: PopoverTintPreset) {
        flowActiveSavedID = nil
        if preset == .custom {
            flowTint = flowTint.markedCustom()
            return
        }
        flowTint = .preset(preset)
        if let themePalette = preset.themePalette {
            palette = themePalette
        }
    }

    func applyRingIconPreset(_ preset: RingIconPreset) {
        ringActiveSavedIconID = nil
        if preset == .custom {
            ringIcons = ringIcons.markedCustom()
            return
        }
        ringIcons = .preset(preset)
    }

    func applyFlowIconPreset(_ preset: FlowIconPreset) {
        flowActiveSavedIconID = nil
        if preset == .custom {
            flowIcons = flowIcons.markedCustom()
            return
        }
        flowIcons = .preset(preset)
    }

    @discardableResult
    func saveMenuBarTintPreset(named name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let before = Set(savedTintLibrary.menuBar.map(\.id))
        savedTintLibrary = savedTintLibrary.addingMenuBar(name: trimmed, scheme: menuBarTint)
        let id = savedTintLibrary.menuBar.first(where: { !before.contains($0.id) })?.id
            ?? savedTintLibrary.menuBar.last?.id
        guard let id else { return nil }
        isApplyingSavedTint = true
        menuBarActiveSavedID = id
        isApplyingSavedTint = false
        return id
    }

    @discardableResult
    func updateMenuBarTintPreset() -> Bool {
        guard let id = menuBarActiveSavedID,
              savedTintLibrary.menuBar.contains(where: { $0.id == id }) else { return false }
        savedTintLibrary = savedTintLibrary.updatingMenuBar(id: id, scheme: menuBarTint)
        return true
    }

    @discardableResult
    func saveRingTintPreset(named name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let before = Set(savedTintLibrary.ring.map(\.id))
        savedTintLibrary = savedTintLibrary.addingRing(name: trimmed, settings: ringTint)
        let id = savedTintLibrary.ring.first(where: { !before.contains($0.id) })?.id
            ?? savedTintLibrary.ring.last?.id
        guard let id else { return nil }
        isApplyingSavedTint = true
        ringActiveSavedID = id
        isApplyingSavedTint = false
        return id
    }

    @discardableResult
    func updateRingTintPreset() -> Bool {
        guard let id = ringActiveSavedID,
              savedTintLibrary.ring.contains(where: { $0.id == id }) else { return false }
        savedTintLibrary = savedTintLibrary.updatingRing(id: id, settings: ringTint)
        return true
    }

    @discardableResult
    func saveFlowTintPreset(named name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let before = Set(savedTintLibrary.flow.map(\.id))
        savedTintLibrary = savedTintLibrary.addingFlow(name: trimmed, settings: flowTint)
        let id = savedTintLibrary.flow.first(where: { !before.contains($0.id) })?.id
            ?? savedTintLibrary.flow.last?.id
        guard let id else { return nil }
        isApplyingSavedTint = true
        flowActiveSavedID = id
        isApplyingSavedTint = false
        return id
    }

    @discardableResult
    func updateFlowTintPreset() -> Bool {
        guard let id = flowActiveSavedID,
              savedTintLibrary.flow.contains(where: { $0.id == id }) else { return false }
        savedTintLibrary = savedTintLibrary.updatingFlow(id: id, settings: flowTint)
        return true
    }

    @discardableResult
    func saveRingIconPreset(named name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let before = Set(savedIconLibrary.ring.map(\.id))
        savedIconLibrary = savedIconLibrary.addingRing(name: trimmed, settings: ringIcons)
        let id = savedIconLibrary.ring.first(where: { !before.contains($0.id) })?.id
            ?? savedIconLibrary.ring.last?.id
        guard let id else { return nil }
        isApplyingSavedIcon = true
        ringActiveSavedIconID = id
        isApplyingSavedIcon = false
        return id
    }

    @discardableResult
    func updateRingIconPreset() -> Bool {
        guard let id = ringActiveSavedIconID,
              savedIconLibrary.ring.contains(where: { $0.id == id }) else { return false }
        savedIconLibrary = savedIconLibrary.updatingRing(id: id, settings: ringIcons)
        return true
    }

    @discardableResult
    func saveFlowIconPreset(named name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let before = Set(savedIconLibrary.flow.map(\.id))
        savedIconLibrary = savedIconLibrary.addingFlow(name: trimmed, settings: flowIcons)
        let id = savedIconLibrary.flow.first(where: { !before.contains($0.id) })?.id
            ?? savedIconLibrary.flow.last?.id
        guard let id else { return nil }
        isApplyingSavedIcon = true
        flowActiveSavedIconID = id
        isApplyingSavedIcon = false
        return id
    }

    @discardableResult
    func updateFlowIconPreset() -> Bool {
        guard let id = flowActiveSavedIconID,
              savedIconLibrary.flow.contains(where: { $0.id == id }) else { return false }
        savedIconLibrary = savedIconLibrary.updatingFlow(id: id, settings: flowIcons)
        return true
    }

    func applySavedMenuBarTint(id: UUID) {
        guard let item = savedTintLibrary.menuBar.first(where: { $0.id == id }) else { return }
        isApplyingSavedTint = true
        menuBarActiveSavedID = id
        menuBarTint = item.payload
        isApplyingSavedTint = false
    }

    func applySavedRingTint(id: UUID) {
        guard let item = savedTintLibrary.ring.first(where: { $0.id == id }) else { return }
        isApplyingSavedTint = true
        ringActiveSavedID = id
        ringTint = item.payload
        isApplyingSavedTint = false
    }

    func applySavedFlowTint(id: UUID) {
        guard let item = savedTintLibrary.flow.first(where: { $0.id == id }) else { return }
        isApplyingSavedTint = true
        flowActiveSavedID = id
        flowTint = item.payload
        isApplyingSavedTint = false
    }

    func applySavedRingIcon(id: UUID) {
        guard let item = savedIconLibrary.ring.first(where: { $0.id == id }) else { return }
        isApplyingSavedIcon = true
        ringActiveSavedIconID = id
        ringIcons = item.payload
        isApplyingSavedIcon = false
    }

    func applySavedFlowIcon(id: UUID) {
        guard let item = savedIconLibrary.flow.first(where: { $0.id == id }) else { return }
        isApplyingSavedIcon = true
        flowActiveSavedIconID = id
        flowIcons = item.payload
        isApplyingSavedIcon = false
    }

    func deleteSavedMenuBarTint(id: UUID) {
        savedTintLibrary = savedTintLibrary.removingMenuBar(id: id)
        if menuBarActiveSavedID == id {
            menuBarActiveSavedID = nil
        }
    }

    func deleteSavedRingTint(id: UUID) {
        savedTintLibrary = savedTintLibrary.removingRing(id: id)
        if ringActiveSavedID == id {
            ringActiveSavedID = nil
        }
    }

    func deleteSavedFlowTint(id: UUID) {
        savedTintLibrary = savedTintLibrary.removingFlow(id: id)
        if flowActiveSavedID == id {
            flowActiveSavedID = nil
        }
    }

    func deleteSavedRingIcon(id: UUID) {
        savedIconLibrary = savedIconLibrary.removingRing(id: id)
        if ringActiveSavedIconID == id {
            ringActiveSavedIconID = nil
        }
    }

    func deleteSavedFlowIcon(id: UUID) {
        savedIconLibrary = savedIconLibrary.removingFlow(id: id)
        if flowActiveSavedIconID == id {
            flowActiveSavedIconID = nil
        }
    }

    private func persistTint() {
        if let data = try? JSONEncoder().encode(menuBarTint) {
            store.set(data, forKey: Keys.menuBarTint)
        }
        store.set(menuBarTint.preset != .off, forKey: Keys.lowBatteryTintEnabled)
    }

    private func persistRingTint() {
        if let data = try? JSONEncoder().encode(ringTint) {
            store.set(data, forKey: Keys.ringTint)
        }
    }

    private func persistFlowTint() {
        if let data = try? JSONEncoder().encode(flowTint) {
            store.set(data, forKey: Keys.flowTint)
        }
    }

    private func persistRingIcons() {
        if let data = try? JSONEncoder().encode(ringIcons) {
            store.set(data, forKey: Keys.ringIcons)
        }
    }

    private func persistFlowIcons() {
        if let data = try? JSONEncoder().encode(flowIcons) {
            store.set(data, forKey: Keys.flowIcons)
        }
    }

    private func persistSavedTintLibrary() {
        if let data = try? JSONEncoder().encode(savedTintLibrary) {
            store.set(data, forKey: Keys.savedTintLibrary)
        }
    }

    private func persistSavedIconLibrary() {
        if let data = try? JSONEncoder().encode(savedIconLibrary) {
            store.set(data, forKey: Keys.savedIconLibrary)
        }
    }

    /// In-app language is resolved from `*.lproj` at runtime. Writing
    /// `AppleLanguages` only takes effect on the next launch and fights live switching.
    private func clearLegacyAppleLanguages() {
        store.removeObject(forKey: Keys.appleLanguages)
    }
}
