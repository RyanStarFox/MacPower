import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var hosting: NSHostingController<PopoverRootView>
    private var defaultArrowHeight: CGFloat?
    private var appearanceObservation: NSKeyValueObservation?
    private var themeChangeObserver: NSObjectProtocol?
    private var lastRenderedKey: MenuBarIconKey?
    private var lastAppearanceName: NSAppearance.Name?
    private var lastTitle: String?
    private var lastTooltip: String?
    private var isRefreshingIcon = false

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
        hosting.sizingOptions = []
        popover.contentViewController = hosting
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

        refreshIcon(force: true)
    }

    func applyLocalization() {
        let replacement = NSHostingController(rootView: PopoverRootView(appState: appState))
        replacement.sizingOptions = []
        popover.contentViewController = replacement
        hosting = replacement
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
        let image = MenuBarBatteryRenderer.image(
            snapshot: appState.snapshot,
            style: appState.settings.iconStyle,
            fill: fill,
            appearance: appearance,
            showChargeGlyphs: appState.settings.showChargeGlyphs
        )
        image.isTemplate = fill.isTemplate
        button.image = image

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
        if isRightClick, appState.settings.menuBarRightClickAction == .statusMenu {
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
        appState.setPopoverOpen(true)
        setStatusItemHighlighted(true)
        // Re-assign so SwiftUI builds the open layout before we measure; Observation
        // alone can defer the swap past the first sizeThatFits on macOS 15.
        hosting.rootView = PopoverRootView(appState: appState)
        applyAnchorPreference()
        applyArrowHeight(hidden: !appState.settings.showPopoverArrow)
        syncPopoverContentSize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        hugMenuBarIfArrowHidden()
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            setStatusItemHighlighted(false)
            popover.performClose(nil)
        }

        let menu = NSMenu()
        let quitTitle = Localization.string("settings.quit", language: appState.settings.language)
        let quitItem = NSMenuItem(
            title: quitTitle,
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        } else {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        }
    }

    @objc
    private func quitApp(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    func popoverDidShow(_ notification: Notification) {
        if !appState.isPopoverOpen {
            appState.setPopoverOpen(true)
            hosting.rootView = PopoverRootView(appState: appState)
            syncPopoverContentSize()
        }
        setStatusItemHighlighted(true)
        hugMenuBarIfArrowHidden()
    }

    private var popoverWidth: CGFloat {
        guard appState.settings.showStatusRings else { return PopoverLayout.width }
        return PopoverLayout.width(ringCount: appState.settings.ringOrder.count, twoRows: appState.settings.twoRingRows)
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
        let size = NSSize(width: width, height: max(ceil(fitted.height), 1))
        // Animating this resize is what slides the rings from the previous
        // pitch into the final grid. The popover can still fade in.
        let animates = popover.animates
        popover.animates = false
        popover.contentSize = size
        popover.animates = animates
        hosting.view.layoutSubtreeIfNeeded()
    }

    func popoverDidClose(_ notification: Notification) {
        setStatusItemHighlighted(false)
        appState.setPopoverOpen(false)
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
        window.setFrame(window.frame.offsetBy(dx: 0, dy: delta), display: true)
    }
}
