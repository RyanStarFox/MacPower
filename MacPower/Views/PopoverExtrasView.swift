import AppKit
import CoreText
import SwiftUI

/// Title line for a panel block. The settings gear sits on the right of the title only.
private struct BlockTitleRow: View {
    var title: String
    var showsSettingsButton: Bool
    var settingsTitle: String
    var onOpenSettings: () -> Void

    var body: some View {
        if showsSettingsButton {
            HStack(alignment: .center, spacing: 8) {
                titleText
                Spacer(minLength: 8)
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(settingsTitle)
                .accessibilityLabel(settingsTitle)
            }
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct TopAppsSection: View {
    var list: TopAppList
    var language: AppLanguage
    var rowCount: Int
    var chart: TopAppsChartStyle = .bars
    var showsSettingsButton: Bool = false
    var onOpenSettings: () -> Void = {}

    private static let rowHeight: CGFloat = 20
    private static let rowSpacing: CGFloat = 6
    private static let columnPlot: CGFloat = 64
    private static let columnValueHeight: CGFloat = 14
    private static let columnIconHeight: CGFloat = 16
    private static let columnNameHeight: CGFloat = 14
    private static let columnSpacing: CGFloat = 4
    private static var columnHeight: CGFloat {
        columnPlot + columnValueHeight + columnIconHeight + columnNameHeight + columnSpacing * 2
    }

    private var listHeight: CGFloat {
        let rows = CGFloat(max(rowCount, 1))
        return Self.rowHeight * rows + Self.rowSpacing * max(rows - 1, 0)
    }

    private var blockHeight: CGFloat {
        switch chart {
        case .list, .bars: listHeight
        case .columns: Self.columnHeight
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BlockTitleRow(
                title: Localization.string("popover.topApps.title", language: language),
                showsSettingsButton: showsSettingsButton,
                settingsTitle: Localization.string("settings.title", language: language),
                onOpenSettings: onOpenSettings
            )
            Group {
                switch list {
                case .measuring:
                    Text(Localization.string("popover.topApps.measuring", language: language))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .apps(let apps) where apps.isEmpty:
                    Text(Localization.string("popover.topApps.empty", language: language))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .apps(let apps):
                    chartBody(apps)
                }
            }
            .frame(maxWidth: .infinity, minHeight: blockHeight, maxHeight: blockHeight, alignment: .top)
        }
        .animation(nil, value: list)
        .animation(nil, value: chart)
    }

    @ViewBuilder
    private func chartBody(_ apps: [TopAppEntry]) -> some View {
        switch chart {
        case .list:
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                ForEach(apps) { app in
                    listRow(app)
                }
            }
        case .bars:
            let fractions = TopAppsChartScale.fractions(apps.map(\.impact))
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    barRow(app, fraction: fractions[index])
                }
            }
        case .columns:
            columnChart(apps)
        }
    }

