import AppKit
import SwiftUI

/// macOS 15's hosting controller grows this window but will not shrink it when a
/// shorter tab is shown. Apply the measured height in the same layout pass, with
/// the title bar held still, so the resize is not a visible flash a frame later.
private final class SettingsSizerView: NSView {
    var height: CGFloat = 0 {
        didSet {
            guard height != oldValue else { return }
            apply()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    private func apply() {
        guard height > 80, let window else { return }
        let scale = window.backingScaleFactor
        let snap = { (value: CGFloat) -> CGFloat in
            (value * scale).rounded() / scale
        }
        let targetHeight = min(snap(height), 620)
        let current = window.contentRect(forFrameRect: window.frame)
        guard abs(current.width - 440) > 0.5 || abs(current.height - targetHeight) > 0.5 else { return }
        var content = current
        content.size = NSSize(width: 440, height: targetHeight)
        content.origin.y += current.height - targetHeight
        var frame = window.frameRect(forContentRect: content)
        // Keep the title-bar top on a pixel so the tab row does not drift by a pixel
        // when the content height's fractional part changes.
        let top = snap(frame.maxY)
        frame.size.width = snap(frame.size.width)
        frame.size.height = snap(frame.size.height)
        frame.origin.x = snap(frame.origin.x)
        frame.origin.y = top - frame.size.height
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        window.setFrame(frame, display: false, animate: false)
        NSAnimationContext.endGrouping()
    }
}

private struct SettingsWindowSizer: NSViewRepresentable {
    var height: CGFloat

    func makeNSView(context: Context) -> SettingsSizerView {
        let view = SettingsSizerView(frame: .zero)
        view.autoresizingMask = []
        view.height = height
        return view
    }

    func updateNSView(_ view: SettingsSizerView, context: Context) {
        view.height = height
    }
}

struct SettingsView: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case general, menuBar, rings, flow
        var id: String { rawValue }
    }

    @Bindable var appState: AppState
    @State private var pane: Pane = .general
    @State private var ringEditorTarget: RingEditorTarget = .all
    @State private var flowEditorTarget: FlowEditorTarget = .all
    @State private var saveDialog: SaveTintDialog?

    private enum SaveTintDialog: Identifiable {
        case menuBar, ring, flow, ringIcon, flowIcon
        var id: String {
            switch self {
            case .menuBar: "menuBar"
            case .ring: "ring"
            case .flow: "flow"
            case .ringIcon: "ringIcon"
            case .flowIcon: "flowIcon"
            }
        }
    }

    @State private var savePresetName = ""
    @State private var ringIconsEditorExpanded = false
    @State private var flowIconsEditorExpanded = false
    @State private var menuBarTintEditorExpanded = false
    @State private var ringTintEditorExpanded = false
    @State private var flowTintEditorExpanded = false

    var body: some View {
        let hugHeight = settingsHugsContentHeight
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                settingsTabPicker
                    .padding(.top, 12)
                    .padding(.bottom, 2)

                Form {
                    switch pane {
                    case .general: generalSections
                    case .menuBar: menuBarSections
                    case .rings: ringsSections
                    case .flow: flowSections
                    }
                }
                .formStyle(.grouped)
                // The grouped form paints its own scroll fill, which on macOS 26+
                // is a different shade than the window behind the tabs.
                .scrollContentBackground(.hidden)
                // Collapsed presets should hug the window; only scroll once editors expand.
                .scrollDisabled(hugHeight)
            }
            .fixedSize(horizontal: false, vertical: hugHeight)
            .background {
                GeometryReader { proxy in
                    SettingsWindowSizer(height: proxy.size.height)
                        .frame(width: 0, height: 0)
                }
            }

