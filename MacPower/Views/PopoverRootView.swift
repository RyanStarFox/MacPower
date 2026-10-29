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

    static func width(ringCount: Int, twoRows: Bool) -> CGFloat {
        let count = columns(ringCount: ringCount, twoRows: twoRows)
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

    /// Cells on the wider row. The settings button is one cell.
    static func columns(ringCount: Int, twoRows: Bool) -> Int {
        let total = max(ringCount, 0) + 1
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

    var body: some View {
        Group {
            if appState.isPopoverOpen {
                let theme = AppTheme.resolved(palette: appState.settings.palette, colorScheme: colorScheme)
                content(theme: theme)
                    .padding(PopoverLayout.padding)
                    .frame(width: panelWidth)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Keep the hosting graph mounted, but never build glass / TimelineView
                // while the menu extra is idle. Interactive Liquid Glass in a hidden
                // NSPopover was burning CPU and UAFing NSViewFocusProxy ~2s after launch.
                // Match the open width so the first real layout is not a resize.
                Color.clear.frame(width: panelWidth, height: 1)
            }
        }
        .environment(\.locale, appState.settings.resolvedLocale)
        .id(appState.settings.language)
    }

    private var panelWidth: CGFloat {
        guard appState.settings.showStatusRings else { return PopoverLayout.width }
        return PopoverLayout.width(ringCount: appState.settings.ringOrder.count, twoRows: appState.settings.twoRingRows)
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
            VStack(alignment: .leading, spacing: 14) {
                if showRings {
                    ringsHeader
                }

                if showFlow {
                    VStack(alignment: .leading, spacing: 4) {
                        TimeEstimateRow(snapshot: appState.snapshot, language: appState.settings.language)
                        if showRings {
                            energyFlow(theme: theme)
                        } else {
                            // Gear-only layout height so HStack can center it on the
                            // ribbon; caption is painted below without shifting alignment.
                            energyFlow(theme: theme) {
                                flowSideSettingsButton
                            }
                        }
                    }
                } else if !showRings {
                    settingsButton
                        .frame(maxWidth: .infinity)
                }
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
            settingsButton
        }
        // Opening used to lay the rings out once at the wrong pitch, then
        // animate them into place. Placement itself should snap.
        .animation(nil, value: panelWidth)
        .animation(nil, value: appState.settings.twoRingRows)
        .animation(nil, value: appState.settings.ringOddRow)
        .animation(nil, value: slots.count)
    }

    @ViewBuilder
    private func ringCell(_ slot: RingSlot) -> some View {
        switch slot {
        case .download:
            speedRing(
                segment: .download,
                bytesPerSecond: appState.metrics.downloadBytesPerSecond,
                glyph: "arrow.down",
                nameKey: "settings.rings.download"
            )
        case .upload:
            speedRing(
                segment: .upload,
                bytesPerSecond: appState.metrics.uploadBytesPerSecond,
                glyph: "arrow.up",
                nameKey: "settings.rings.upload"
            )
        case .speedPair:
            speedPairRing
        default:
            if let kind = slot.metric {
                metricRing(kind)
            }
        }
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

    private func speedRing(
        segment: RingColorSegment,
        bytesPerSecond: Double,
        glyph: String,
        nameKey: String
    ) -> some View {
        let language = appState.settings.language
        let percent = NetworkRateFormat.ringPercent(bytesPerSecond: bytesPerSecond)
        let colors = appState.settings.ringTint.scheme(forSegment: segment).colors(percent: percent)
        let rate = NetworkRateFormat.string(bytesPerSecond: bytesPerSecond)
        let name = Localization.string(nameKey, language: language)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: rate,
            accessibilityName: name,
            glyph: .system(glyph),
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
        let downloadColor = appState.settings.ringTint.scheme(forSegment: .download)
            .colors(percent: NetworkRateFormat.ringPercent(bytesPerSecond: downBytes)).left
        let uploadColor = appState.settings.ringTint.scheme(forSegment: .upload)
            .colors(percent: NetworkRateFormat.ringPercent(bytesPerSecond: upBytes)).left
        return SpeedPairRingView(
            downloadProgress: NetworkRateFormat.ringPercent(bytesPerSecond: downBytes) / 100,
            uploadProgress: NetworkRateFormat.ringPercent(bytesPerSecond: upBytes) / 100,
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

    private var settingsButton: some View {
        let language = appState.settings.language
        return Button {
            appState.openSettings()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 58, height: 58)
                    .modifier(SettingsGlassChrome(capture: readmeGalleryCapture))
                Text(Localization.string("settings.title", language: language))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .autoFittingCaption(minimumScale: 0.55)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help(Localization.string("settings.title", language: language))
        .accessibilityLabel(Localization.string("settings.title", language: language))
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
        let column = layoutMetrics(total: subviews.count, width: width).column
        let rowHeight = rowHeight(fitting: column, subviews: subviews)
        let rows: CGFloat = usesTwoRows(subviews.count) ? 2 : 1
        return CGSize(width: width, height: rowHeight * rows + rowSpacing * (rows - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let total = subviews.count
        guard total > 0 else { return }
        let metrics = layoutMetrics(total: total, width: bounds.width)
        let column = metrics.column
        let fitted = ProposedViewSize(width: column, height: nil)
        let rowHeight = rowHeight(fitting: column, subviews: subviews)
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
        let y = bounds.minY + rowHeight + rowSpacing
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

    private func rowHeight(fitting column: CGFloat, subviews: Subviews) -> CGFloat {
        let proposal = ProposedViewSize(width: column, height: nil)
        return subviews.map { $0.sizeThatFits(proposal).height }.max() ?? 0
    }
}

/// README bitmaps cannot sample Liquid Glass (it comes back as a solid dark
/// disc). Draw a light rimmed circle that survives `cacheDisplay`.
private struct SettingsGlassChrome: ViewModifier {
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
