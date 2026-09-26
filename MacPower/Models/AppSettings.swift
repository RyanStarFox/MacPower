import Foundation
import Observation

@Observable
final class AppSettings {
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
        static let showEnergyFlow = "showEnergyFlow"
        static let menuBarRightClickAction = "menuBarRightClickAction"
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
        didSet { store.set(showStatusRings, forKey: Keys.showStatusRings) }
    }

    var showEnergyFlow: Bool {
        didSet { store.set(showEnergyFlow, forKey: Keys.showEnergyFlow) }
    }

    var menuBarRightClickAction: MenuBarRightClickAction {
        didSet { store.set(menuBarRightClickAction.rawValue, forKey: Keys.menuBarRightClickAction) }
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

        if defaults.object(forKey: Keys.showEnergyFlow) == nil {
            showEnergyFlow = true
        } else {
            showEnergyFlow = defaults.bool(forKey: Keys.showEnergyFlow)
        }

        menuBarRightClickAction = MenuBarRightClickAction.resolved(
            stored: defaults.string(forKey: Keys.menuBarRightClickAction)
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

        store.set(resolvedMotion.rawValue, forKey: Keys.motionStyle)
        store.set(menuBarRightClickAction.rawValue, forKey: Keys.menuBarRightClickAction)
        store.set(MenuBarIconStyle.from(outlined: outlined, digits: digits).rawValue, forKey: Keys.iconStyle)
        store.set(outlined, forKey: Keys.iconOutlined)
        store.set(digits.rawValue, forKey: Keys.digitPlacement)
        persistTint()
        persistRingTint()
        persistFlowTint()
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
