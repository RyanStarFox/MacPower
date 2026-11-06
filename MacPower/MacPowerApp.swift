import AppKit
import SwiftUI

@main
struct MacPowerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if ReadmeAssetCapture.startIfNeeded() { return }
        #endif
        NSApp.setActivationPolicy(.accessory)
        let state = AppState()
        appState = state
        statusItemController = StatusItemController(appState: state)
        state.onLanguageChange = { [weak statusItemController] in
            statusItemController?.applyLocalization()
        }
        state.onPopoverChromeChange = { [weak statusItemController] in
            statusItemController?.applyArrowVisibility()
        }
        state.onPopoverLayoutChange = { [weak statusItemController] in
            statusItemController?.adoptPopoverLayoutIfNeeded()
        }
        state.onMenuBarNeedsRefresh = { [weak statusItemController] in
            statusItemController?.refreshIcon()
        }
        statusItemController?.refreshIcon(force: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stopAutomaticUpdateChecks()
        appState?.telemetry.stop()
        appState?.metricsService.stop()
    }
}

/// Only fields that actually change the menu-bar glyph. Watts jitter must not redraw it.
struct MenuBarIconKey: Equatable {
    var percent: Int
    var flowMode: EnergyFlowMode
    var lowPowerMode: Bool
    var outlined: Bool
    var digits: MenuBarDigitPlacement
    var tint: MenuBarTintScheme
    var showChargeGlyphs: Bool
    var language: AppLanguage

    @MainActor
    init(_ state: AppState) {
        percent = Int(state.snapshot.percent.rounded(.towardZero))
        flowMode = state.snapshot.flowMode
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        outlined = state.settings.iconOutlined
        digits = state.settings.digitPlacement
        tint = state.settings.menuBarTint
        showChargeGlyphs = state.settings.showChargeGlyphs
        language = state.settings.language
    }
}

