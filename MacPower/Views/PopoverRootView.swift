import AppKit
import SwiftUI

enum PopoverLayout {
    /// Minimum panel width shared with `StatusItemController`. One row widens
    /// to fit every cell. Two rows use the longer row. macOS 15 clips the panel
    /// when this width and the SwiftUI frame disagree.
    static let width: CGFloat = 420
    static let padding: CGFloat = 14
    static let ringSpacing: CGFloat = 6
    /// Pitch of one cell when five of them fill the minimum panel. Rows of three
    /// or more keep this pitch instead of stretching across the panel.
    static var ringColumn: CGFloat {
        (width - padding * 2 - 4 * ringSpacing) / 5
    }

    /// Three-across is a little roomier than the five-across pitch. Four or more stay on that pitch.
    static func ringPitch(columns: Int) -> (column: CGFloat, spacing: CGFloat) {
        if columns == 3 {
            return (ringColumn * 1.25, ringSpacing * 1.25)
        }
        return (ringColumn, ringSpacing)
    }

    static func width(rowCounts: [Int]) -> CGFloat {
        width(ringCount: rowCounts.max() ?? 0, twoRows: false, includesSettings: false)
    }

    static func width(ringCount: Int, twoRows: Bool, includesSettings: Bool = true) -> CGFloat {
        let count = columns(ringCount: ringCount, twoRows: twoRows, includesSettings: includesSettings)
        let pitch = ringPitch(columns: count)
        let columns = CGFloat(count)
        let gaps = max(columns - 1, 0) * pitch.spacing
        let natural = (padding * 2 + columns * pitch.column + gaps).rounded(.up)
        // One or two cells stay on the wide panel so the battery section keeps
        // its normal width. Three or more shrink the panel to the ring pitch.
        if count >= 3 {
            return natural
        }
        return max(width, natural)
    }

    /// Cells on the wider row. The settings gear is one cell only while it lives in the ring grid.
    static func columns(ringCount: Int, twoRows: Bool, includesSettings: Bool = true) -> Int {
        let total = max(ringCount, 0) + (includesSettings ? 1 : 0)
        if twoRows, total >= 2 {
            return (total + 1) / 2
        }
        return total
    }
}

