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
        guard appState.settings.showStatusRings else { return PopoverLayout.width }
        return PopoverLayout.width(
            ringCount: appState.settings.ringOrder.count,
            twoRows: appState.settings.twoRingRows,
            includesSettings: settingsGearInRings
        )
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
            let showRings = appState.settings.showStatusRings
            let showFlow = appState.settings.showEnergyFlow
            let entries = appState.settings.renderedPopoverEntries
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
        let slots = appState.settings.ringOrder
        return RingHeaderLayout(
            twoRows: appState.settings.twoRingRows,
            staggerOdd: appState.settings.ringOddRow == .stagger
        ) {
            ForEach(slots) { slot in
                ringCell(slot)
            }
            if settingsGearInRings {
                settingsButton
            }
        }
        // Opening lays this block out in the short placeholder, then the
        // popover animation eases both rows up into the final grid. Snap.
        .animation(nil, value: appState.isPopoverOpen)
        .animation(nil, value: panelWidth)
        .animation(nil, value: appState.settings.twoRingRows)
        .animation(nil, value: appState.settings.ringOddRow)
        .animation(nil, value: slots.count)
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
        let caption = celsius.map { BatteryTemperatureFormat.caption(celsius: $0) } ?? "—"
        let name = Localization.string("settings.rings.batteryTemperature", language: language)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: caption,
            accessibilityName: name,
            glyph: appState.settings.ringIcons.slot(for: .batteryTemperature),
            glyphTint: colors.left,
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
            glyphTint: colors.left,
            accessibilityValue: "\(name) \(caption)"
        )
    }

    private func metricRing(_ kind: RingKind) -> some View {
        let language = appState.settings.language
        let percent = percent(for: kind)
        let colors = appState.settings.ringTint.scheme(for: kind).colors(percent: percent)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: Localization.string(kind.captionKey, language: language, Int64(percent.rounded())),
            accessibilityName: Localization.string(kind.localizationKey, language: language),
            glyph: appState.settings.ringIcons.slot(for: kind)
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

    private func percent(for kind: RingKind) -> Double {
        switch kind {
        case .battery: appState.snapshot.percent
        case .cpu: appState.metrics.cpuPercent
        case .gpu: appState.metrics.gpuPercent
        case .memory: appState.metrics.memoryPercent
        case .disk: appState.metrics.diskPercent
        case .memoryPressure: appState.metrics.memoryPressurePercent
        case .swap: appState.metrics.swapPercent
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

/// Rings and the settings button are one sequence. Two rows split an even
/// count into n + n, and an odd count into n+1 over n, with the shorter row
/// in the gaps of the row above.
private struct RingHeaderLayout: Layout {
    var twoRows: Bool
    var staggerOdd: Bool
    var rowSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? (PopoverLayout.width - PopoverLayout.padding * 2)
        let metrics = layoutMetrics(total: subviews.count, width: width)
        let heights = rowHeights(column: metrics.column, subviews: subviews, topCount: metrics.columns)
        let height = heights.bottom > 0 ? heights.top + rowSpacing + heights.bottom : heights.top
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let total = subviews.count
        guard total > 0 else { return }
        let metrics = layoutMetrics(total: total, width: bounds.width)
        let column = metrics.column
        let fitted = ProposedViewSize(width: column, height: nil)
        let heights = rowHeights(column: column, subviews: subviews, topCount: metrics.columns)
        let topCount = metrics.columns
        let xOrigin = rowOrigin(
            in: bounds.width,
            columns: topCount,
            column: column,
            spacing: metrics.spacing,
            minX: bounds.minX
        )
        for index in 0..<topCount {
            place(
                subviews[index],
                column: column,
                spacing: metrics.spacing,
                xIndex: index,
                y: bounds.minY,
                xOrigin: xOrigin,
                proposal: fitted
            )
        }
        let bottomCount = total - topCount
        guard bottomCount > 0 else { return }
        let shift = staggerOdd && bottomCount < topCount ? (column + metrics.spacing) / 2 : 0
        let y = bounds.minY + heights.top + rowSpacing
        for index in 0..<bottomCount {
            place(
                subviews[topCount + index],
                column: column,
                spacing: metrics.spacing,
                xIndex: index,
                y: y,
                xOrigin: xOrigin,
                proposal: fitted,
                extraX: shift
            )
        }
    }

    private func place(
        _ subview: LayoutSubview,
        column: CGFloat,
        spacing: CGFloat,
        xIndex: Int,
        y: CGFloat,
        xOrigin: CGFloat,
        proposal: ProposedViewSize,
        extraX: CGFloat = 0
    ) {
        let x = xOrigin + extraX + CGFloat(xIndex) * (column + spacing)
        subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: proposal)
    }

    private func usesTwoRows(_ total: Int) -> Bool {
        twoRows && total >= 2
    }

    private func layoutMetrics(total: Int, width: CGFloat) -> (columns: Int, column: CGFloat, spacing: CGFloat) {
        let columns = usesTwoRows(total) ? (total + 1) / 2 : max(total, 1)
        let pitch = PopoverLayout.ringPitch(columns: columns)
        // One or two cells keep stretching so the panel stays wide enough for
        // the battery section. Three or more use a fixed pitch.
        if columns >= 3 {
            return (columns, pitch.column, pitch.spacing)
        }
        let gaps = pitch.spacing * CGFloat(max(columns - 1, 0))
        let column = max(0, (width - gaps) / CGFloat(max(columns, 1)))
        return (columns, column, pitch.spacing)
    }

    private func rowOrigin(in width: CGFloat, columns: Int, column: CGFloat, spacing: CGFloat, minX: CGFloat) -> CGFloat {
        guard columns >= 3 else { return minX }
        let group = CGFloat(columns) * column + spacing * CGFloat(columns - 1)
        return minX + max(0, (width - group) / 2)
    }

    /// Each row is as tall as its own tallest cell, so the up/down ring's
    /// second caption stays inside the second row.
    private func rowHeights(column: CGFloat, subviews: Subviews, topCount: Int) -> (top: CGFloat, bottom: CGFloat) {
        let proposal = ProposedViewSize(width: column, height: nil)
        let top = subviews.prefix(topCount).map { $0.sizeThatFits(proposal).height }.max() ?? 0
        let bottom = subviews.dropFirst(topCount).map { $0.sizeThatFits(proposal).height }.max() ?? 0
        return (top, bottom)
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
