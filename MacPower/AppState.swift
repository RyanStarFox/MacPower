import AppKit
import CoreServices
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
    var topApps: TopAppList = .measuring
    var lowPowerPreset: LowPowerPreset?
    /// Whether Low Power Mode is on for the power source in use right now.
    var lowPowerNow: Bool?
    var lowPowerBusy = false
    var lowPowerChangeFailed = false
    var localIPInterfaces: [LocalIPInterfaceAddress] = []
    var publicIPv4: String?
    var publicIPv6: String?
    var publicIPv4Failed = false
    var publicIPv6Failed = false
    var bluetoothDevices: [BluetoothSeenDevice] = []
    var bluetoothScanWanted = false {
        didSet { syncBluetoothMonitoring() }
    }
    @ObservationIgnored
    private var armedExternalPower: Bool?
    @ObservationIgnored
    private var reapplyStrategyWhenIdle = false
    var launchAtLoginError: String?
    @ObservationIgnored
    var onLanguageChange: (() -> Void)?
    @ObservationIgnored
    var onPopoverChromeChange: (() -> Void)?
    /// Ring rows gained or lost a cell while the panel is open. The window size is not SwiftUI's frame.
    @ObservationIgnored
    var onPopoverLayoutChange: (() -> Void)?
    @ObservationIgnored
    var onMenuBarNeedsRefresh: (() -> Void)?
    /// First interactive launch shows the menu-bar guide. Login launches stay quiet.
    var showsWelcomeGuide = false
    @ObservationIgnored
    private let launchedAtLogin: Bool

    let telemetry = PowerTelemetryService()
    let metricsService = SystemMetricsService()
    @ObservationIgnored
    private let topAppSampler = TopAppSampler()
    @ObservationIgnored
    private let localIPService = LocalIPService()
    @ObservationIgnored
    private var samplingTopApps = false
    @ObservationIgnored
    private let updateChecker = UpdateChecker()
    @ObservationIgnored
    private var updateCheckLoop: Task<Void, Never>?
    @ObservationIgnored private var bluetoothTask: Task<Void, Never>?

    private var settingsWindow: NSWindow?
    @ObservationIgnored
    private var settingsCloseObserver: NSObjectProtocol?

    init(launchedAtLogin: Bool? = nil) {
        self.launchedAtLogin = launchedAtLogin ?? LoginLaunch.isCurrent()
        telemetry.onChange = { [weak self] snapshot in
            guard let self else { return }
            self.snapshot = snapshot
            self.onMenuBarNeedsRefresh?()
            self.noteExternalPower(snapshot.externalConnected)
        }
        metricsService.onChange = { [weak self] metrics in
            self?.metrics = metrics
        }
        settings.onMenuBarChromeChange = { [weak self] in
            self?.onMenuBarNeedsRefresh?()
        }
        topAppSampler.onChange = { [weak self] list in
            self?.topApps = list
        }
        metricsService.needs = { [weak self] in
            self?.metricNeeds() ?? .init()
        }
        telemetry.wantsPackTemperature = { [weak self] in
            self?.settings.ringOrder.contains(.batteryTemperature) == true
        }
        telemetry.start()
        metricsService.start()
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        startAutomaticUpdateChecks()
        presentStartupUI()
        settings.onTopAppSamplingChange = { [weak self] in
            self?.syncTopAppSampling()
        }
        localIPService.onChange = { [weak self] snapshot in
            guard let self else { return }
            self.localIPInterfaces = snapshot.interfaces
            self.publicIPv4 = snapshot.publicIPv4
            self.publicIPv6 = snapshot.publicIPv6
            self.publicIPv4Failed = snapshot.publicIPv4Failed
            self.publicIPv6Failed = snapshot.publicIPv6Failed
        }
        settings.onLocalIPChange = { [weak self] in
            self?.syncLocalIP(fetchPublic: self?.isPopoverOpen == true)
        }
        settings.onBluetoothDevicesChange = { [weak self] in
            self?.syncBluetoothMonitoring()
        }
        syncTopAppSampling()
        syncLocalIP(fetchPublic: false)
        syncBluetoothMonitoring()
    }

    func setPopoverOpen(_ open: Bool) {
        isPopoverOpen = open
        telemetry.setPopoverOpen(open)
        metricsService.setPopoverOpen(open)
        syncPopoverExtras()
        syncLocalIP(fetchPublic: open)
        if open, !settings.bluetoothRingDevices.isEmpty {
            Task { await self.refreshBluetoothNow() }
        }
    }

    func syncBluetoothMonitoring() {
        let needed = bluetoothScanWanted || !settings.bluetoothRingDevices.isEmpty
        if needed {
            guard bluetoothTask == nil else { return }
            bluetoothTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refreshBluetoothNow()
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                }
            }
        } else {
            bluetoothTask?.cancel()
            bluetoothTask = nil
        }
    }

    func refreshBluetoothNow() async {
        let next = await Task.detached(priority: .utility) {
            BluetoothBatteryReader.load()
        }.value
        bluetoothDevices = next
        settings.refreshBluetoothNames(from: next)
        onPopoverLayoutChange?()
    }

    private func metricNeeds() -> SystemMetricsService.Needs {
        guard settings.showStatusRings else { return .init() }
        let slots = settings.ringOrder
        return SystemMetricsService.Needs(
            cpu: slots.contains(.cpu),
            gpu: slots.contains(.gpu),
            memory: slots.contains(.memory),
            disk: slots.contains(.disk),
            pressure: slots.contains(.memoryPressure),
            swap: slots.contains(.swap),
            network: slots.contains(.download) || slots.contains(.upload) || slots.contains(.speedPair)
        )
    }

    func syncPopoverExtras() {
        syncTopAppSampling()
        if isPopoverOpen, settings.showLowPower, !lowPowerBusy {
            refreshLowPowerReading()
            lowPowerChangeFailed = false
        }
    }

    private func syncLocalIP(fetchPublic: Bool) {
        localIPService.apply(
            enabled: settings.showLocalIP,
            scopes: settings.ipScopes,
            families: settings.ipFamilies,
            fetchPublic: fetchPublic
        )
    }

    private func syncTopAppSampling() {
        topAppSampler.configure(
            interval: TimeInterval(settings.topAppIntervalSeconds),
            window: .seconds(settings.topAppWindowMinutes * 60),
            limit: settings.topAppLimit
        )
        if settings.showTopApps, !samplingTopApps {
            samplingTopApps = true
            topAppSampler.start()
        } else if !settings.showTopApps, samplingTopApps {
            samplingTopApps = false
            topAppSampler.stop()
            topApps = .measuring
        }
    }

    func setLowPowerStrategy(_ preset: LowPowerPreset) {
        guard !lowPowerBusy else { return }
        let previousStrategy = settings.lowPowerStrategy
        let previousNow = lowPowerNow
        let external = snapshot.externalConnected
        let predictedNow = external ? preset.ac : preset.battery
        // Title and the current-mode icon publish together. Busy stays off the view:
        // disabling the row dims it, then a later tick undims it and the block flashes.
        updateLowPowerAppearance {
            lowPowerBusy = true
            if lowPowerChangeFailed { lowPowerChangeFailed = false }
            settings.lowPowerStrategy = preset
            if lowPowerNow != predictedNow { lowPowerNow = predictedNow }
        }
        Task {
            let applied = await LowPowerModeController.apply(preset)
            updateLowPowerAppearance {
                lowPowerBusy = false
                if applied {
                    if lowPowerPreset != preset { lowPowerPreset = preset }
                    if lowPowerNow != predictedNow { lowPowerNow = predictedNow }
                } else {
                    settings.lowPowerStrategy = previousStrategy
                    if lowPowerNow != previousNow { lowPowerNow = previousNow }
                    lowPowerChangeFailed = true
                }
            }
            finishLowPowerChange()
        }
    }

    func toggleLowPowerNow() {
        guard !lowPowerBusy, let lowPowerNow else { return }
        let next = !lowPowerNow
        let external = snapshot.externalConnected
        let armedNow = settings.lowPowerStrategy == nil
        updateLowPowerAppearance {
            lowPowerBusy = true
            if lowPowerChangeFailed { lowPowerChangeFailed = false }
        }
        Task {
            if armedNow {
                if let live = LowPowerModeController.read() {
                    updateLowPowerAppearance {
                        settings.lowPowerStrategy = live
                    }
                } else {
                    updateLowPowerAppearance {
                        lowPowerBusy = false
                        lowPowerChangeFailed = true
                    }
                    finishLowPowerChange()
                    return
                }
            }
            let applied = await LowPowerModeController.applyActive(on: next, externalConnected: external)
            updateLowPowerAppearance {
                lowPowerBusy = false
                if applied {
                    if self.lowPowerNow != next { self.lowPowerNow = next }
                } else {
                    if armedNow { settings.lowPowerStrategy = nil }
                    lowPowerChangeFailed = true
                }
            }
            finishLowPowerChange()
        }
    }

    private func refreshLowPowerReading() {
        guard let preset = LowPowerModeController.read() else {
            lowPowerPreset = settings.lowPowerStrategy
            return
        }
        lowPowerPreset = preset
        lowPowerNow = snapshot.externalConnected ? preset.ac : preset.battery
    }

    private func noteExternalPower(_ external: Bool) {
        guard snapshot.hasBattery else { return }
        let previous = armedExternalPower
        armedExternalPower = external
        guard LowPowerModeController.shouldReapplyStrategy(
            previousExternal: previous,
            external: external,
            hasStrategy: settings.lowPowerStrategy != nil
        ) else { return }
        if lowPowerBusy {
            reapplyStrategyWhenIdle = true
            return
        }
        reapplySavedStrategy(external: external)
    }

    private func reapplySavedStrategy(external: Bool) {
        guard let preset = settings.lowPowerStrategy, !lowPowerBusy else { return }
        let previousNow = lowPowerNow
        let predictedNow = external ? preset.ac : preset.battery
        updateLowPowerAppearance {
            lowPowerBusy = true
            if lowPowerChangeFailed { lowPowerChangeFailed = false }
            if lowPowerNow != predictedNow { lowPowerNow = predictedNow }
        }
        Task {
            let applied = await LowPowerModeController.apply(preset)
            updateLowPowerAppearance {
                lowPowerBusy = false
                if applied {
                    if lowPowerPreset != preset { lowPowerPreset = preset }
                    if lowPowerNow != predictedNow { lowPowerNow = predictedNow }
                } else {
                    if lowPowerNow != previousNow { lowPowerNow = previousNow }
                    lowPowerChangeFailed = true
                }
            }
            finishLowPowerChange()
        }
    }

    /// Popover updates from a low-power write should not fade. The busy flag is
    /// only a re-entry guard; the section does not observe it.
    private func updateLowPowerAppearance(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction, updates)
    }

    private func finishLowPowerChange() {
        guard !lowPowerBusy, reapplyStrategyWhenIdle else { return }
        reapplyStrategyWhenIdle = false
        reapplySavedStrategy(external: snapshot.externalConnected)
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

    var isCheckingForUpdates = false

    func setAutomaticUpdateChecking(_ enabled: Bool, checkNow: Bool) {
        settings.automaticallyCheckForUpdates = enabled
        if enabled {
            startUpdateCheckLoop()
            if checkNow {
                checkForUpdates(reason: .userEnabled)
            }
        } else {
            stopAutomaticUpdateChecks()
        }
    }

    func checkForUpdates(reason: UpdateCheckReason) {
        guard !Self.isRunningTests else { return }
        if reason == .manual, isCheckingForUpdates { return }
        let enabled = settings.automaticallyCheckForUpdates
        let version = Self.marketingVersion
        let language = settings.language
        if reason == .manual {
            isCheckingForUpdates = true
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await updateChecker.checkIfNeeded(
                enabled: enabled,
                reason: reason,
                currentVersion: version
            )
            if reason == .manual {
                isCheckingForUpdates = false
            }
            switch result {
            case .skipped:
                return
            case .failed(let failure):
                if reason == .manual {
                    presentCheckNotice(
                        title: Localization.string("update.check.failed", language: language),
                        message: failure.message(language: language),
                        language: language
                    )
                }
            case .current:
                if reason == .manual {
                    presentCheckNotice(
                        title: Localization.string("update.upToDate.title", language: language),
                        message: Localization.string(
                            "update.upToDate.message %@",
                            language: language,
                            version
                        ),
                        language: language
                    )
                }
            case .available(let release):
                if reason != .manual {
                    let deferred = UserDefaults.standard.string(forKey: Self.deferredUpdateKey)
                    guard UpdateCheckPolicy.shouldPresentUpdate(latest: release.tagName, deferred: deferred) else { return }
                }
                presentUpdateAlert(release: release, currentVersion: version, language: language)
            }
        }
    }

    func startAutomaticUpdateChecks() {
        if !launchedAtLogin {
            checkForUpdates(reason: .launch)
        }
        startUpdateCheckLoop()
    }

    private func startUpdateCheckLoop() {
        updateCheckLoop?.cancel()
        updateCheckLoop = Task { [weak self] in
            while !Task.isCancelled {
                let next = UpdateCheckPolicy.nextHourlyCheck(after: Date())
                let delay = max(1, next.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(delay))
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
        let install = release.updateOffer.map { offer in
            UpdateInstallController(
                offer: offer,
                text: UpdateInstallText(
                    update: Localization.string("update.install.now", language: language),
                    downloadingGitHub: Localization.string("update.install.downloading.github", language: language),
                    downloadingGitee: Localization.string("update.install.downloading.gitee", language: language),
                    installing: Localization.string("update.install.installing", language: language),
                    failed: Localization.string("update.install.failed", language: language)
                )
            )
        }
        let messageKey = install == nil ? "update.available.message %@" : "update.available.installed %@"
        ReleaseNotesPanel.present(
            title: Localization.string(
                "update.available.title %@",
                language: language,
                AppVersion.display(release.tagName)
            ),
            message: Localization.string(messageKey, language: language, currentVersion),
            notes: release.notes.text(for: language),
            primary: Localization.string("update.available.open", language: language),
            secondary: Localization.string("update.available.later", language: language),
            alternate: Localization.string("update.available.gitee", language: language),
            onPrimary: { NSWorkspace.shared.open(release.htmlURL) },
            onAlternate: { NSWorkspace.shared.open(UpdateChecker.giteeReleaseURL(tag: release.tagName)) },
            onLater: { UserDefaults.standard.set(release.tagName, forKey: Self.deferredUpdateKey) },
            install: install,
            automaticTitle: Localization.string("settings.updates.automatic", language: language),
            automaticOn: settings.automaticallyCheckForUpdates,
            onAutomatic: { [weak self] enabled in
                self?.setAutomaticUpdateChecking(enabled, checkNow: false)
            }
        )
    }

    private func presentCheckNotice(title: String, message: String?, language: AppLanguage) {
        ReleaseNotesPanel.present(
            title: title,
            message: message,
            notes: "",
            primary: Localization.string("update.whatsNew.ok", language: language)
        )
    }

    /// Login starts with no window. The first time someone opens the app, settings
    /// comes up with the menu-bar guide. Later launches only show update notes.
    private func presentStartupUI() {
        guard !Self.isRunningTests else { return }
        if launchedAtLogin {
            UserDefaults.standard.set(Self.marketingVersion, forKey: Self.whatsNewKey)
            return
        }
        if !UserDefaults.standard.bool(forKey: Self.welcomeKey) {
            UserDefaults.standard.set(Self.marketingVersion, forKey: Self.whatsNewKey)
            showsWelcomeGuide = true
            DispatchQueue.main.async { [weak self] in
                self?.openSettings()
            }
            return
        }
        presentWhatsNewIfNeeded()
    }

    func completeWelcomeGuide() {
        showsWelcomeGuide = false
        UserDefaults.standard.set(true, forKey: Self.welcomeKey)
    }

    func openMenuBarSettings() {
        NSWorkspace.shared.open(LoginLaunch.menuBarSettingsURL)
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
    private static let welcomeKey = "didCompleteWelcomeGuide"
    private static let deferredUpdateKey = "deferredUpdateTag"

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
        window.setContentSize(NSSize(width: SettingsColumn.width, height: SettingsColumn.preferredHeight))
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

/// `kAEOpenApplication` carries `keyAELaunchedAsLogInItem` when login starts the app.
enum LoginLaunch {
    static let menuBarSettingsURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!

    static func isCurrent() -> Bool {
        isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
    }

    static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event else { return false }
        guard event.eventID == kAEOpenApplication else { return false }
        if meansYes(event.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem)) {
            return true
        }
        let nested = event.paramDescriptor(forKeyword: keyAEPropData)?
            .paramDescriptor(forKeyword: keyAELaunchedAsLogInItem)
        return meansYes(nested)
    }

    private static func meansYes(_ descriptor: NSAppleEventDescriptor?) -> Bool {
        guard let descriptor else { return false }
        switch descriptor.descriptorType {
        case typeTrue:
            return true
        case typeFalse:
            return false
        case typeBoolean:
            return descriptor.booleanValue
        case typeEnumerated, typeSInt16, typeSInt32, typeUInt32:
            return descriptor.int32Value == Int32(bitPattern: UInt32(kAEYes))
        default:
            return descriptor.booleanValue
        }
    }
}