struct PopoverRootView: View {
    @Bindable var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.readmeGalleryCapture) private var readmeGalleryCapture
    /// Stays false through the open layout. The ring block used to ease up
    /// from the short placeholder frame; arming progress animation on that
    /// same turn is what floats both rows into the grid.
    @State private var ringPlacementSettled = false

    var body: some View {
        Group {
            if appState.isPopoverOpen {
                let theme = AppTheme.resolved(palette: appState.settings.palette, colorScheme: colorScheme)
                content(theme: theme)
                    .padding(PopoverLayout.padding)
                    .frame(width: panelWidth, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.identity)
            } else {
                // Keep the hosting graph mounted, but never build glass / TimelineView
                // while the menu extra is idle. Interactive Liquid Glass in a hidden
                // NSPopover was burning CPU and UAFing NSViewFocusProxy ~2s after launch.
                // Match the open width so the first real layout is not a resize.
                Color.clear
                    .frame(width: panelWidth, height: 1)
                    .transition(.identity)
            }
        }
        .animation(nil, value: appState.isPopoverOpen)
        .environment(\.locale, appState.settings.resolvedLocale)
        .id(appState.settings.language)
    }

    private var panelWidth: CGFloat {
        guard showsRingBlock else { return PopoverLayout.width }
        let counts = ringRowCounts
        guard counts.contains(where: { $0 > 0 }) else { return PopoverLayout.width }
        return PopoverLayout.width(rowCounts: counts)
    }

    private var showsRingBlock: Bool {
        appState.settings.showStatusRings
            && appState.settings.displayedRingRows(seen: appState.bluetoothDevices).contains { !$0.isEmpty }
    }

    private func compactPopoverEntries(_ entries: [PopoverEntry], showRings: Bool) -> [PopoverEntry] {
        var kept = entries
        if !showRings {
            kept.removeAll { $0.block == .rings }
        }
        var result: [PopoverEntry] = []
        for entry in kept {
            if entry.isDivider {
                if result.isEmpty || result.last?.isDivider == true { continue }
                result.append(entry)
            } else {
                result.append(entry)
            }
        }
        while result.last?.isDivider == true {
            result.removeLast()
        }
        return result
    }

    private var ringRowCounts: [Int] {
        var counts = appState.settings.displayedRingRows(seen: appState.bluetoothDevices).map(\.count)
        if settingsGearInRings {
            if counts.isEmpty { counts = [1] } else { counts[counts.count - 1] += 1 }
        }
        return counts
    }

    private var settingsGearInRings: Bool {
        appState.settings.settingsButtonPlacement.drawsRingGear(
            host: appState.settings.settingsButtonHost,
            ringsVisible: appState.settings.showStatusRings
        )
    }

    private var settingsGearBesideFlow: Bool {
        appState.settings.settingsButtonPlacement.drawsFlowGear(
            host: appState.settings.settingsButtonHost,
            flowVisible: appState.settings.showEnergyFlow
        )
    }

    private func showsHeaderSettings(on section: SettingsButtonHost) -> Bool {
        appState.settings.settingsButtonPlacement.drawsHeader(
            host: appState.settings.settingsButtonHost,
            section: section,
            sectionVisible: true
        )
    }

    @ViewBuilder
    private func content(theme: AppTheme) -> some View {
        if !appState.snapshot.hasBattery {
            Text(Localization.string("error.needsBattery", language: appState.settings.language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            let showRings = showsRingBlock
            let showFlow = appState.settings.showEnergyFlow
            let entries = compactPopoverEntries(appState.settings.renderedPopoverEntries, showRings: showRings)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    switch entry {
                    case .block(let block):
                        popoverBlock(block, theme: theme, showRings: showRings, showFlow: showFlow)
                            .padding(.top, index == 0 ? 0 : 14)
                    case .divider:
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                            .accessibilityHidden(true)
                    }
                }
            }
            .onChange(of: appState.settings.showTopApps) { _, _ in
                appState.syncPopoverExtras()
            }
            .onChange(of: appState.settings.showLowPower) { _, _ in
                appState.syncPopoverExtras()
            }
        }
    }

    @ViewBuilder
    private func popoverBlock(_ block: PopoverBlock, theme: AppTheme, showRings: Bool, showFlow: Bool) -> some View {
        switch block {
        case .rings:
            if showRings {
                ringsHeader
            }
        case .flow:
            if showFlow {
                VStack(alignment: .leading, spacing: 4) {
                    TimeEstimateRow(snapshot: appState.snapshot, language: appState.settings.language)
                    if settingsGearBesideFlow {
                        // Gear-only layout height so HStack can center it on the
                        // ribbon; caption is painted below without shifting alignment.
                        energyFlow(theme: theme) {
                            flowSideSettingsButton
                        }
                    } else {
                        energyFlow(theme: theme)
                    }
                }
            }
        case .topApps:
            if appState.settings.showTopApps {
                TopAppsSection(
                    list: appState.topApps,
                    language: appState.settings.language,
                    rowCount: appState.settings.topAppLimit,
                    chart: appState.settings.topAppsChart,
                    showsSettingsButton: showsHeaderSettings(on: .topApps),
                    onOpenSettings: { appState.openSettings() }
                )
            }
        case .lowPower:
            if appState.settings.showLowPower {
                LowPowerSection(
                    strategy: appState.settings.lowPowerStrategy ?? appState.lowPowerPreset,
                    lowPowerOn: appState.lowPowerNow,
                    failed: appState.lowPowerChangeFailed,
                    language: appState.settings.language,
                    panelWidth: panelWidth,
                    layout: appState.settings.lowPowerButtonLayout,
                    visibility: appState.settings.lowPowerButtonVisibility,
                    onStrategy: { appState.setLowPowerStrategy($0) },
                    onToggleNow: { appState.toggleLowPowerNow() },
                    showsSettingsButton: showsHeaderSettings(on: .lowPower),
                    onOpenSettings: { appState.openSettings() }
                )
            }
        case .localIP:
            if appState.settings.showLocalIP {
                LocalIPSection(
                    rows: LocalIPFilter.rows(
                        interfaces: appState.localIPInterfaces,
                        scopes: appState.settings.ipScopes,
                        families: appState.settings.ipFamilies,
                        publicIPv4: appState.publicIPv4,
                        publicIPv6: appState.publicIPv6,
                        publicIPv4Failed: appState.publicIPv4Failed,
                        publicIPv6Failed: appState.publicIPv6Failed
                    ),
                    language: appState.settings.language,
                    panelWidth: panelWidth,
                    showsSettingsButton: showsHeaderSettings(on: .localIP),
                    onOpenSettings: { appState.openSettings() }
                )
            }
        case .batteryCycle:
            if appState.settings.showBatteryCycle {
                BatteryCycleSection(
                    hasBattery: appState.snapshot.hasBattery,
                    cycleCount: appState.snapshot.cycleCount,
                    fullChargeMilliAmpHours: appState.snapshot.fullChargeMilliAmpHours,
                    designCapacityMilliAmpHours: appState.snapshot.designCapacityMilliAmpHours,
                    capacityStyle: appState.settings.batteryCapacityStyle,
                    language: appState.settings.language,
                    showsSettingsButton: showsHeaderSettings(on: .batteryCycle),
                    onOpenSettings: { appState.openSettings() }
                )
            }
        case .settings:
            if appState.settings.settingsButtonPlacement.drawsOwnBlock(
                blockVisible: appState.settings.showSettingsBlock
            ) {
                standaloneSettingsRow
            }
        }
    }

    private var ringsHeader: some View {
        let rows = appState.settings.displayedRingRows(seen: appState.bluetoothDevices)
        return RingHeaderLayout(rowCounts: ringRowCounts) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                ForEach(row) { item in
                    ringItemCell(item)
                }
            }
            if settingsGearInRings {
                settingsButton
            }
        }
        // Opening lays this block out in the short placeholder, then the
        // popover animation eases the rows up into the final grid. Snap.
        .animation(nil, value: appState.isPopoverOpen)
        .animation(nil, value: panelWidth)
        .animation(nil, value: rows.map(\.count))
        .transaction { transaction in
            if !ringPlacementSettled {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    ringPlacementSettled = true
                }
            }
        }
        .onDisappear {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                ringPlacementSettled = false
            }
        }
    }

    @ViewBuilder
    private func ringItemCell(_ item: RingItem) -> some View {
        if let slot = item.slot {
            ringCell(slot)
        } else {
            bluetoothRing(item)
        }
    }

    @ViewBuilder
    private func bluetoothRing(_ item: RingItem) -> some View {
        let language = appState.settings.language
        let devices = appState.settings.bluetoothRingDevices
        let ring = RingBoard.resolve(item, devices: devices)
        let reading = appState.bluetoothDevices.first { $0.address == item.address }
        let face = ring.flatMap {
            RingBoard.face(ring: $0, connected: reading?.connected == true, levels: reading?.levels ?? [:])
        }
        if let ring, let face {
            let device = devices.first { $0.address == item.address }
            let model = device?.model ?? .generic
            let name = device?.name ?? item.address ?? ""
            let captions = bluetoothCaptions(face: face, language: language)
            let title = ([name] + captions).joined(separator: " ")
            let scheme = appState.settings.ringTint.scheme(for: .battery)
            if face.parts.count == 2, let left = face.parts.first, let right = face.parts.last {
                let leftPercent = Double(face.levels[left] ?? 0)
                let rightPercent = Double(face.levels[right] ?? 0)
                PairRingView(
                    leftProgress: face.isPlaceholder ? 0 : leftPercent / 100,
                    rightProgress: face.isPlaceholder ? 0 : rightPercent / 100,
                    leftColor: ring.sideColors[left]?.color ?? scheme.colors(percent: leftPercent).left,
                    rightColor: ring.sideColors[right]?.color ?? scheme.colors(percent: rightPercent).left,
                    leftGlyph: ring.shownGlyph(model: model, part: left),
                    rightGlyph: ring.shownGlyph(model: model, part: right),
                    leftCaption: bluetoothCaption(part: left, face: face, language: language),
                    rightCaption: bluetoothCaption(part: right, face: face, language: language),
                    accessibilityValue: title
                )
            } else if face.parts.count <= 1 {
                let percent = face.parts.first.flatMap { face.levels[$0] }
                let shown = Double(percent ?? 0)
                let colors = scheme.colors(percent: shown)
                StatusRingView(
                    percent: shown,
                    fillLeft: colors.left,
                    fillRight: colors.right,
                    caption: face.isPlaceholder ? "—" : "\(percent ?? 0)%",
                    accessibilityName: title,
                    glyph: ring.shownGlyph(model: model, parts: face.parts),
                    glyphTint: ring.iconColor?.color
                )
            } else {
                MeterRingView(
                    segments: meterSegments(face: face, scheme: scheme),
                    glyph: ring.shownGlyph(model: model, parts: ring.parts),
                    glyphTint: ring.iconColor?.color,
                    accessibilityValue: title
                )
            }
        }
    }

    /// Index 0 is 60° (right ear), 1 is 180° (case), 2 is 300° (left ear).
    private func meterSegments(face: BluetoothRingFace, scheme: ValueTintScheme) -> [MeterRingView.MeterSegment] {
        let language = appState.settings.language
        var placed: [BluetoothBatteryPart?] = [nil, nil, nil]
        var rest: [BluetoothBatteryPart] = []
        for part in face.parts {
            switch part {
            case .right: placed[0] = part
            case .box: placed[1] = part
            case .left: placed[2] = part
            default: rest.append(part)
            }
        }
        for part in rest {
            if let index = placed.firstIndex(where: { $0 == nil }) {
                placed[index] = part
            }
        }
        return placed.compactMap { part in
            guard let part else { return nil }
            let percent = Double(face.levels[part] ?? 0)
            return MeterRingView.MeterSegment(
                progress: face.isPlaceholder ? 0 : percent / 100,
                color: scheme.colors(percent: percent).left,
                caption: bluetoothCaption(part: part, face: face, language: language)
            )
        }
    }

    private func bluetoothCaptions(face: BluetoothRingFace, language: AppLanguage) -> [String] {
        if face.isPlaceholder { return ["—"] }
        if face.parts.count <= 1 { return ["\(face.parts.first.flatMap { face.levels[$0] } ?? 0)%"] }
        return face.parts.map { bluetoothCaption(part: $0, face: face, language: language) }
    }

    private func bluetoothCaption(part: BluetoothBatteryPart, face: BluetoothRingFace, language: AppLanguage) -> String {
        if face.isPlaceholder { return "—" }
        let name = Localization.string(part.shortLocalizationKey, language: language)
        return "\(name) \(face.levels[part] ?? 0)%"
    }

    @ViewBuilder
    private func ringCell(_ slot: RingSlot) -> some View {
        switch slot {
        case .download:
            speedRing(
                segment: .download,
                bytesPerSecond: appState.metrics.downloadBytesPerSecond,
                glyph: appState.settings.ringIcons.slot(for: .download),
                nameKey: "settings.rings.download"
            )
        case .upload:
            speedRing(
                segment: .upload,
                bytesPerSecond: appState.metrics.uploadBytesPerSecond,
                glyph: appState.settings.ringIcons.slot(for: .upload),
                nameKey: "settings.rings.upload"
            )
        case .speedPair:
            speedPairRing
        case .batteryTemperature:
            temperatureRing
        case .thermalState:
            thermalRing
        default:
            if let kind = slot.metric {
                metricRing(kind)
            }
        }
    }

    private var temperatureRing: some View {
        let language = appState.settings.language
        let celsius = appState.snapshot.batteryTemperatureCelsius
        let percent = celsius.map {
            BatteryTemperatureFormat.ringPercent(
                celsius: $0,
                centerCelsius: Double(appState.settings.temperatureHalfCelsius)
            )
        } ?? 0
        let colors = appState.settings.ringTint.scheme(forSegment: .batteryTemperature).colors(percent: percent)
        let unit = appState.settings.temperatureUnit
        let value = celsius.map { BatteryTemperatureFormat.caption(celsius: $0, unit: unit) } ?? "—"
        let caption = Localization.string("ring.caption.batteryTemperature %@", language: language, value)
        let name = Localization.string("settings.rings.batteryTemperature", language: language)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: caption,
            accessibilityName: name,
            glyph: appState.settings.ringIcons.slot(for: .batteryTemperature),
            glyphTint: appState.settings.slotIconColors[RingSlot.batteryTemperature.rawValue]?.color,
            accessibilityValue: "\(name) \(caption)"
        )
    }

    private var thermalRing: some View {
        let language = appState.settings.language
        let level = appState.snapshot.thermalState
        let percent = level?.ringPercent(
            nominal: appState.settings.thermalNominalPercent,
            fair: appState.settings.thermalFairPercent,
            serious: appState.settings.thermalSeriousPercent,
            critical: appState.settings.thermalCriticalPercent
        ) ?? 0
        let colors = appState.settings.ringTint.scheme(forSegment: .thermalState).colors(percent: percent)
        let caption = level.map { Localization.string($0.captionKey, language: language) } ?? "—"
        let name = Localization.string("settings.rings.thermalState", language: language)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: caption,
            accessibilityName: name,
            glyph: appState.settings.ringIcons.slot(for: .thermalState),
            glyphTint: appState.settings.slotIconColors[RingSlot.thermalState.rawValue]?.color,
            accessibilityValue: "\(name) \(caption)"
        )
    }

    private func metricRing(_ kind: RingKind) -> some View {
        let language = appState.settings.language
        let percent = percent(for: kind)
        let colors = appState.settings.ringTint.scheme(for: kind).colors(percent: percent)
        let name = Localization.string(kind.localizationKey, language: language)
        let caption = metricCaption(kind, percent: percent, language: language)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: caption,
            accessibilityName: name,
            glyph: appState.settings.ringIcons.slot(for: kind),
            accessibilityValue: kind == .swap ? "\(name) \(caption)" : nil
        )
    }

    private func networkPercent(bytesPerSecond: Double, segment: RingColorSegment) -> Double {
        let kilobytes = segment == .upload
            ? appState.settings.uploadHalfKilobytes
            : appState.settings.downloadHalfKilobytes
        return NetworkRateFormat.ringPercent(
            bytesPerSecond: bytesPerSecond,
            centerBytesPerSecond: Double(kilobytes) * 1024
        )
    }

    private func speedRing(
        segment: RingColorSegment,
        bytesPerSecond: Double,
        glyph: GlyphSlot,
        nameKey: String
    ) -> some View {
        let language = appState.settings.language
        let percent = networkPercent(bytesPerSecond: bytesPerSecond, segment: segment)
        let colors = appState.settings.ringTint.scheme(forSegment: segment).colors(percent: percent)
        let rate = NetworkRateFormat.string(bytesPerSecond: bytesPerSecond)
        let name = Localization.string(nameKey, language: language)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: rate,
            accessibilityName: name,
            glyph: glyph,
            glyphTint: colors.left,
            accessibilityValue: "\(name) \(rate)"
        )
    }

    private var speedPairRing: some View {
        let language = appState.settings.language
        let downBytes = appState.metrics.downloadBytesPerSecond
        let upBytes = appState.metrics.uploadBytesPerSecond
        let down = NetworkRateFormat.string(bytesPerSecond: downBytes)
        let up = NetworkRateFormat.string(bytesPerSecond: upBytes)
        let name = Localization.string("settings.rings.speedPair", language: language)
        let downloadPercent = networkPercent(bytesPerSecond: downBytes, segment: .download)
        let uploadPercent = networkPercent(bytesPerSecond: upBytes, segment: .upload)
        let downloadColor = appState.settings.ringTint.scheme(forSegment: .download)
            .colors(percent: downloadPercent).left
        let uploadColor = appState.settings.ringTint.scheme(forSegment: .upload)
            .colors(percent: uploadPercent).left
        return SpeedPairRingView(
            downloadProgress: downloadPercent / 100,
            uploadProgress: uploadPercent / 100,
            downloadCaption: down,
            uploadCaption: up,
            accessibilityValue: "\(name) ↓ \(down) ↑ \(up)",
            downloadColor: downloadColor,
            uploadColor: uploadColor
        )
    }

    private func metricCaption(_ kind: RingKind, percent: Double, language: AppLanguage) -> String {
        if kind == .swap {
            return Localization.string(
                kind.captionKey,
                language: language,
                SwapUsageFormat.string(bytes: appState.metrics.swapUsedBytes)
            )
        }
        return Localization.string(kind.captionKey, language: language, Int64(percent.rounded()))
    }

    private func percent(for kind: RingKind) -> Double {
        switch kind {
        case .battery: appState.snapshot.percent
        case .cpu: appState.metrics.cpuPercent
        case .gpu: appState.metrics.gpuPercent
        case .memory: appState.metrics.memoryPercent
        case .disk: appState.metrics.diskPercent
        case .memoryPressure: appState.metrics.memoryPressurePercent
        case .swap:
            SwapUsageFormat.ringPercent(
                usedBytes: appState.metrics.swapUsedBytes,
                halfBytes: Double(appState.settings.swapHalfMegabytes) * 1_048_576,
                memoryBytes: SwapUsageFormat.physicalMemoryBytes()
            )
        }
    }

    private func energyFlow(theme: AppTheme) -> some View {
        EnergyFlowView(
            snapshot: appState.snapshot,
            theme: theme,
            flowTint: appState.settings.flowTint,
            flowIcons: appState.settings.flowIcons,
            isAnimating: appState.isPopoverOpen,
            motion: appState.settings.motionStyle,
            motionFrameRate: appState.settings.motionFrameRate,
            pulseFlowIcons: appState.settings.pulseFlowIcons,
            flowIconScale: appState.settings.flowIconScale,
            language: appState.settings.language
        )
    }

    private func energyFlow<Trailing: View>(
        theme: AppTheme,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        EnergyFlowView(
            snapshot: appState.snapshot,
            theme: theme,
            flowTint: appState.settings.flowTint,
            flowIcons: appState.settings.flowIcons,
            isAnimating: appState.isPopoverOpen,
            motion: appState.settings.motionStyle,
            motionFrameRate: appState.settings.motionFrameRate,
            pulseFlowIcons: appState.settings.pulseFlowIcons,
            flowIconScale: appState.settings.flowIconScale,
            language: appState.settings.language,
            trailingAccessory: trailing
        )
    }

    /// Compact settings control for the flow-only layout: layout size is the
    /// gear alone so it centers on the ribbon; the title sits underneath.
    private var flowSideSettingsButton: some View {
        let language = appState.settings.language
        let title = Localization.string("settings.title", language: language)
        return Button {
            appState.openSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 58, height: 58)
                .modifier(SettingsGlassChrome(capture: readmeGalleryCapture))
                .overlay(alignment: .bottom) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .autoFittingCaption(minimumScale: 0.55)
                        .fixedSize()
                        .offset(y: 16)
                }
        }
        .buttonStyle(.plain)
        .frame(width: 58, height: 58)
        .help(title)
        .accessibilityLabel(title)
    }

    private var standaloneSettingsRow: some View {
        let language = appState.settings.language
        let title = Localization.string("settings.title", language: language)
        return Button {
            appState.openSettings()
        } label: {
            EnergyModeButton(title: title, systemImage: "gearshape")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var settingsButton: some View {
        let language = appState.settings.language
        let title = Localization.string("settings.title", language: language)
        return Button {
            appState.openSettings()
        } label: {
            RingSettingsCell(title: title)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Gear cell in the ring grid. Same diameter and caption rhythm as `StatusRingView`.
struct RingSettingsCell: View {
    var title: String
    @Environment(\.readmeGalleryCapture) private var readmeGalleryCapture

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: StatusRingView.diameter, height: StatusRingView.diameter)
                .modifier(SettingsGlassChrome(capture: readmeGalleryCapture))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .autoFittingCaption(minimumScale: 0.55)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One centered row per saved row. The settings gear is the last cell of the last row.
private struct RingHeaderLayout: Layout {
    var rowCounts: [Int]
    var rowSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? (PopoverLayout.width - PopoverLayout.padding * 2)
        let height = stackedHeight(subviews: subviews)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var cursor = 0
        var y = bounds.minY
        for count in rowCounts where count > 0 {
            guard cursor + count <= subviews.count else { return }
            let pitch = PopoverLayout.ringPitch(columns: count)
            let fitted = ProposedViewSize(width: pitch.column, height: nil)
            let slice = subviews[cursor..<(cursor + count)]
            let height = slice.map { $0.sizeThatFits(fitted).height }.max() ?? 0
            let origin = centeredOrigin(
                width: bounds.width,
                columns: count,
                column: pitch.column,
                spacing: pitch.spacing,
                minX: bounds.minX
            )
            for offset in 0..<count {
                let x = origin + CGFloat(offset) * (pitch.column + pitch.spacing)
                subviews[cursor + offset].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: fitted)
            }
            y += height + rowSpacing
            cursor += count
        }
    }

    private func stackedHeight(subviews: Subviews) -> CGFloat {
        var cursor = 0
        var height: CGFloat = 0
        var rows = 0
        for count in rowCounts where count > 0 {
            guard cursor + count <= subviews.count else { break }
            let pitch = PopoverLayout.ringPitch(columns: count)
            let fitted = ProposedViewSize(width: pitch.column, height: nil)
            let row = subviews[cursor..<(cursor + count)].map { $0.sizeThatFits(fitted).height }.max() ?? 0
            height += row
            rows += 1
            cursor += count
        }
        if rows > 1 { height += rowSpacing * CGFloat(rows - 1) }
        return height
    }

    private func centeredOrigin(width: CGFloat, columns: Int, column: CGFloat, spacing: CGFloat, minX: CGFloat) -> CGFloat {
        let group = CGFloat(columns) * column + spacing * CGFloat(max(columns - 1, 0))
        return minX + max(0, (width - group) / 2)
    }
}

/// README bitmaps cannot sample Liquid Glass (it comes back as a solid dark
/// disc). Draw a light rimmed circle that survives `cacheDisplay`.
struct SettingsGlassChrome: ViewModifier {
    var capture: Bool

    func body(content: Content) -> some View {
        if capture {
            content.background {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.90),
                                Color(white: 0.78)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(Color(white: 0.62).opacity(0.55), lineWidth: 1)
                    }
            }
        } else {
            content.macPowerGlassEffect(.regularInteractive, in: Circle())
        }
    }
}