            // A pixel of slack from snapping the window height stays below the
            // tabs. Without this, AppKit centers that slack and the tab row shifts.
            if hugHeight {
                Spacer(minLength: 0)
            }
        }
        .frame(width: 440, alignment: .top)
        .frame(maxHeight: hugHeight ? .infinity : 620, alignment: .top)
        .animation(nil, value: pane)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, appState.settings.resolvedLocale)
        .id(appState.settings.language)
        .onChange(of: appState.settings.language) { _, _ in
            appState.refreshLocalizedChrome()
        }
        .onChange(of: pane) { _, _ in
            // Drop editor expansion when leaving a tab so returning hugs again.
            menuBarTintEditorExpanded = false
            ringTintEditorExpanded = false
            ringIconsEditorExpanded = false
            flowTintEditorExpanded = false
            flowIconsEditorExpanded = false
        }
        .alert(
            Text("settings.tint.saveAs.title"),
            isPresented: Binding(
                get: { saveDialog != nil },
                set: { if !$0 { saveDialog = nil } }
            )
        ) {
            TextField(Localization.string("settings.tint.save.placeholder", language: appState.settings.language), text: $savePresetName)
            Button("settings.tint.save.confirm") {
                commitSavePreset()
            }
            Button("settings.tint.save.cancel", role: .cancel) {
                saveDialog = nil
                savePresetName = ""
            }
        } message: {
            Text("settings.tint.saveAs.message")
        }
    }

    /// Content-sized and centered, so macOS 14/15 don't stretch the control to the window edges.
    private var settingsTabPicker: some View {
        Picker("settings.title", selection: $pane) {
            Text("settings.section.general").tag(Pane.general)
            Text("settings.section.icon").tag(Pane.menuBar)
            Text("settings.tab.rings").tag(Pane.rings)
            Text("settings.tab.flow").tag(Pane.flow)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: true)
        .frame(maxWidth: .infinity)
    }

    /// Prefer an intrinsic window height until a preset editor is opened.
    private var settingsHugsContentHeight: Bool {
        switch pane {
        case .general:
            true
        case .menuBar:
            !menuBarTintEditorExpanded
        case .rings:
            !ringTintEditorExpanded && !ringIconsEditorExpanded
        case .flow:
            !flowTintEditorExpanded && !flowIconsEditorExpanded
        }
    }

    @ViewBuilder
    private var generalSections: some View {
        Section {
            Picker(selection: $appState.settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(title(for: language)).tag(language)
                }
            } label: {
                Text("settings.language") + Text("（文/A）")
            }
            Toggle("settings.popover.arrow", isOn: $appState.settings.showPopoverArrow)
                .onChange(of: appState.settings.showPopoverArrow) { _, _ in
                    appState.onPopoverChromeChange?()
                }
            Toggle("settings.popover.showRings", isOn: $appState.settings.showStatusRings)
            Toggle("settings.popover.showFlow", isOn: $appState.settings.showEnergyFlow)
            Picker("settings.menuBar.rightClick", selection: $appState.settings.menuBarRightClickAction) {
                ForEach(MenuBarRightClickAction.allCases) { action in
                    Text(LocalizedStringKey(action.localizationKey)).tag(action)
                }
            }
            Toggle("settings.launchAtLogin", isOn: launchAtLoginBinding)
            Toggle("settings.updates.automatic", isOn: $appState.settings.automaticallyCheckForUpdates)
                .onChange(of: appState.settings.automaticallyCheckForUpdates) { _, enabled in
                    if enabled {
                        appState.checkForUpdates(reason: .userEnabled)
                    }
                }
        }

        Section {
            Button("settings.quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
        } footer: {
            HStack(spacing: 6) {
                Text(versionLabel)
                Link(destination: UpdateChecker.githubRepoURL) {
                    Image("GitHubMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                }
                .accessibilityLabel("GitHub")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var menuBarSections: some View {
        Section {
            Picker("settings.icon.border", selection: $appState.settings.iconOutlined) {
                Text("settings.icon.border.off").tag(false)
                Text("settings.icon.border.on").tag(true)
            }
            Picker("settings.icon.digits", selection: $appState.settings.digitPlacement) {
                ForEach(MenuBarDigitPlacement.allCases) { placement in
                    Text(LocalizedStringKey(placement.localizationKey)).tag(placement)
                }
            }
            Toggle("settings.icon.chargeGlyphs", isOn: $appState.settings.showChargeGlyphs)
        }

        Section {
            Picker("settings.icon.tint.preset", selection: menuBarPresetPickerBinding) {
                ForEach(MenuBarTintPreset.pickerCases) { preset in
                    Text(LocalizedStringKey(preset.localizationKey)).tag(MenuBarPresetPickerItem.builtin(preset))
                }
                if !appState.settings.savedTintLibrary.menuBar.isEmpty {
                    Divider()
                    ForEach(appState.settings.savedTintLibrary.menuBar) { item in
                        Text(item.name).tag(MenuBarPresetPickerItem.saved(item.id))
                    }
                }
            }
            collapsiblePresetEditor(
                expanded: $menuBarTintEditorExpanded,
                toolbar: {
                    tintPresetSaveControls(
                        canOverwrite: appState.settings.menuBarActiveSavedID != nil,
                        onSave: { _ = appState.settings.updateMenuBarTintPreset() },
                        onSaveAs: {
                            savePresetName = defaultSaveName(for: .menuBar)
                            saveDialog = .menuBar
                        },
                        deleteID: appState.settings.menuBarActiveSavedID,
                        onDelete: { appState.settings.deleteSavedMenuBarTint(id: $0) }
                    )
                }
            ) {
                if appState.settings.menuBarTint.preset != .off {
                    Picker("settings.icon.tint.when", selection: tintModeBinding) {
                        ForEach(MenuBarTintMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.localizationKey)).tag(mode)
                        }
                    }
                    ForEach(appState.settings.menuBarTint.sortedBands) { band in
                        editableTintBandRow(band)
                    }
                    Button("settings.icon.tint.add") {
                        appState.settings.menuBarTint = appState.settings.menuBarTint.addingBand()
                    }
                }
            }
        }
    }

    private var menuBarPresetPickerBinding: Binding<MenuBarPresetPickerItem> {
        Binding(
            get: {
                if let id = appState.settings.menuBarActiveSavedID {
                    return .saved(id)
                }
                return .builtin(appState.settings.menuBarTint.preset)
            },
            set: { item in
                switch item {
                case .builtin(let preset):
                    appState.settings.applyTintPreset(preset)
                case .saved(let id):
                    appState.settings.applySavedMenuBarTint(id: id)
                }
            }
        )
    }

    private var tintModeBinding: Binding<MenuBarTintMode> {
        Binding(
            get: { appState.settings.menuBarTint.mode },
            set: { mode in
                var scheme = appState.settings.menuBarTint.markedCustom()
                scheme.mode = mode
                appState.settings.menuBarTint = scheme
            }
        )
    }

    private func editableTintBandRow(_ band: MenuBarTintBand) -> some View {
        let range = appState.settings.menuBarTint.percentRange(for: band.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                TintPercentEditor(
                    value: band.throughPercent,
                    range: range,
                    onCommit: { appState.settings.menuBarTint = appState.settings.menuBarTint.replacingBand(id: band.id, throughPercent: $0) }
                )

                Spacer(minLength: 8)

                Picker("settings.icon.tint.blend", selection: tintBlendBinding(band.id)) {
                    ForEach(MenuBarTintBlend.allCases) { blend in
                        Text(LocalizedStringKey(blend.localizationKey)).tag(blend)
                    }
                }
                .labelsHidden()
                .fixedSize()

                if appState.settings.menuBarTint.bands.count > 1 {
                    Button {
                        appState.settings.menuBarTint = appState.settings.menuBarTint.removingBand(id: band.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(LocalizedStringKey("settings.icon.tint.remove"))
                }
            }

            tintWells(band)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func tintWells(_ band: MenuBarTintBand) -> some View {
        switch band.blend {
        case .constant:
            HStack(spacing: 8) {
                Spacer()
                tintWell(label: "settings.icon.tint.color", bandID: band.id, swatch: band.highRight, keyPath: \.highRight)
            }
        case .slide:
            HStack(spacing: 12) {
                Spacer()
                tintWell(label: "settings.icon.tint.low", bandID: band.id, swatch: band.lowRight, keyPath: \.lowRight)
                tintWell(label: "settings.icon.tint.high", bandID: band.id, swatch: band.highRight, keyPath: \.highRight)
            }
        case .gradient:
            HStack(spacing: 12) {
                Spacer()
                tintWell(label: "settings.icon.tint.left", bandID: band.id, swatch: band.highLeft, keyPath: \.highLeft)
                tintWell(label: "settings.icon.tint.right", bandID: band.id, swatch: band.highRight, keyPath: \.highRight)
            }
        case .slideGradient:
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 12) {
                    tintWell(label: "settings.icon.tint.lowLeft", bandID: band.id, swatch: band.lowLeft, keyPath: \.lowLeft)
                    tintWell(label: "settings.icon.tint.lowRight", bandID: band.id, swatch: band.lowRight, keyPath: \.lowRight)
                }
                HStack(spacing: 12) {
                    tintWell(label: "settings.icon.tint.highLeft", bandID: band.id, swatch: band.highLeft, keyPath: \.highLeft)
                    tintWell(label: "settings.icon.tint.highRight", bandID: band.id, swatch: band.highRight, keyPath: \.highRight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func tintWell(
        label: LocalizedStringKey,
        bandID: UUID,
        swatch: MenuBarTintSwatch,
        keyPath: WritableKeyPath<MenuBarTintBand, MenuBarTintSwatch>
    ) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !swatch.followsMenuBar {
                ColorPicker(
                    label,
                    selection: tintColorBinding(bandID, keyPath),
                    supportsOpacity: false
                )
                .labelsHidden()
                .fixedSize()
            }
            Toggle(isOn: tintFollowsMenuBarBinding(bandID, keyPath)) {
                Text("settings.icon.tint.menuBarColor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
        }
    }

    private func tintBlendBinding(_ id: UUID) -> Binding<MenuBarTintBlend> {
        Binding(
            get: { appState.settings.menuBarTint.bands.first(where: { $0.id == id })?.blend ?? .constant },
            set: { blend in
                appState.settings.menuBarTint = appState.settings.menuBarTint.replacingBand(id: id, blend: blend)
            }
        )
    }

    private func tintColorBinding(
        _ id: UUID,
        _ keyPath: WritableKeyPath<MenuBarTintBand, MenuBarTintSwatch>
    ) -> Binding<Color> {
        Binding(
            get: {
                appState.settings.menuBarTint.bands.first(where: { $0.id == id })?[keyPath: keyPath].color ?? .primary
            },
            set: { color in
                replaceSwatch(id: id, keyPath: keyPath, swatch: .from(color: color))
            }
        )
    }

    private func tintFollowsMenuBarBinding(
        _ id: UUID,
        _ keyPath: WritableKeyPath<MenuBarTintBand, MenuBarTintSwatch>
    ) -> Binding<Bool> {
        Binding(
            get: {
                appState.settings.menuBarTint.bands.first(where: { $0.id == id })?[keyPath: keyPath].followsMenuBar ?? false
            },
            set: { follows in
                replaceSwatch(id: id, keyPath: keyPath, swatch: follows ? .menuBar : .systemGreen)
            }
        )
    }

    private func replaceSwatch(
        id: UUID,
        keyPath: WritableKeyPath<MenuBarTintBand, MenuBarTintSwatch>,
        swatch: MenuBarTintSwatch
    ) {
        var scheme = appState.settings.menuBarTint.markedCustom()
        scheme.bands = scheme.bands.map { band in
            guard band.id == id else { return band }
            var next = band
            next[keyPath: keyPath] = swatch
            if next.blend == .constant {
                next.highRight = swatch
                next.highLeft = swatch
                next.lowRight = swatch
                next.lowLeft = swatch
            }
            return next
        }
        appState.settings.menuBarTint = scheme.normalized()
    }

    @ViewBuilder
    private var ringsSections: some View {
        Section {
            Picker("settings.icon.tint.preset", selection: ringPresetPickerBinding) {
                ForEach(PopoverTintPreset.allCases) { preset in
                    Text(LocalizedStringKey(preset.localizationKey)).tag(PopoverPresetPickerItem.builtin(preset))
                }
                if !appState.settings.savedTintLibrary.ring.isEmpty {
                    Divider()
                    ForEach(appState.settings.savedTintLibrary.ring) { item in
                        Text(item.name).tag(PopoverPresetPickerItem.saved(item.id))
                    }
                }
            }
            collapsiblePresetEditor(
                expanded: $ringTintEditorExpanded,
                toolbar: {
                    tintPresetSaveControls(
                        canOverwrite: appState.settings.ringActiveSavedID != nil,
                        onSave: { _ = appState.settings.updateRingTintPreset() },
                        onSaveAs: {
                            savePresetName = defaultSaveName(for: .ring)
                            saveDialog = .ring
                        },
                        deleteID: appState.settings.ringActiveSavedID,
                        onDelete: { appState.settings.deleteSavedRingTint(id: $0) }
                    )
                }
            ) {
                Picker("settings.tint.selection", selection: $ringEditorTarget) {
                    ForEach(RingEditorTarget.allCases) { target in
                        Text(LocalizedStringKey(target.localizationKey)).tag(target)
                    }
                }
                if ringEditorTarget == .all {
                    ForEach(TintSchemeMerge.bands(from: appState.settings.ringTint.allSchemes)) { band in
                        mergedTintBandRow(
                            band,
                            apply: applyRingAllBand,
                            onRemove: {
                                appState.settings.ringTint = appState.settings.ringTint.mapAll { $0.removingBand(at: band.id) }
                            }
                        )
                    }
                    Button("settings.icon.tint.add") {
                        appState.settings.ringTint = appState.settings.ringTint.mapAll { $0.addingBand() }
                    }
                } else if let ring = ringEditorTarget.ring {
                    let scheme = appState.settings.ringTint.scheme(for: ring)
                    ForEach(scheme.sortedBands) { band in
                        editableValueTintBandRow(band, scheme: scheme) { next in
                            appState.settings.ringTint = appState.settings.ringTint.replacing(ring, with: next)
                        }
                    }
                    Button("settings.icon.tint.add") {
                        appState.settings.ringTint = appState.settings.ringTint.replacing(ring, with: scheme.addingBand())
                    }
                }
            }
        }

        Section {
            Picker("settings.icons.preset", selection: ringIconPresetPickerBinding) {
                ForEach(RingIconPreset.allCases) { preset in
                    Text(LocalizedStringKey(preset.localizationKey)).tag(RingIconPresetPickerItem.builtin(preset))
                }
                if !appState.settings.savedIconLibrary.ring.isEmpty {
                    Divider()
                    ForEach(appState.settings.savedIconLibrary.ring) { item in
                        Text(item.name).tag(RingIconPresetPickerItem.saved(item.id))
                    }
                }
            }
            collapsiblePresetEditor(
                expanded: $ringIconsEditorExpanded,
                toolbar: {
                    iconPresetEditorCaption(
                        canOverwrite: appState.settings.ringActiveSavedIconID != nil,
                        onSave: { _ = appState.settings.updateRingIconPreset() },
                        onSaveAs: {
                            savePresetName = defaultSaveName(for: .ringIcon)
                            saveDialog = .ringIcon
                        },
                        deleteID: appState.settings.ringActiveSavedIconID,
                        onDelete: { appState.settings.deleteSavedRingIcon(id: $0) }
                    )
                }
            ) {
                HStack(spacing: 10) {
                    ForEach(RingKind.allCases) { kind in
                        ringIconSlotControl(kind)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var flowSections: some View {
        Section {
            Picker("settings.icon.tint.preset", selection: flowPresetPickerBinding) {
                ForEach(PopoverTintPreset.allCases) { preset in
                    Text(LocalizedStringKey(preset.localizationKey)).tag(PopoverPresetPickerItem.builtin(preset))
                }
                if !appState.settings.savedTintLibrary.flow.isEmpty {
                    Divider()
                    ForEach(appState.settings.savedTintLibrary.flow) { item in
                        Text(item.name).tag(PopoverPresetPickerItem.saved(item.id))
                    }
                }
            }
            collapsiblePresetEditor(
                expanded: $flowTintEditorExpanded,
                toolbar: {
                    tintPresetSaveControls(
                        canOverwrite: appState.settings.flowActiveSavedID != nil,
                        onSave: { _ = appState.settings.updateFlowTintPreset() },
                        onSaveAs: {
                            savePresetName = defaultSaveName(for: .flow)
                            saveDialog = .flow
                        },
                        deleteID: appState.settings.flowActiveSavedID,
                        onDelete: { appState.settings.deleteSavedFlowTint(id: $0) }
                    )
                }
            ) {
                Picker("settings.tint.selection", selection: $flowEditorTarget) {
                    ForEach(FlowEditorTarget.allCases) { target in
                        Text(LocalizedStringKey(target.localizationKey)).tag(target)
                    }
                }
                if flowEditorTarget == .all {
                    ForEach(TintSchemeMerge.bands(from: appState.settings.flowTint.allSchemes)) { band in
                        mergedTintBandRow(
                            band,
                            apply: applyFlowAllBand,
                            onRemove: {
                                appState.settings.flowTint = appState.settings.flowTint.mapAll { $0.removingBand(at: band.id) }
                            }
                        )
                    }
                    Button("settings.icon.tint.add") {
                        appState.settings.flowTint = appState.settings.flowTint.mapAll { $0.addingBand() }
                    }
                } else if let mode = flowEditorTarget.mode {
                    let scheme = appState.settings.flowTint.scheme(for: mode)
                    ForEach(scheme.sortedBands) { band in
                        editableValueTintBandRow(band, scheme: scheme) { next in
                            appState.settings.flowTint = appState.settings.flowTint.replacing(mode, with: next)
                        }
                    }
                    Button("settings.icon.tint.add") {
                        appState.settings.flowTint = appState.settings.flowTint.replacing(mode, with: scheme.addingBand())
                    }
                }

                Toggle(isOn: motionColorEnabledBinding) {
                    Text("settings.flow.tint.motionColor")
                }
                if appState.settings.flowTint.motionColor != nil {
                    ColorPicker(
                        "settings.flow.tint.motionColor",
                        selection: motionColorBinding,
                        supportsOpacity: false
                    )
                }
            }
        }

        Section {
            Picker("settings.icons.preset", selection: flowIconPresetPickerBinding) {
                ForEach(FlowIconPreset.allCases) { preset in
                    Text(LocalizedStringKey(preset.localizationKey)).tag(FlowIconPresetPickerItem.builtin(preset))
                }
                if !appState.settings.savedIconLibrary.flow.isEmpty {
                    Divider()
                    ForEach(appState.settings.savedIconLibrary.flow) { item in
                        Text(item.name).tag(FlowIconPresetPickerItem.saved(item.id))
                    }
                }
            }
            collapsiblePresetEditor(
                expanded: $flowIconsEditorExpanded,
                toolbar: {
                    iconPresetEditorCaption(
                        canOverwrite: appState.settings.flowActiveSavedIconID != nil,
                        onSave: { _ = appState.settings.updateFlowIconPreset() },
                        onSaveAs: {
                            savePresetName = defaultSaveName(for: .flowIcon)
                            saveDialog = .flowIcon
                        },
                        deleteID: appState.settings.flowActiveSavedIconID,
                        onDelete: { appState.settings.deleteSavedFlowIcon(id: $0) }
                    )
                }
            ) {
                HStack(spacing: 10) {
                    ForEach(FlowIconRole.allCases) { role in
                        flowIconSlotControl(role)
                    }
                }
            }
            FlowIconSizeControl(settings: appState.settings)
        }

        Section {
            Picker("settings.motion.style", selection: $appState.settings.motionStyle) {
                ForEach(EnergyMotionStyle.allCases) { style in
                    Text(LocalizedStringKey(style.localizationKey)).tag(style)
                }
            }
            Picker("settings.motion.frameRate", selection: $appState.settings.motionFrameRate) {
                ForEach(EnergyMotionFrameRate.allCases) { rate in
                    Text(rate.title).tag(rate)
                }
            }
            .disabled(appState.settings.motionStyle == .off)
            Toggle("settings.motion.pulseIcons", isOn: $appState.settings.pulseFlowIcons)
        }
    }

    private var ringIconPresetPickerBinding: Binding<RingIconPresetPickerItem> {
        Binding(
            get: {
                if let id = appState.settings.ringActiveSavedIconID {
                    return .saved(id)
                }
                return .builtin(appState.settings.ringIcons.preset)
            },
            set: { item in
                switch item {
                case .builtin(let preset):
                    appState.settings.applyRingIconPreset(preset)
                case .saved(let id):
                    appState.settings.applySavedRingIcon(id: id)
                }
            }
        )
    }

    private var flowIconPresetPickerBinding: Binding<FlowIconPresetPickerItem> {
        Binding(
            get: {
                if let id = appState.settings.flowActiveSavedIconID {
                    return .saved(id)
                }
                return .builtin(appState.settings.flowIcons.preset)
            },
            set: { item in
                switch item {
                case .builtin(let preset):
                    appState.settings.applyFlowIconPreset(preset)
                case .saved(let id):
                    appState.settings.applySavedFlowIcon(id: id)
                }
            }
        )
    }

    @ViewBuilder
    private func collapsiblePresetEditor<Toolbar: View, Content: View>(
        expanded: Binding<Bool>,
        @ViewBuilder toolbar: () -> Toolbar,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                Text(
                    expanded.wrappedValue
                        ? LocalizedStringKey("settings.icons.hidePreset")
                        : LocalizedStringKey("settings.icons.editPreset")
                )
            }
            if expanded.wrappedValue {
                toolbar()
            }
            Spacer(minLength: 0)
        }
        if expanded.wrappedValue {
            content()
        }
    }

    @ViewBuilder
    private func tintPresetSaveControls(
        canOverwrite: Bool,
        onSave: @escaping () -> Void,
        onSaveAs: @escaping () -> Void,
        deleteID: UUID?,
        onDelete: @escaping (UUID) -> Void
    ) -> some View {
        if canOverwrite {
            Button("settings.tint.save", action: onSave)
        }
        Button("settings.tint.saveAs", action: onSaveAs)
        if let deleteID {
            Button("settings.tint.delete", role: .destructive) {
                onDelete(deleteID)
            }
        }
        if !canOverwrite {
            Text("settings.icons.builtinEditNote")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func iconPresetEditorCaption(
        canOverwrite: Bool,
        onSave: @escaping () -> Void,
        onSaveAs: @escaping () -> Void,
        deleteID: UUID?,
        onDelete: @escaping (UUID) -> Void
    ) -> some View {
        Text("settings.icons.clickToChange")
            .font(.caption)
            .foregroundStyle(.secondary)
        tintPresetSaveControls(
            canOverwrite: canOverwrite,
            onSave: onSave,
            onSaveAs: onSaveAs,
            deleteID: deleteID,
            onDelete: onDelete
        )
    }

    private var iconSlotColumnWidth: CGFloat { 56 }

    private func iconZoomSlider(value: Binding<Double>) -> some View {
        let percent = Int((value.wrappedValue * 100).rounded())
        return VStack(spacing: 2) {
            Slider(value: value, in: GlyphSlot.minScale...GlyphSlot.maxScale, step: 0.01)
                .controlSize(.mini)
                .labelsHidden()
            Text("\(percent)%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .frame(width: iconSlotColumnWidth)
        .help(Localization.string("settings.icons.zoom", language: appState.settings.language))
    }

    @ViewBuilder
    private func ringIconSlotControl(_ kind: RingKind) -> some View {
        let language = appState.settings.language
        let slot = appState.settings.ringIcons.slot(for: kind)
        VStack(spacing: 6) {
            Text(Localization.string(kind.localizationKey, language: language))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: iconSlotColumnWidth)
                .multilineTextAlignment(.center)
            iconSlotMenuPreview(slot: slot) {
                Button(Localization.string("settings.icons.upload", language: language)) {
                    uploadRingIcon(kind)
                }
                if slot.source == .custom {
                    Toggle(
                        Localization.string("settings.icons.template", language: language),
                        isOn: ringTemplateBinding(kind)
                    )
                }
                Divider()
                ForEach(Array(kind.symbolChoices.enumerated()), id: \.offset) { _, choice in
                    Button {
                        appState.settings.ringIcons = appState.settings.ringIcons.replacing(
                            kind,
                            with: choice.withScale(slot.scale)
                        )
                    } label: {
                        Label {
                            Text(choice.name)
                        } icon: {
                            GlyphSlotView(slot: choice, systemPointSize: 13, assetSide: 14)
                        }
                    }
                }
            }
            iconZoomSlider(
                value: Binding(
                    get: { appState.settings.ringIcons.slot(for: kind).scale },
                    set: { appState.settings.ringIcons = appState.settings.ringIcons.withScale($0, for: kind) }
                )
            )
        }
        .frame(width: iconSlotColumnWidth)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func flowIconSlotControl(_ role: FlowIconRole) -> some View {
        let language = appState.settings.language
        let slot = appState.settings.flowIcons.slot(for: role)
        VStack(spacing: 6) {
            Text(Localization.string(role.localizationKey, language: language))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: iconSlotColumnWidth)
                .multilineTextAlignment(.center)
            iconSlotMenuPreview(slot: slot) {
                Button(Localization.string("settings.icons.upload", language: language)) {
                    uploadFlowIcon(role)
                }
                if slot.source == .custom {
                    Toggle(
                        Localization.string("settings.icons.template", language: language),
                        isOn: flowTemplateBinding(role)
                    )
                }
                Divider()
                ForEach(Array(role.symbolChoices.enumerated()), id: \.offset) { _, choice in
                    Button {
                        appState.settings.flowIcons = appState.settings.flowIcons.replacing(
                            role,
                            with: choice.withScale(slot.scale),
                            syncCharging: role == .battery
                        )
                    } label: {
                        Label {
                            Text(choice.name)
                        } icon: {
                            GlyphSlotView(slot: choice, systemPointSize: 13, assetSide: 14)
                        }
                    }
                }
            }
            iconZoomSlider(
                value: Binding(
                    get: { appState.settings.flowIcons.slot(for: role).scale },
                    set: { appState.settings.flowIcons = appState.settings.flowIcons.withScale($0, for: role) }
                )
            )
        }
        .frame(width: iconSlotColumnWidth)
        .frame(maxWidth: .infinity)
    }

    /// Fixed-size glyph preview; no chevron — caption says to click the icon.
    @ViewBuilder
    private func iconSlotMenuPreview<Content: View>(
        slot: GlyphSlot,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let side = iconSlotColumnWidth - 8
        Menu(content: content) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                GlyphSlotView(slot: slot, systemPointSize: 17, assetSide: 20)
            }
            .frame(width: side, height: side)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: side, height: side)
        .help(Localization.string("settings.icons.clickToChange", language: appState.settings.language))
    }

    private func ringTemplateBinding(_ kind: RingKind) -> Binding<Bool> {
        Binding(
            get: { appState.settings.ringIcons.slot(for: kind).template },
            set: { enabled in
                var slot = appState.settings.ringIcons.slot(for: kind)
                slot.template = enabled
                appState.settings.ringIcons = appState.settings.ringIcons.replacing(kind, with: slot)
            }
        )
    }

    private func flowTemplateBinding(_ role: FlowIconRole) -> Binding<Bool> {
        Binding(
            get: { appState.settings.flowIcons.slot(for: role).template },
            set: { enabled in
                var slot = appState.settings.flowIcons.slot(for: role)
                slot.template = enabled
                let sync = role == .battery && slot.source == .custom
                appState.settings.flowIcons = appState.settings.flowIcons.replacing(role, with: slot, syncCharging: sync)
            }
        )
    }

    private func uploadRingIcon(_ kind: RingKind) {
        let title = Localization.string("settings.icons.upload", language: appState.settings.language)
        let slot = appState.settings.ringIcons.slot(for: kind)
        guard let url = CustomIconStore.pickImage(title: title),
              let id = CustomIconStore.save(fromFile: url) else { return }
        appState.settings.ringIcons = appState.settings.ringIcons.replacing(
            kind,
            with: .customFile(id, scale: slot.scale)
        )
    }

    private func uploadFlowIcon(_ role: FlowIconRole) {
        let title = Localization.string("settings.icons.upload", language: appState.settings.language)
        let previousScale = appState.settings.flowIcons.slot(for: role).scale
        guard let url = CustomIconStore.pickImage(title: title),
              let id = CustomIconStore.save(fromFile: url) else { return }
        appState.settings.flowIcons = appState.settings.flowIcons.replacing(
            role,
            with: .customFile(id, scale: previousScale),
            syncCharging: role == .battery
        )
    }

    private var ringPresetPickerBinding: Binding<PopoverPresetPickerItem> {
        Binding(
            get: {
                if let id = appState.settings.ringActiveSavedID {
                    return .saved(id)
                }
                return .builtin(appState.settings.ringTint.preset)
            },
            set: { item in
                switch item {
                case .builtin(let preset):
                    appState.settings.applyRingTintPreset(preset)
                case .saved(let id):
                    appState.settings.applySavedRingTint(id: id)
                }
            }
        )
    }

    private var flowPresetPickerBinding: Binding<PopoverPresetPickerItem> {
        Binding(
            get: {
                if let id = appState.settings.flowActiveSavedID {
                    return .saved(id)
                }
                return .builtin(appState.settings.flowTint.preset)
            },
            set: { item in
                switch item {
                case .builtin(let preset):
                    appState.settings.applyFlowTintPreset(preset)
                case .saved(let id):
                    appState.settings.applySavedFlowTint(id: id)
                }
            }
        )
    }

    private func defaultSaveName(for dialog: SaveTintDialog) -> String {
        let base = Localization.string("settings.tint.save.defaultName", language: appState.settings.language)
        let count: Int = {
            switch dialog {
            case .menuBar: appState.settings.savedTintLibrary.menuBar.count
            case .ring: appState.settings.savedTintLibrary.ring.count
            case .flow: appState.settings.savedTintLibrary.flow.count
            case .ringIcon: appState.settings.savedIconLibrary.ring.count
            case .flowIcon: appState.settings.savedIconLibrary.flow.count
            }
        }()
        return "\(base) \(count + 1)"
    }

    private func commitSavePreset() {
        defer {
            saveDialog = nil
            savePresetName = ""
        }
        guard let saveDialog else { return }
        switch saveDialog {
        case .menuBar:
            _ = appState.settings.saveMenuBarTintPreset(named: savePresetName)
        case .ring:
            _ = appState.settings.saveRingTintPreset(named: savePresetName)
        case .flow:
            _ = appState.settings.saveFlowTintPreset(named: savePresetName)
        case .ringIcon:
            _ = appState.settings.saveRingIconPreset(named: savePresetName)
        case .flowIcon:
            _ = appState.settings.saveFlowIconPreset(named: savePresetName)
        }
    }

    private var motionColorEnabledBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.flowTint.motionColor != nil },
            set: { enabled in
                var tint = appState.settings.flowTint.markedCustom()
                tint.motionColor = enabled ? (tint.motionColor ?? .systemGreen) : nil
                appState.settings.flowTint = tint
            }
        )
    }

    private var motionColorBinding: Binding<Color> {
        Binding(
            get: { appState.settings.flowTint.motionColor?.color ?? .green },
            set: { color in
                var tint = appState.settings.flowTint.markedCustom()
                tint.motionColor = .from(color: color)
                appState.settings.flowTint = tint
            }
        )
    }

    private func editableValueTintBandRow(
        _ band: MenuBarTintBand,
        scheme: ValueTintScheme,
        update: @escaping (ValueTintScheme) -> Void
    ) -> some View {
        let range = scheme.percentRange(for: band.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                TintPercentEditor(
                    value: band.throughPercent,
                    range: range,
                    onCommit: { update(scheme.replacingBand(id: band.id, throughPercent: $0)) }
                )

                Spacer(minLength: 8)

                Picker("settings.icon.tint.blend", selection: Binding(
                    get: { band.blend },
                    set: { update(scheme.replacingBand(id: band.id, blend: $0)) }
                )) {
                    ForEach(MenuBarTintBlend.allCases) { blend in
                        Text(LocalizedStringKey(blend.localizationKey)).tag(blend)
                    }
                }
                .labelsHidden()
                .fixedSize()

                if scheme.bands.count > 1 {
                    Button {
                        update(scheme.removingBand(id: band.id))
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(LocalizedStringKey("settings.icon.tint.remove"))
                }
            }

            valueTintWells(band, scheme: scheme, update: update)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func valueTintWells(
        _ band: MenuBarTintBand,
        scheme: ValueTintScheme,
        update: @escaping (ValueTintScheme) -> Void
    ) -> some View {
        switch band.blend {
        case .constant:
            HStack(spacing: 8) {
                Spacer()
                valueTintWell(label: "settings.icon.tint.color", band: band, scheme: scheme, keyPath: \.highRight, update: update)
            }
        case .slide:
            HStack(spacing: 12) {
                Spacer()
                valueTintWell(label: "settings.icon.tint.low", band: band, scheme: scheme, keyPath: \.lowRight, update: update)
                valueTintWell(label: "settings.icon.tint.high", band: band, scheme: scheme, keyPath: \.highRight, update: update)
            }
        case .gradient:
            HStack(spacing: 12) {
                Spacer()
                valueTintWell(label: "settings.icon.tint.left", band: band, scheme: scheme, keyPath: \.highLeft, update: update)
                valueTintWell(label: "settings.icon.tint.right", band: band, scheme: scheme, keyPath: \.highRight, update: update)
            }
        case .slideGradient:
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 12) {
                    valueTintWell(label: "settings.icon.tint.lowLeft", band: band, scheme: scheme, keyPath: \.lowLeft, update: update)
                    valueTintWell(label: "settings.icon.tint.lowRight", band: band, scheme: scheme, keyPath: \.lowRight, update: update)
                }
                HStack(spacing: 12) {
                    valueTintWell(label: "settings.icon.tint.highLeft", band: band, scheme: scheme, keyPath: \.highLeft, update: update)
                    valueTintWell(label: "settings.icon.tint.highRight", band: band, scheme: scheme, keyPath: \.highRight, update: update)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func valueTintWell(
        label: LocalizedStringKey,
        band: MenuBarTintBand,
        scheme: ValueTintScheme,
        keyPath: WritableKeyPath<MenuBarTintBand, MenuBarTintSwatch>,
        update: @escaping (ValueTintScheme) -> Void
    ) -> some View {
        let swatch = band[keyPath: keyPath]
        return HStack(spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !swatch.followsMenuBar {
                ColorPicker(
                    label,
                    selection: Binding(
                        get: { swatch.color },
                        set: { color in
                            update(scheme.replacingBand(at: scheme.sortedBands.firstIndex(where: { $0.id == band.id }) ?? 0) { band in
                                band[keyPath: keyPath] = .from(color: color)
                                if band.blend == .constant {
                                    let s = MenuBarTintSwatch.from(color: color)
                                    band.highRight = s
                                    band.highLeft = s
                                    band.lowRight = s
                                    band.lowLeft = s
                                }
                            })
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .fixedSize()
            }
            Toggle(isOn: Binding(
                get: { swatch.followsMenuBar },
                set: { follows in
                    let next: MenuBarTintSwatch = follows ? .menuBar : .systemGreen
                    update(scheme.replacingBand(at: scheme.sortedBands.firstIndex(where: { $0.id == band.id }) ?? 0) { band in
                        band[keyPath: keyPath] = next
                        if band.blend == .constant {
                            band.highRight = next
                            band.highLeft = next
                            band.lowRight = next
                            band.lowLeft = next
                        }
                    })
                }
            )) {
                Text("settings.icon.tint.menuBarColor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
        }
    }

    private func mergedTintBandRow(
        _ band: MergedTintBand,
        apply: @escaping (Int, (inout MenuBarTintBand) -> Void) -> Void,
        onRemove: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                MergedTintPercentEditor(
                    value: band.throughPercent,
                    range: 1...100,
                    onCommit: { percent in
                        apply(band.id) { $0.throughPercent = percent }
                    }
                )

                Spacer(minLength: 8)

                Picker("settings.icon.tint.blend", selection: Binding(
                    get: { band.blend },
                    set: { blend in
                        guard let blend else { return }
                        apply(band.id) { $0.blend = blend }
                    }
                )) {
                    Text("-").tag(Optional<MenuBarTintBlend>.none)
                    ForEach(MenuBarTintBlend.allCases) { blend in
                        Text(LocalizedStringKey(blend.localizationKey)).tag(Optional.some(blend))
                    }
                }
                .labelsHidden()
                .fixedSize()

                if band.presentInAll {
                    Button(action: onRemove) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(LocalizedStringKey("settings.icon.tint.remove"))
                }
            }

            mergedTintWells(band, apply: apply)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func mergedTintWells(
        _ band: MergedTintBand,
        apply: @escaping (Int, (inout MenuBarTintBand) -> Void) -> Void
    ) -> some View {
        let blend = band.blend ?? .constant
        switch blend {
        case .constant:
            HStack(spacing: 8) {
                Spacer()
                mergedTintWell(label: "settings.icon.tint.color", swatch: band.highRight) { swatch in
                    apply(band.id) { band in
                        band.highRight = swatch
                        band.highLeft = swatch
                        band.lowRight = swatch
                        band.lowLeft = swatch
                    }
                }
            }
        case .slide:
            HStack(spacing: 12) {
                Spacer()
                mergedTintWell(label: "settings.icon.tint.low", swatch: band.lowRight) { swatch in
                    apply(band.id) { $0.lowRight = swatch }
                }
                mergedTintWell(label: "settings.icon.tint.high", swatch: band.highRight) { swatch in
                    apply(band.id) { $0.highRight = swatch }
                }
            }
        case .gradient:
            HStack(spacing: 12) {
                Spacer()
                mergedTintWell(label: "settings.icon.tint.left", swatch: band.highLeft) { swatch in
                    apply(band.id) { $0.highLeft = swatch }
                }
                mergedTintWell(label: "settings.icon.tint.right", swatch: band.highRight) { swatch in
                    apply(band.id) { $0.highRight = swatch }
                }
            }
        case .slideGradient:
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 12) {
                    mergedTintWell(label: "settings.icon.tint.lowLeft", swatch: band.lowLeft) { swatch in
                        apply(band.id) { $0.lowLeft = swatch }
                    }
                    mergedTintWell(label: "settings.icon.tint.lowRight", swatch: band.lowRight) { swatch in
                        apply(band.id) { $0.lowRight = swatch }
                    }
                }
                HStack(spacing: 12) {
                    mergedTintWell(label: "settings.icon.tint.highLeft", swatch: band.highLeft) { swatch in
                        apply(band.id) { $0.highLeft = swatch }
                    }
                    mergedTintWell(label: "settings.icon.tint.highRight", swatch: band.highRight) { swatch in
                        apply(band.id) { $0.highRight = swatch }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func mergedTintWell(
        label: LocalizedStringKey,
        swatch: MenuBarTintSwatch?,
        onChange: @escaping (MenuBarTintSwatch) -> Void
    ) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if swatch == nil {
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .center)
            }
            if swatch?.followsMenuBar != true {
                ColorPicker(
                    label,
                    selection: Binding(
                        get: { swatch?.color ?? .gray },
                        set: { onChange(.from(color: $0)) }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .fixedSize()
            }
            Toggle(isOn: Binding(
                get: { swatch?.followsMenuBar ?? false },
                set: { follows in
                    onChange(follows ? .menuBar : .systemGreen)
                }
            )) {
                Text("settings.icon.tint.menuBarColor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
        }
    }

    private func applyRingAllBand(at index: Int, mutate: (inout MenuBarTintBand) -> Void) {
        appState.settings.ringTint = appState.settings.ringTint.mapAll { scheme in
            scheme.replacingBand(at: index, mutate: mutate)
        }
    }

    private func applyFlowAllBand(at index: Int, mutate: (inout MenuBarTintBand) -> Void) {
        appState.settings.flowTint = appState.settings.flowTint.mapAll { scheme in
            scheme.replacingBand(at: index, mutate: mutate)
        }
    }

    private var versionLabel: String {
        Localization.string(
            "settings.about.version %@",
            language: appState.settings.language,
            AppState.marketingVersion
        )
    }

    private func title(for language: AppLanguage) -> String {
        if language == .system {
            return Localization.string("settings.language.system", language: appState.settings.language)
        }
        return language.nativeName
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.launchAtLoginEnabled },
            set: { appState.setLaunchAtLogin($0) }
        )
    }
}

private struct TintPercentEditor: View {
    let value: Int
    let range: ClosedRange<Int>
    let onCommit: (Int) -> Void

    @State private var draft: String
    @State private var focused = false

    init(value: Int, range: ClosedRange<Int>, onCommit: @escaping (Int) -> Void) {
        self.value = value
        self.range = range
        self.onCommit = onCommit
        _draft = State(initialValue: "\(value)")
    }

    private var locked: Bool { range.lowerBound == range.upperBound }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Stepper("", value: Binding(
                get: { value },
                set: { next in
                    onCommit(next)
                    draft = "\(next)"
                }
            ), in: range)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .disabled(locked)

            Text("≤")
                .foregroundStyle(.secondary)

            CenteredPercentField(
                text: $draft,
                isEnabled: !locked,
                isFocused: $focused,
                onCommit: commit
            )
            .frame(width: 44, height: 22)

            Text("%")
                .foregroundStyle(.secondary)
        }
        .onAppear { draft = "\(value)" }
        .onChange(of: value) { _, newValue in
            if !focused { draft = "\(newValue)" }
        }
    }

    private func commit() {
        let next = MenuBarTintPercentInput.commit(draft, range: range, fallback: value)
        draft = "\(next)"
        if next != value {
            onCommit(next)
        }
    }
}

/// Percent field for merged "all" editors. `nil` shows "-" until the user types a number.
private struct MergedTintPercentEditor: View {
    let value: Int?
    let range: ClosedRange<Int>
    let onCommit: (Int) -> Void

    @State private var draft: String
    @State private var focused = false

    init(value: Int?, range: ClosedRange<Int>, onCommit: @escaping (Int) -> Void) {
        self.value = value
        self.range = range
        self.onCommit = onCommit
        _draft = State(initialValue: value.map(String.init) ?? "-")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if let value {
                Stepper("", value: Binding(
                    get: { value },
                    set: { next in
                        onCommit(next)
                        draft = "\(next)"
                    }
                ), in: range)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            } else {
                Stepper("", value: .constant(50), in: range)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(true)
            }

            Text("≤")
                .foregroundStyle(.secondary)

            CenteredPercentField(
                text: $draft,
                isEnabled: true,
                isFocused: $focused,
                onCommit: commit
            )
            .frame(width: 44, height: 22)

            Text("%")
                .foregroundStyle(.secondary)
        }
        .onAppear { draft = value.map(String.init) ?? "-" }
        .onChange(of: value) { _, newValue in
            if !focused { draft = newValue.map(String.init) ?? "-" }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "-" {
            draft = value.map(String.init) ?? "-"
            return
        }
        let fallback = value ?? range.lowerBound
        let next = MenuBarTintPercentInput.commit(draft, range: range, fallback: fallback)
        // Only apply when the user typed a parseable number (not junk reverting to fallback while mixed).
        if value == nil {
            let digits = trimmed.filter(\.isNumber)
            guard !digits.isEmpty else {
                draft = "-"
                return
            }
        }
        draft = "\(next)"
        if next != value {
            onCommit(next)
        }
    }
}

/// One row: label, editable percent, then the slider. Typed sizes run 10...1000.
/// The slider stays on its narrower range and pins when the number sits outside it.
private struct FlowIconSizeControl: View {
    @Bindable var settings: AppSettings
    @State private var draft: String
    @State private var focused = false

    private static let editRange = 10...1000

    init(settings: AppSettings) {
        self.settings = settings
        _draft = State(initialValue: "\(Self.percent(of: settings.flowIconScale))")
    }

    var body: some View {
        let percent = Self.percent(of: settings.flowIconScale)
        HStack(spacing: 8) {
            Text("settings.flow.iconSize")
            Spacer(minLength: 8)
            CenteredPercentField(
                text: $draft,
                isEnabled: true,
                isFocused: $focused,
                onCommit: commit
            )
            .frame(width: 52, height: 22)
            Text("%")
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: {
                        min(
                            max(settings.flowIconScale, AppSettings.flowIconScaleSliderBounds.lowerBound),
                            AppSettings.flowIconScaleSliderBounds.upperBound
                        )
                    },
                    set: { settings.flowIconScale = $0 }
                ),
                in: AppSettings.flowIconScaleSliderBounds
            )
            .frame(width: 148)
        }
        .onChange(of: percent) { _, newValue in
            if !focused { draft = "\(newValue)" }
        }
    }

    private func commit() {
        let next = MenuBarTintPercentInput.commit(draft, range: Self.editRange, fallback: Self.percent(of: settings.flowIconScale))
        draft = "\(next)"
        let scale = Double(next) / 100
        if scale != settings.flowIconScale {
            settings.flowIconScale = scale
        }
    }

    private static func percent(of scale: Double) -> Int {
        Int((scale * 100).rounded())
    }
}

/// AppKit field so digits sit vertically centered — SwiftUI `TextField` baseline is low on macOS.
private struct CenteredPercentField: NSViewRepresentable {
    @Binding var text: String
    var isEnabled: Bool
    @Binding var isFocused: Bool
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let cell = VerticallyCenteredTextFieldCell(textCell: text)
        cell.isEditable = true
        cell.isSelectable = true
        cell.isBordered = true
        cell.isBezeled = true
        cell.bezelStyle = .roundedBezel
        cell.drawsBackground = true
        cell.backgroundColor = .textBackgroundColor
        cell.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        cell.alignment = .center
        cell.controlSize = .regular

        let field = NSTextField(frame: .zero)
        field.cell = cell
        field.focusRingType = .default
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submitted(_:))
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text, field.currentEditor() == nil {
            field.stringValue = text
        }
        field.isEnabled = isEnabled
        field.isEditable = isEnabled
        field.alphaValue = isEnabled ? 1 : 0.45
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CenteredPercentField

        init(_ parent: CenteredPercentField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused = true
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.isFocused = false
            parent.onCommit()
        }

        @objc func submitted(_ sender: NSTextField) {
            parent.text = sender.stringValue
            parent.onCommit()
            sender.window?.makeFirstResponder(nil)
        }
    }
}

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let ideal = super.drawingRect(forBounds: rect)
        let size = cellSize(forBounds: rect)
        let delta = ideal.height - size.height
        guard delta > 0 else { return ideal }
        return NSRect(
            x: ideal.origin.x,
            y: ideal.origin.y + delta / 2,
            width: ideal.width,
            height: size.height
        )
    }
}
