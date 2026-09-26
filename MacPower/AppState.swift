import AppKit
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class AppState {
    var snapshot: PowerSnapshot = .empty
    var metrics: SystemSnapshot = .empty
    var settings = AppSettings()
    var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    var isPopoverOpen = false
    var launchAtLoginError: String?
    @ObservationIgnored
    var onLanguageChange: (() -> Void)?
    @ObservationIgnored
    var onPopoverChromeChange: (() -> Void)?
    @ObservationIgnored
    var onMenuBarNeedsRefresh: (() -> Void)?

    let telemetry = PowerTelemetryService()
    let metricsService = SystemMetricsService()
    @ObservationIgnored
    private let updateChecker = UpdateChecker()
    @ObservationIgnored
    private var updateCheckLoop: Task<Void, Never>?

    private var settingsWindow: NSWindow?
    @ObservationIgnored
    private var settingsCloseObserver: NSObjectProtocol?

    init() {
        telemetry.onChange = { [weak self] snapshot in
            self?.snapshot = snapshot
            self?.onMenuBarNeedsRefresh?()
        }
        metricsService.onChange = { [weak self] metrics in
            self?.metrics = metrics
        }
        settings.onMenuBarChromeChange = { [weak self] in
            self?.onMenuBarNeedsRefresh?()
        }
        telemetry.start()
        metricsService.start()
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        startAutomaticUpdateChecks()
    }

    func setPopoverOpen(_ open: Bool) {
        isPopoverOpen = open
        telemetry.setPopoverOpen(open)
        metricsService.setPopoverOpen(open)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }

    func checkForUpdates(reason: UpdateCheckReason) {
        guard !Self.isRunningTests else { return }
        let enabled = settings.automaticallyCheckForUpdates
        let version = Self.marketingVersion
        let language = settings.language
        Task { [weak self] in
            guard let self else { return }
            guard let release = await updateChecker.checkIfNeeded(
                enabled: enabled,
                reason: reason,
                currentVersion: version
            ) else { return }
            presentUpdateAlert(release: release, currentVersion: version, language: language)
        }
    }

    func startAutomaticUpdateChecks() {
        checkForUpdates(reason: .launch)
        updateCheckLoop?.cancel()
        updateCheckLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(UpdateCheckPolicy.interval))
                guard !Task.isCancelled else { return }
                self?.checkForUpdates(reason: .periodic)
            }
        }
    }

    func stopAutomaticUpdateChecks() {
        updateCheckLoop?.cancel()
        updateCheckLoop = nil
    }

    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private func presentUpdateAlert(
        release: GitHubLatestRelease,
        currentVersion: String,
        language: AppLanguage
    ) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = Localization.string(
            "update.available.title %@",
            language: language,
            AppVersion.display(release.tagName)
        )
        alert.informativeText = Localization.string(
            "update.available.message %@",
            language: language,
            currentVersion
        )
        alert.addButton(withTitle: Localization.string("update.available.open", language: language))
        alert.addButton(withTitle: Localization.string("update.available.later", language: language))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    func openSettings() {
        // Accessory (menu-bar-only) apps on macOS 15 often create the window but
        // never surface it. Flip to regular briefly so AppKit will key/activate.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            settingsWindow.orderFrontRegardless()
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(appState: self))
        // macOS 15 grows this window from intrinsic size but does not shrink it
        // when a shorter tab is selected. SettingsWindowSizer sets the size.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        // Content starts below the title bar. fullSizeContentView let the title-bar
        // material tint the tab row (a mismatched band on macOS 26+) and made
        // SwiftUI's top safe area jump between panes on macOS 15.
        window.styleMask = [.titled, .closable]
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .windowBackgroundColor
        window.title = Localization.string("settings.title", language: settings.language)
        window.isReleasedWhenClosed = false

        // Sequoia lays out hosting controllers lazily. Give the view a real size
        // so it can measure, then let SettingsWindowSizer replace it before show.
        // A flexible root reports the proposed height from sizeThatFits, which
        // would open the window far too tall.
        window.setContentSize(NSSize(width: 440, height: 360))
        if #available(macOS 15.0, *) {
            window.updateConstraintsIfNeeded()
        }
        window.layoutIfNeeded()
        hosting.view.layoutSubtreeIfNeeded()
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        settingsWindow = window
        observeSettingsWindowClose(window)
    }

    private func observeSettingsWindowClose(_ window: NSWindow) {
        if let settingsCloseObserver {
            NotificationCenter.default.removeObserver(settingsCloseObserver)
        }
        settingsCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSettingsWindowClosed()
            }
        }
    }

    private func handleSettingsWindowClosed() {
        // Return to menu-bar-only once settings is gone.
        NSApp.setActivationPolicy(.accessory)
    }

    func refreshLocalizedChrome() {
        settingsWindow?.title = Localization.string("settings.title", language: settings.language)
        onLanguageChange?()
    }

    func menuBarFill(appearance: NSAppearance) -> MenuBarResolvedFill {
        settings.menuBarTint.fill(
            percent: snapshot.percent,
            flowMode: snapshot.flowMode,
            appearance: appearance
        )
    }
}
