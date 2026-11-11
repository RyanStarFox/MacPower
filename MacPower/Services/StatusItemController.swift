import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate, NSMenuDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var hosting: NSHostingController<PopoverRootView>
    private var defaultArrowHeight: CGFloat?
    private var appearanceObservation: NSKeyValueObservation?
    private var themeChangeObserver: NSObjectProtocol?
    private var powerStateObserver: NSObjectProtocol?
    private var scrollObserver: NSObjectProtocol?
    /// Clip-view origin from the last time the panel was scrolled. `NSClipView` is flipped, so 0 is the top.
    private var savedScrollOffset: CGFloat = 0
    private var isAdjustingScroll = false
    private var lastRenderedKey: MenuBarIconKey?
    private var lastAppearanceName: NSAppearance.Name?
    private var lastTitle: String?
    private var lastTooltip: String?
    private var isRefreshingIcon = false
    private var isShowingStatusMenu = false
    /// Colored charge sits above template chrome so the empty frame still tracks the menu bar.
    private var chargeOverlay: PassthroughImageView?
    /// Clicks outside a menu-bar popover never reach this accessory app, so
    /// `.transient` alone leaves the panel up until the status item is clicked again.
    private var outsideClickMonitors: [Any] = []
    /// Holds the SwiftUI panel so a taller-than-screen layout can scroll
    /// instead of extending past the Dock.
    private let contentScrollView: NSScrollView = {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.horizontalScrollElasticity = .none
        scroll.usesPredominantAxisScrolling = true
        return scroll
    }()

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hosting = NSHostingController(rootView: PopoverRootView(appState: appState))
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        // Empty options: we set `popover.contentSize` ourselves before each show.
        // Relying on intrinsicContentSize alone left Sequoia with a too-narrow
        // frame, and SwiftUI then centered/clipped the 420pt panel on both sides.
        configureHosting(hosting)
        contentScrollView.contentView.drawsBackground = false
        contentScrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentScrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rememberScrollOffset()
            }
        }
        installHosting(hosting)
        popover.contentSize = NSSize(width: popoverWidth, height: 1)
        applyAnchorPreference()

        if let button = statusItem.button {
            button.imagePosition = .imageLeft
            button.target = self
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            configureHighlightAppearance(for: button)
            // Observe the app appearance — not the button's. Button
            // effectiveAppearance churns while AppKit redraws Liquid Glass
            // replicants, which previously re-entered refreshIcon in a loop.
            appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refreshIcon(force: false)
                }
            }
            themeChangeObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshIcon(force: true)
                }
            }
        }

        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: ProcessInfo.processInfo,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.appState.lowPowerNow != nil, !self.appState.lowPowerBusy {
                    self.appState.lowPowerNow = ProcessInfo.processInfo.isLowPowerModeEnabled
                }
                self.refreshIcon()
            }
        }
        refreshIcon(force: true)
    }

    func applyLocalization() {
        let replacement = NSHostingController(rootView: PopoverRootView(appState: appState))
        configureHosting(replacement)
        hosting = replacement
        installHosting(replacement)
        if popover.isShown {
            syncPopoverContentSize()
        } else {
            popover.contentSize = NSSize(width: popoverWidth, height: 1)
        }
        refreshIcon(force: true)
    }

    func applyArrowVisibility() {
        applyAnchorPreference()
        guard popover.isShown, let button = statusItem.button else { return }
        applyArrowHeight(hidden: !appState.settings.showPopoverArrow)
        // Remeasure before re-show so width stays locked at PopoverLayout.width.
        syncPopoverContentSize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        hugMenuBarIfArrowHidden()
    }

    private func applyAnchorPreference() {
        let hide = !appState.settings.showPopoverArrow
        if popover.responds(to: NSSelectorFromString("setShouldHideAnchor:")) {
            popover.setValue(hide, forKey: "shouldHideAnchor")
        }
    }

    func refreshIcon() {
        refreshIcon(force: false)
    }

    func refreshIcon(force: Bool) {
        guard let button = statusItem.button else { return }
        guard !isRefreshingIcon else { return }
        let appearance = button.effectiveAppearance
        let key = MenuBarIconKey(appState)
        let appearanceName = appearance.name
        if !force,
           key == lastRenderedKey,
           appearanceName == lastAppearanceName {
            return
        }

        isRefreshingIcon = true
        defer { isRefreshingIcon = false }

        let fill = appState.menuBarFill(appearance: appearance)
        let content = MenuBarBatteryRenderer.statusItemContent(
            snapshot: appState.snapshot,
            style: appState.settings.iconStyle,
            fill: fill,
            appearance: appearance,
            showChargeGlyphs: appState.settings.showChargeGlyphs
        )
        button.image = content.chrome

        let title: String
        if appState.settings.digitPlacement == .beside {
            title = " \(Int(appState.snapshot.percent.rounded()))%"
        } else {
            title = ""
        }
        if title != lastTitle {
            button.title = title
            lastTitle = title
        }

        syncChargeOverlay(on: button, charge: content.charge)

        let tip = tooltip
        if tip != lastTooltip {
            button.toolTip = tip
            lastTooltip = tip
        }

        lastRenderedKey = key
        lastAppearanceName = appearanceName
    }

    private var tooltip: String {
        let percent = Int(appState.snapshot.percent.rounded())
        return Localization.string("battery.percent %lld", language: appState.settings.language, Int64(percent))
    }

    @objc
    private func handleStatusItemClick(_ sender: Any?) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick {
            guard !isShowingStatusMenu else { return }
            showStatusMenu()
            return
        }
        togglePopover(sender)
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            setStatusItemHighlighted(false)
            popover.performClose(sender)
            return
        }
        // Build the open layout without motion so the rings do not slide up.
        // `show` itself must run after that transaction: disabling Core Animation
        // actions around `show` drops the popover window and the panel never appears.
        performWithoutMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                appState.setPopoverOpen(true)
                // Re-assign so SwiftUI builds the open layout before we measure.
                // Observation alone can defer the swap past the first sizeThatFits.
                hosting.rootView = PopoverRootView(appState: appState)
            }
            setStatusItemHighlighted(true)
            applyAnchorPreference()
            applyArrowHeight(hidden: !appState.settings.showPopoverArrow)
            syncPopoverContentSize()
        }
        popover.animates = false
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        hugMenuBarIfArrowHidden()
        hosting.view.layoutSubtreeIfNeeded()
        restoreScrollFromCurrentFrames()
        popover.contentViewController?.view.window?.makeKey()
        startOutsideClickMonitoring()
        DispatchQueue.main.async { [weak self] in
            self?.restoreScrollFromCurrentFrames()
        }
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.closePopoverIfClickIsOutside()
            return event
        }) {
            outsideClickMonitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            Task { @MainActor in
                self?.closePopoverIfClickIsOutside()
            }
        }) {
            outsideClickMonitors.append(monitor)
        }
    }

    private func stopOutsideClickMonitoring() {
        for monitor in outsideClickMonitors {
            NSEvent.removeMonitor(monitor)
        }
        outsideClickMonitors.removeAll()
    }

    /// Leave clicks on the panel and the status item alone. The status item's own action toggles the panel.
    private func closePopoverIfClickIsOutside() {
        guard popover.isShown else { return }
        let mouse = NSEvent.mouseLocation
        if let window = popover.contentViewController?.view.window, window.frame.contains(mouse) {
            return
        }
        if let button = statusItem.button, let window = button.window {
            let local = button.convert(window.convertPoint(fromScreen: mouse), from: nil)
            if button.bounds.contains(local) { return }
        }
        popover.performClose(nil)
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            setStatusItemHighlighted(false)
            popover.performClose(nil)
        }

        let menu = NSMenu()
        let language = appState.settings.language
        let settingsItem = NSMenuItem(
            title: Localization.string("menu.openSettings", language: language),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quitItem = NSMenuItem(
            title: Localization.string("settings.quit", language: language),
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)
        menu.delegate = self
        // A context menu popped from the status button picks up the icon's
        // drawing appearance, so the labels stay white on a light menu bar.
        // Assigning the menu to the status item makes AppKit use the menu bar's
        // light or dark appearance instead.
        isShowingStatusMenu = true
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
        isShowingStatusMenu = false
    }

    @objc
    private func openSettingsFromMenu(_ sender: Any?) {
        appState.openSettings()
    }

    @objc
    private func quitApp(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    func menuDidClose(_ menu: NSMenu) {
        if statusItem.menu === menu {
            statusItem.menu = nil
        }
        isShowingStatusMenu = false
    }

    func popoverDidShow(_ notification: Notification) {
        if !appState.isPopoverOpen {
            appState.setPopoverOpen(true)
            hosting.rootView = PopoverRootView(appState: appState)
            syncPopoverContentSize()
        }
        setStatusItemHighlighted(true)
        hugMenuBarIfArrowHidden()
        startOutsideClickMonitoring()
    }

    private var popoverWidth: CGFloat {
        guard appState.settings.showStatusRings,
              appState.settings.displayedRingRows(seen: appState.bluetoothDevices).contains(where: { !$0.isEmpty })
        else { return PopoverLayout.width }
        let settings = appState.settings
        let includesSettings = settings.settingsButtonPlacement.drawsRingGear(
            host: settings.settingsButtonHost,
            ringsVisible: true
        )
        var counts = settings.displayedRingRows(seen: appState.bluetoothDevices).map(\.count)
        if includesSettings {
            if counts.isEmpty { counts = [1] } else { counts[counts.count - 1] += 1 }
        }
        guard counts.contains(where: { $0 > 0 }) else { return PopoverLayout.width }
        return PopoverLayout.width(rowCounts: counts)
    }

    /// A hidden Bluetooth ring changes the SwiftUI width immediately. The popover window only follows when we set `contentSize` again.
    func adoptPopoverLayoutIfNeeded() {
        guard popover.isShown else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.popover.isShown else { return }
            let width = self.popoverWidth
            let fitted = self.hosting.sizeThatFits(
                in: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            )
            let visibleHeight = min(max(ceil(fitted.height), 1), self.maximumPopoverHeight())
            let sameWidth = abs(self.popover.contentSize.width - width) < 0.5
            let sameHeight = abs(self.popover.contentSize.height - visibleHeight) < 0.5
            guard !sameWidth || !sameHeight else { return }
            self.syncPopoverContentSize()
            self.hugMenuBarIfArrowHidden()
        }
    }

    /// Lock width to the SwiftUI design width and take height from the hosting view.
    /// Must run while the open content graph is mounted, ideally before `show`.
    private func syncPopoverContentSize() {
        if #available(macOS 15.0, *) {
            hosting.view.window?.updateConstraintsIfNeeded()
        }
        hosting.view.layoutSubtreeIfNeeded()
        let width = popoverWidth
        let fitted = hosting.sizeThatFits(
            in: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        let contentHeight = max(ceil(fitted.height), 1)
        let visibleHeight = min(contentHeight, maximumPopoverHeight())
        let scrolls = contentHeight > visibleHeight + 0.5
        hosting.view.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)
        contentScrollView.hasVerticalScroller = scrolls
        contentScrollView.verticalScrollElasticity = scrolls ? .automatic : .none
        let size = NSSize(width: width, height: visibleHeight)
        // Animating this resize slides the ring block up from the previous
        // (often shorter) frame. Keep the popover's own fade for show/close,
        // but commit this size with motion disabled, then lay out before any
        // later caller turns animation back on.
        let animates = popover.animates
        popover.animates = false
        isAdjustingScroll = true
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        popover.contentSize = size
        contentScrollView.layoutSubtreeIfNeeded()
        restoreScroll(documentHeight: contentHeight, visibleHeight: visibleHeight)
        NSAnimationContext.endGrouping()
        isAdjustingScroll = false
        popover.animates = animates
    }

    private func installHosting(_ hosting: NSHostingController<PopoverRootView>) {
        hosting.view.translatesAutoresizingMaskIntoConstraints = true
        contentScrollView.documentView = hosting.view
        guard popover.contentViewController?.view !== contentScrollView else { return }
        let controller = NSViewController()
        controller.view = contentScrollView
        popover.contentViewController = controller
    }

    /// Room under the menu bar and above the Dock. The arrow, when shown, sits outside the content.
    private func maximumPopoverHeight() -> CGFloat {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame.height ?? 800
        let arrow: CGFloat = appState.settings.showPopoverArrow ? (defaultArrowHeight ?? 13) : 0
        return max(280, visible - arrow - 10)
    }

    private func rememberScrollOffset() {
        guard !isAdjustingScroll else { return }
        let clip = contentScrollView.contentView
        let documentHeight = contentScrollView.documentView?.frame.height ?? 0
        guard documentHeight > clip.bounds.height + 0.5 else { return }
        savedScrollOffset = clip.bounds.origin.y
    }

    private func restoreScrollFromCurrentFrames() {
        let documentHeight = contentScrollView.documentView?.frame.height ?? 0
        let visibleHeight = contentScrollView.contentView.bounds.height
        guard documentHeight > 1, visibleHeight > 1 else { return }
        isAdjustingScroll = true
        restoreScroll(documentHeight: documentHeight, visibleHeight: visibleHeight)
        isAdjustingScroll = false
    }

    private func restoreScroll(documentHeight: CGFloat, visibleHeight: CGFloat) {
        let clip = contentScrollView.contentView
        let maxOffset = max(0, documentHeight - visibleHeight)
        clip.scroll(to: NSPoint(x: 0, y: min(max(0, savedScrollOffset), maxOffset)))
        contentScrollView.reflectScrolledClipView(clip)
    }

    private func configureHosting(_ hosting: NSHostingController<PopoverRootView>) {
        hosting.sizingOptions = []
    }

    /// Content size, show, and the menu-bar hug all change the window frame.
    /// Any one of them, inside the popover's implicit animation, moves the rings.
    /// `animates` stays off until the next turn so a show() scheduled after this
    /// call returns cannot pick the flag back up and slide the ring block.
    private func performWithoutMotion(_ work: () -> Void) {
        popover.animates = false
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        work()
        CATransaction.commit()
        NSAnimationContext.endGrouping()
        DispatchQueue.main.async { [weak self] in
            self?.popover.animates = true
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
        rememberScrollOffset()
        setStatusItemHighlighted(false)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            appState.setPopoverOpen(false)
        }
    }

    /// macOS 27 draws the selected menu-bar item with its native Liquid Glass
    /// treatment. Earlier systems retain the same interaction through a subtle,
    /// appearance-aware capsule rather than relying on private AppKit chrome.
    private func setStatusItemHighlighted(_ highlighted: Bool) {
        guard let button = statusItem.button else { return }

        if #available(macOS 27, *) {
            button.isHighlighted = highlighted
            return
        }

        // Keep AppKit's press highlight from competing with the persistent
        // fallback shown while the popover is open.
        button.isHighlighted = false
        configureHighlightAppearance(for: button)
        guard let layer = button.layer else { return }

        let previousColor = layer.backgroundColor
        let nextColor = highlighted ? legacyHighlightColor(for: button).cgColor : nil
        layer.backgroundColor = nextColor

        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = previousColor
        animation.toValue = nextColor
        animation.duration = highlighted ? 0.16 : 0.12
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "macPowerStatusItemHighlight")
    }

    private func configureHighlightAppearance(for button: NSStatusBarButton) {
        guard #unavailable(macOS 27) else { return }
        button.wantsLayer = true
        button.layer?.cornerRadius = button.bounds.height / 2
        button.layer?.masksToBounds = true
    }

    private func syncChargeOverlay(on button: NSStatusBarButton, charge: NSImage?) {
        guard let charge else {
            chargeOverlay?.isHidden = true
            chargeOverlay?.image = nil
            return
        }
        let overlay = chargeOverlay ?? {
            let view = PassthroughImageView()
            view.imageScaling = .scaleNone
            view.wantsLayer = true
            button.addSubview(view)
            chargeOverlay = view
            return view
        }()
        overlay.image = charge
        overlay.isHidden = false
        button.layoutSubtreeIfNeeded()
        let size = charge.size
        if let cell = button.cell as? NSButtonCell {
            let imageRect = cell.imageRect(forBounds: button.bounds)
            if imageRect.width > 0, imageRect.height > 0 {
                overlay.frame = imageRect
                return
            }
        }
        overlay.frame = NSRect(
            x: ((button.bounds.width - size.width) / 2).rounded(.towardZero),
            y: ((button.bounds.height - size.height) / 2).rounded(.towardZero),
            width: size.width,
            height: size.height
        )
    }

    private func legacyHighlightColor(for button: NSStatusBarButton) -> NSColor {
        var color = NSColor.selectedContentBackgroundColor
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.selectedContentBackgroundColor
        }
        return color.withAlphaComponent(0.18)
    }

    private func applyArrowHeight(hidden: Bool) {
        cacheDefaultArrowHeightIfNeeded(on: popover)
        let height: CGFloat = hidden ? 0 : (defaultArrowHeight ?? 13)
        setArrowHeight(height, on: popover)
        if let window = popover.contentViewController?.view.window {
            cacheDefaultArrowHeightIfNeeded(on: window)
            setArrowHeight(height, on: window)
        }
    }

    private func cacheDefaultArrowHeightIfNeeded(on object: NSObject) {
        guard defaultArrowHeight == nil else { return }
        guard object.responds(to: NSSelectorFromString("arrowHeight")) else { return }
        guard let height = object.value(forKey: "arrowHeight") as? CGFloat, height > 0 else { return }
        defaultArrowHeight = height
    }

    private func setArrowHeight(_ height: CGFloat, on object: NSObject) {
        guard object.responds(to: NSSelectorFromString("setArrowHeight:")) else { return }
        object.setValue(height, forKey: "arrowHeight")
    }

    /// `shouldHideAnchor` only skips drawing the triangle; AppKit still reserves its slot.
    /// Pull the panel up so its content sits against the menu-bar underside.
    private func hugMenuBarIfArrowHidden() {
        guard !appState.settings.showPopoverArrow else { return }
        applyArrowHeight(hidden: true)
        guard let content = popover.contentViewController?.view,
              let window = content.window else { return }
        let screen = window.screen
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }

        let contentOnScreen = window.convertToScreen(content.convert(content.bounds, to: nil))
        let delta = screen.visibleFrame.maxY - contentOnScreen.maxY
        guard delta > 0.5 else { return }
        window.setFrame(window.frame.offsetBy(dx: 0, dy: delta), display: true, animate: false)
    }
}

/// Lets clicks fall through to the status-item button.
private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