    private func listRow(_ app: TopAppEntry) -> some View {
        HStack(spacing: 8) {
            appIcon(app)
            Text(app.name)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 8)
            impactText(app)
        }
        .frame(height: Self.rowHeight, alignment: .center)
    }

    private func barRow(_ app: TopAppEntry, fraction: Double) -> some View {
        HStack(spacing: 8) {
            appIcon(app)
            Text(app.name)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            barTrack(fraction: fraction)
                .frame(maxWidth: .infinity)
            impactText(app)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: Self.rowHeight, alignment: .center)
    }

    private func barTrack(fraction: Double) -> some View {
        GeometryReader { proxy in
            let width = fraction <= 0 ? 0 : max(3, proxy.size.width * fraction)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: width)
            }
        }
        .frame(height: 8)
    }

    private func columnChart(_ apps: [TopAppEntry]) -> some View {
        let fractions = TopAppsChartScale.fractions(apps.map(\.impact))
        return VStack(spacing: Self.columnSpacing) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    VStack(spacing: 2) {
                        Spacer(minLength: 0)
                        impactText(app)
                            .font(.caption2.monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(height: Self.columnValueHeight)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.primary.opacity(0.55))
                            .frame(height: max(4, Self.columnPlot * fractions[index]))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(height: Self.columnPlot + Self.columnValueHeight, alignment: .bottom)

            HStack(alignment: .center, spacing: 4) {
                ForEach(apps) { app in
                    appIcon(app)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: Self.columnIconHeight)

            HStack(alignment: .top, spacing: 4) {
                ForEach(apps) { app in
                    Text(app.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: Self.columnNameHeight)
                }
            }
        }
    }

    private func appIcon(_ app: TopAppEntry) -> some View {
        Image(nsImage: icon(for: app))
            .resizable()
            .frame(width: 16, height: 16)
    }

    private func impactText(_ app: TopAppEntry) -> some View {
        Text(EnergyImpact.label(app.impact))
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func icon(for app: TopAppEntry) -> NSImage {
        if let path = app.iconPath {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

/// Decides whether the strategy and low-power buttons share one row.
/// Side by side only when every strategy label (not just the selected one)
/// fits in two lines and the low-power label fits on one line, at the
/// current panel width. Otherwise they stack.
enum LowPowerButtonRowLayout {
    static let buttonSpacing: CGFloat = 8
    static let iconSide: CGFloat = 26
    static let iconSpacing: CGFloat = 8
    static let textLeading: CGFloat = 6
    static let textTrailing: CGFloat = 10
    static let fontSize: CGFloat = 13
    static let strategyLines = 2
    static let lowPowerLines = 1
    static let menuIndicatorWidth: CGFloat = 12

    static func textColumnWidth(panelWidth: CGFloat, sideBySide: Bool) -> CGFloat {
        let content = panelWidth - PopoverLayout.padding * 2
        let button = sideBySide ? (content - buttonSpacing) / 2 : content
        return button - iconSide - iconSpacing - textLeading - textTrailing
    }

    static func prefersSideBySide(
        strategyLabels: [String],
        lowPowerLabel: String,
        panelWidth: CGFloat
    ) -> Bool {
        let width = textColumnWidth(panelWidth: panelWidth, sideBySide: true)
        let strategiesFit = strategyLabels.allSatisfy {
            labelFits($0, width: width - menuIndicatorWidth, maxLines: strategyLines)
        }
        return strategiesFit && labelFits(lowPowerLabel, width: width, maxLines: lowPowerLines)
    }

    /// Side by side only when both buttons are shown and the length-based fit check passes.
    static func placesSideBySide(
        layout: LowPowerButtonLayout,
        visibility: LowPowerButtonVisibility,
        strategyLabels: [String],
        lowPowerLabel: String,
        panelWidth: CGFloat
    ) -> Bool {
        guard layout == .fitTwoPerRow, visibility == .both else { return false }
        return prefersSideBySide(
            strategyLabels: strategyLabels,
            lowPowerLabel: lowPowerLabel,
            panelWidth: panelWidth
        )
    }

    /// True when `text` draws in full inside `width` on at most `maxLines` lines.
    static func labelFits(_ text: String, width: CGFloat, maxLines: Int) -> Bool {
        guard width > 0, maxLines > 0 else { return false }
        if text.isEmpty { return true }
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: style
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: width, height: 10_000),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return false }
        if lines.count > maxLines { return false }
        var covered = 0
        for line in lines {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            if lineWidth > width + 0.5 { return false }
            let range = CTLineGetStringRange(line)
            covered += range.length
        }
        return covered >= attributed.length
    }
}

struct LowPowerSection: View {
    var strategy: LowPowerPreset?
    var savedStrategy: LowPowerPreset?
    var lowPowerOn: Bool?
    var externalConnected: Bool
    var failed: Bool
    var language: AppLanguage
    var panelWidth: CGFloat
    var layout: LowPowerButtonLayout
    var visibility: LowPowerButtonVisibility
    var onStrategy: (LowPowerPreset) -> Void
    var onToggleNow: () -> Void
    var showsSettingsButton: Bool = false
    var onOpenSettings: () -> Void = {}

    private var strategyTitle: String {
        strategy.map { Localization.string($0.shortLocalizationKey, language: language) }
            ?? Localization.string("popover.lowPower.strategy", language: language)
    }

    private var lowPowerTitle: String {
        Localization.string("popover.lowPower.now", language: language)
    }

    private var strategyLabels: [String] {
        LowPowerPreset.allCases.map {
            Localization.string($0.shortLocalizationKey, language: language)
        }
    }

    private var sideBySide: Bool {
        LowPowerButtonRowLayout.placesSideBySide(
            layout: layout,
            visibility: visibility,
            strategyLabels: strategyLabels,
            lowPowerLabel: lowPowerTitle,
            panelWidth: panelWidth
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BlockTitleRow(
                title: Localization.string("popover.lowPower.title", language: language),
                showsSettingsButton: showsSettingsButton,
                settingsTitle: Localization.string("settings.title", language: language),
                onOpenSettings: onOpenSettings
            )
            if lowPowerOn != nil || strategy != nil {
                buttons
                // Keep the popover height steady when the override notice changes.
                Text(Localization.string("popover.lowPower.override", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isOverridden ? 1 : 0)
                    .accessibilityHidden(!isOverridden)
            } else {
                Text(Localization.string("popover.lowPower.reading", language: language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if failed {
                Text(Localization.string("popover.lowPower.failed", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // A disable or implicit fade repaints both buttons and looks like the block refreshed.
        .animation(nil, value: strategy)
        .animation(nil, value: lowPowerOn)
        .animation(nil, value: failed)
    }

    private var isOverridden: Bool {
        savedStrategy?.isOverridden(current: lowPowerOn, externalConnected: externalConnected) == true
    }

    @ViewBuilder
    private var buttons: some View {
        if visibility.showsStrategy && visibility.showsLowPower {
            if sideBySide {
                HStack(spacing: LowPowerButtonRowLayout.buttonSpacing) {
                    strategyControl
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    nowControl
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: LowPowerButtonRowLayout.buttonSpacing) {
                    strategyControl
                        .frame(maxWidth: .infinity)
                    nowControl
                        .frame(maxWidth: .infinity)
                }
            }
        } else if visibility.showsStrategy {
            strategyControl
                .frame(maxWidth: .infinity)
        } else {
            nowControl
                .frame(maxWidth: .infinity)
        }
    }

    private var strategyControl: some View {
        LowPowerLabeledButton(label: Localization.string("popover.lowPower.defaultState", language: language)) {
            strategyMenu
        }
    }

    private var nowControl: some View {
        LowPowerLabeledButton(label: Localization.string("popover.lowPower.currentState", language: language)) {
            nowButton
        }
    }

    private var strategyMenu: some View {
        Menu {
            ForEach(LowPowerPreset.allCases) { mode in
                Button {
                    onStrategy(mode)
                } label: {
                    if mode == strategy {
                        Label(presetName(mode), systemImage: "checkmark")
                    } else {
                        Text(presetName(mode))
                    }
                }
            }
        } label: {
            EnergyModeButton(
                title: strategyTitle,
                detail: nil,
                lineLimit: LowPowerButtonRowLayout.strategyLines,
                fillsHeight: sideBySide,
                reserveTitles: strategyLabels,
                showsMenuIndicator: true
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .animation(nil, value: strategyTitle)
    }

    private var nowButton: some View {
        Button(action: onToggleNow) {
            EnergyModeButton(
                title: lowPowerTitle,
                systemImage: "battery.25percent",
                detail: nil,
                iconActive: lowPowerOn == true,
                fillsHeight: sideBySide
            )
        }
        .buttonStyle(.plain)
        // Unknown state only. A busy disable dims this row, then undims when the write finishes.
        .disabled(lowPowerOn == nil)
        .animation(nil, value: lowPowerOn)
    }

    private func presetName(_ mode: LowPowerPreset) -> String {
        Localization.string(mode.localizationKey, language: language)
    }
}

/// Distinguishes a default-state selector from the current-state button.
struct LowPowerLabeledButton<Content: View>: View {
    var label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.leading, LowPowerButtonRowLayout.textLeading)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Matches the battery menu's energy-mode control: gray rounded row, battery glyph, one label.
struct EnergyModeButton: View {
    var title: String
    var systemImage = "battery.100percent"
    var detail: String?
    var iconActive = false
    var lineLimit = 1
    var fillsHeight = false
    /// Hidden copies of every label, so the button stays as tall as the tallest one.
    var reserveTitles: [String] = []
    var showsMenuIndicator = false

    var body: some View {
        HStack(spacing: LowPowerButtonRowLayout.iconSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: LowPowerButtonRowLayout.fontSize, weight: .medium))
                .foregroundStyle(iconActive ? Color.white : (systemImage == "battery.25percent" ? Color.primary.opacity(0.55) : Color.primary))
                .frame(width: LowPowerButtonRowLayout.iconSide, height: LowPowerButtonRowLayout.iconSide)
                .background(Circle().fill(iconActive ? Color.accentColor : Color.primary.opacity(0.08)))
            if let detail {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: LowPowerButtonRowLayout.fontSize, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(lineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                titleLabel(title)
            }
            Spacer(minLength: showsMenuIndicator ? LowPowerButtonRowLayout.menuIndicatorWidth : 0)
                .overlay(alignment: .trailing) {
                    if showsMenuIndicator {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
        }
        .padding(.leading, LowPowerButtonRowLayout.textLeading)
        .padding(.trailing, LowPowerButtonRowLayout.textTrailing)
        .frame(
            maxWidth: .infinity,
            minHeight: 40,
            maxHeight: fillsHeight ? .infinity : nil,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The visible title sits on top of every reserved title. Height follows the
    /// tallest label, so choosing a shorter strategy does not shrink the row.
    private func titleLabel(_ text: String) -> some View {
        ZStack(alignment: .leading) {
            ForEach(reserveTitles, id: \.self) { reserved in
                titleText(reserved)
                    .hidden()
            }
            titleText(text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func titleText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: LowPowerButtonRowLayout.fontSize, weight: .medium))
            .foregroundStyle(.primary.opacity(0.88))
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Scope column, interface-name abbreviation, and IPv6 wrapping for one popover row.
enum LocalIPRowLayout {
    static let itemSpacing: CGFloat = 8
    static let addressGap: CGFloat = 8

    struct Presentation: Equatable {
        var interfaceName: String?
        var address: String
    }

    /// First two characters, an ellipsis, and the last two.
    /// The result has to be shorter, so names of four characters or fewer stay whole:
    /// two plus two plus an ellipsis is five characters.
    static func abbreviatedInterfaceName(_ name: String) -> String {
        let characters = Array(name)
        guard characters.count > 4 else { return name }
        let abbreviated = String(characters.prefix(2)) + "…" + String(characters.suffix(2))
        guard abbreviated.count < characters.count else { return name }
        return abbreviated
    }

    static func scopeColumnWidth(labels: [String]) -> CGFloat {
        let measured = labels.map { textWidth($0, font: labelFont) }.max() ?? 0
        return measured.rounded(.up)
    }

    static func presentation(
        interfaceName: String?,
        address: String,
        wrapsAddress: Bool,
        scopeColumnWidth: CGFloat,
        panelWidth: CGFloat
    ) -> Presentation {
        let fullName = interfaceName.flatMap { $0.isEmpty ? nil : $0 }
        let shortName = fullName.map(abbreviatedInterfaceName)
        let content = panelWidth - PopoverLayout.padding * 2
        let chrome = minimumChrome(showsInterface: fullName != nil)
        let usable = max(content - scopeColumnWidth - chrome - 1, 0)
        let fullWidth = fullName.map { textWidth($0, font: labelFont) } ?? 0
        let shortWidth = shortName.map { textWidth($0, font: labelFont) } ?? 0
        let oneLineWidth = textWidth(address, font: addressFont)

        if fullWidth + oneLineWidth <= usable {
            return Presentation(interfaceName: fullName, address: address)
        }
        // Keep a name that still fits beside a wrapped address. Abbreviate only
        // when the full name would leave the address no room to wrap.
        if wrapsAddress,
           let wrapped = wrappedBeside(
            address: address,
            interfaceName: fullName,
            interfaceWidth: fullWidth,
            usable: usable
           ) {
            return wrapped
        }
        if let shortName, shortName != fullName {
            if shortWidth + oneLineWidth <= usable {
                return Presentation(interfaceName: shortName, address: address)
            }
            if wrapsAddress,
               let wrapped = wrappedBeside(
                address: address,
                interfaceName: shortName,
                interfaceWidth: shortWidth,
                usable: usable
               ) {
                return wrapped
            }
        }
        let name = (shortName != fullName) ? shortName : fullName
        let nameWidth = (name == fullName) ? fullWidth : shortWidth
        if wrapsAddress {
            return Presentation(
                interfaceName: name,
                address: wrappedAddress(address, maxWidth: max(usable - nameWidth, 1))
            )
        }
        return Presentation(interfaceName: name, address: address)
    }

    private static func wrappedBeside(
        address: String,
        interfaceName: String?,
        interfaceWidth: CGFloat,
        usable: CGFloat
    ) -> Presentation? {
        let column = max(usable - interfaceWidth, 1)
        let wrapped = wrappedAddress(address, maxWidth: column)
        guard linesFit(wrapped, maxWidth: column) else { return nil }
        return Presentation(interfaceName: interfaceName, address: wrapped)
    }

    /// Breaks `address` onto as many lines as the column needs. Prefers a colon boundary.
    static func wrappedAddress(_ address: String, maxWidth: CGFloat) -> String {
        guard maxWidth > 0, textWidth(address, font: addressFont) > maxWidth else { return address }
        var remaining = address
        var lines: [String] = []
        while !remaining.isEmpty {
            if textWidth(remaining, font: addressFont) <= maxWidth {
                lines.append(remaining)
                break
            }
            let prefix = longestFittingPrefix(remaining, maxWidth: maxWidth)
            if prefix.isEmpty || prefix.count >= remaining.count {
                lines.append(String(remaining.prefix(1)))
                remaining = String(remaining.dropFirst())
                continue
            }
            lines.append(prefix)
            remaining = String(remaining.dropFirst(prefix.count))
        }
        return lines.joined(separator: "\n")
    }

    private static func linesFit(_ text: String, maxWidth: CGFloat) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy { line in
            textWidth(String(line), font: addressFont) <= maxWidth + 0.5
        }
    }

    private static func longestFittingPrefix(_ text: String, maxWidth: CGFloat) -> String {
        var built = ""
        var lastFit = ""
        var lastColonFit = ""
        for character in text {
            let next = built + String(character)
            if textWidth(next, font: addressFont) > maxWidth + 0.5 {
                break
            }
            built = next
            lastFit = built
            if character == ":" {
                lastColonFit = built
            }
        }
        if !lastColonFit.isEmpty, lastColonFit.count < text.count {
            return lastColonFit
        }
        return lastFit
    }

    private static func minimumChrome(showsInterface: Bool) -> CGFloat {
        let gaps = showsInterface ? itemSpacing * 3 : itemSpacing * 2
        return gaps + addressGap
    }

    static var labelFont: NSFont {
        NSFont.preferredFont(forTextStyle: .callout)
    }

    static var addressFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: labelFont.pointSize, weight: .regular)
    }

    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: font])
        )
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)).rounded(.up)
    }
}

struct LocalIPSection: View {
    var rows: [IPAddressRow]
    var language: AppLanguage
    var panelWidth: CGFloat
    var showsSettingsButton: Bool = false
    var onOpenSettings: () -> Void = {}

    private var scopeColumnWidth: CGFloat {
        let labels = rows.map {
            Localization.string($0.scope.localizationKey, language: language)
        }
        return LocalIPRowLayout.scopeColumnWidth(labels: labels)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BlockTitleRow(
                title: Localization.string("popover.localIP.title", language: language),
                showsSettingsButton: showsSettingsButton,
                settingsTitle: Localization.string("settings.title", language: language),
                onOpenSettings: onOpenSettings
            )
            if rows.isEmpty {
                Text(Localization.string("popover.localIP.empty", language: language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rows) { row in
                        addressRow(row)
                    }
                }
            }
        }
        .animation(nil, value: rows)
    }

    private func addressRow(_ row: IPAddressRow) -> some View {
        let presented = LocalIPRowLayout.presentation(
            interfaceName: row.interfaceName,
            address: value(for: row),
            wrapsAddress: row.family == .ipv6 && !row.failed,
            scopeColumnWidth: scopeColumnWidth,
            panelWidth: panelWidth
        )
        return HStack(alignment: .firstTextBaseline, spacing: LocalIPRowLayout.itemSpacing) {
            Text(Localization.string(row.scope.localizationKey, language: language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: scopeColumnWidth, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            if let interfaceName = presented.interfaceName {
                Text(interfaceName)
                    .font(.callout)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: LocalIPRowLayout.addressGap)
            Text(presented.address)
                .font(.callout.monospacedDigit())
                .foregroundStyle(row.failed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: true)
        }
    }

    private func value(for row: IPAddressRow) -> String {
        if row.failed {
            return Localization.string("popover.localIP.failed", language: language)
        }
        return row.address
    }
}

struct BatteryCycleSection: View {
    var hasBattery: Bool
    var cycleCount: Int?
    var fullChargeMilliAmpHours: Int?
    var designCapacityMilliAmpHours: Int?
    var capacityStyle: BatteryCapacityStyle = .both
    var language: AppLanguage
    var showsSettingsButton: Bool = false
    var onOpenSettings: () -> Void = {}

    private var capacityDetail: String? {
        guard let fullChargeMilliAmpHours, let designCapacityMilliAmpHours else { return nil }
        return BatteryCapacityFormat.text(
            fullChargeMilliAmpHours: fullChargeMilliAmpHours,
            designMilliAmpHours: designCapacityMilliAmpHours,
            style: capacityStyle
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BlockTitleRow(
                title: Localization.string("popover.batteryCycle.title", language: language),
                showsSettingsButton: showsSettingsButton,
                settingsTitle: Localization.string("settings.title", language: language),
                onOpenSettings: onOpenSettings
            )
            if !hasBattery || (cycleCount == nil && capacityDetail == nil) {
                Text(Localization.string("popover.batteryCycle.empty", language: language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if let cycleCount {
                        row(
                            title: Localization.string("popover.batteryCycle.cycles", language: language),
                            value: "\(cycleCount)"
                        )
                    }
                    if let capacityDetail {
                        row(
                            title: Localization.string("popover.batteryCycle.capacity", language: language),
                            value: capacityDetail
                        )
                    }
                }
            }
        }
    }

    private func row(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.callout.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
