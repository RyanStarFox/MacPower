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
        presentWhatsNewIfNeeded()
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
        ReleaseNotesPanel.present(
            title: Localization.string(
                "update.available.title %@",
                language: language,
                AppVersion.display(release.tagName)
            ),
            message: Localization.string(
                "update.available.message %@",
                language: language,
                currentVersion
            ),
            notes: release.notes.text(for: language),
            primary: Localization.string("update.available.open", language: language),
            secondary: Localization.string("update.available.later", language: language),
            alternate: Localization.string("update.available.gitee", language: language),
            onPrimary: { NSWorkspace.shared.open(release.htmlURL) },
            onAlternate: { NSWorkspace.shared.open(UpdateChecker.giteeReleaseURL(tag: release.tagName)) }
        )
    }

    /// Shows this version's notes once after an update, including the first launch
    /// of a build that did not record the previous version.
    private func presentWhatsNewIfNeeded() {
        guard !Self.isRunningTests else { return }
        let current = Self.marketingVersion
        let stored = UserDefaults.standard.string(forKey: Self.whatsNewKey)
        guard ReleaseNotes.shouldPresentWhatsNew(stored: stored, current: current) else { return }
        let notes = ReleaseNotes.current.text(for: settings.language)
        UserDefaults.standard.set(current, forKey: Self.whatsNewKey)
        guard !notes.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.presentWhatsNewAlert(version: current, notes: notes)
        }
    }

    private func presentWhatsNewAlert(version: String, notes: String) {
        let language = settings.language
        ReleaseNotesPanel.present(
            title: Localization.string(
                "update.whatsNew.title %@",
                language: language,
                version
            ),
            notes: notes,
            primary: Localization.string("update.whatsNew.ok", language: language)
        )
    }

    private static let whatsNewKey = "lastLaunchedMarketingVersion"

    func openSettings() {
        // Accessory (menu-bar-only) apps on macOS 15 often create the window but
        // never surface it. Flip to regular briefly so AppKit will key/activate.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            settingsWindow.orderFrontRegardless()
            settingsWindow.styleSettingsChrome()
            NotificationCenter.default.post(name: .macPowerReapplySettingsFrame, object: settingsWindow)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(appState: self))
        // macOS 15 grows this window from intrinsic size but does not shrink it
        // when a shorter tab is selected. SettingsWindowSizer sets the size.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        // SwiftUI lays out under the title bar and pads the title-bar height in by
        // hand, so the safe area cannot move the tabs. The title bar stays opaque:
        // on macOS 27 a transparent one showed its strip black for up to half a
        // second whenever the window grew for a taller tab.
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
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
        // macOS 15 only reserves the title bar once the window is on screen.
        // Re-measure now so the title is not drawn through the tabs on first open.
        window.layoutIfNeeded()
        hosting.view.layoutSubtreeIfNeeded()
        NotificationCenter.default.post(name: .macPowerReapplySettingsFrame, object: window)
        window.styleSettingsChrome()
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
