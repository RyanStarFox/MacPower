import SwiftUI

enum PopoverLayout {
    /// Fixed panel width shared with `StatusItemController` so NSPopover's
    /// `contentSize` cannot drift narrower than the SwiftUI layout (macOS 15
    /// was clipping both sides when intrinsic width failed to propagate).
    static let width: CGFloat = 420
    static let padding: CGFloat = 14
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
                    .frame(width: PopoverLayout.width)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Keep the hosting graph mounted, but never build glass / TimelineView
                // while the menu extra is idle. Interactive Liquid Glass in a hidden
                // NSPopover was burning CPU and UAFing NSViewFocusProxy ~2s after launch.
                Color.clear.frame(width: PopoverLayout.width, height: 1)
            }
        }
        .environment(\.locale, appState.settings.resolvedLocale)
        .id(appState.settings.language)
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
                } else if !showRings {
                    settingsButton
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var ringsHeader: some View {
        let language = appState.settings.language
        let ringTint = appState.settings.ringTint
        let ringIcons = appState.settings.ringIcons
        let battery = Int(appState.snapshot.percent.rounded())
        let cpu = Int(appState.metrics.cpuPercent.rounded())
        let gpu = Int(appState.metrics.gpuPercent.rounded())
        let memory = Int(appState.metrics.memoryPercent.rounded())
        let batteryColors = ringTint.scheme(for: .battery).colors(percent: appState.snapshot.percent)
        let cpuColors = ringTint.scheme(for: .cpu).colors(percent: appState.metrics.cpuPercent)
        let gpuColors = ringTint.scheme(for: .gpu).colors(percent: appState.metrics.gpuPercent)
        let memoryColors = ringTint.scheme(for: .memory).colors(percent: appState.metrics.memoryPercent)
        return HStack(alignment: .top, spacing: 8) {
            StatusRingView(
                percent: appState.snapshot.percent,
                fillLeft: batteryColors.left,
                fillRight: batteryColors.right,
                caption: Localization.string("ring.caption.battery %lld", language: language, Int64(battery)),
                accessibilityName: Localization.string("ring.battery", language: language),
                glyph: ringIcons.slot(for: .battery)
            )
            StatusRingView(
                percent: appState.metrics.cpuPercent,
                fillLeft: cpuColors.left,
                fillRight: cpuColors.right,
                caption: Localization.string("ring.caption.cpu %lld", language: language, Int64(cpu)),
                accessibilityName: Localization.string("ring.cpu", language: language),
                glyph: ringIcons.slot(for: .cpu)
            )
            StatusRingView(
                percent: appState.metrics.gpuPercent,
                fillLeft: gpuColors.left,
                fillRight: gpuColors.right,
                caption: Localization.string("ring.caption.gpu %lld", language: language, Int64(gpu)),
                accessibilityName: Localization.string("ring.gpu", language: language),
                glyph: ringIcons.slot(for: .gpu)
            )
            StatusRingView(
                percent: appState.metrics.memoryPercent,
                fillLeft: memoryColors.left,
                fillRight: memoryColors.right,
                caption: Localization.string("ring.caption.memory %lld", language: language, Int64(memory)),
                accessibilityName: Localization.string("ring.memory", language: language),
                glyph: ringIcons.slot(for: .memory)
            )
            settingsButton
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
