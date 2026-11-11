import AppKit
import ServiceManagement
import SwiftUI

extension Notification.Name {
    /// Posted after the settings window is on screen, so the title-bar inset
    /// can be applied before the first paint. macOS 15 reports a content rect
    /// with no title bar until then, which draws the title through the tabs.
    static let macPowerReapplySettingsFrame = Notification.Name("MacPowerReapplySettingsFrame")
}

/// Sidebar plus a wider detail column. The window keeps this size and the detail scrolls.
enum SettingsColumn {
    /// System Settings' sidebar width on macOS 26.
    static let sidebarWidth: CGFloat = 246
    static let contentWidth: CGFloat = 520
    static let width: CGFloat = sidebarWidth + contentWidth
    static let preferredHeight: CGFloat = 680
}

/// Sidebar and title-strip measurements, taken from macOS 26 System Settings
/// so the settings window reads like the system's own.
enum SettingsChrome {
    /// The unified-toolbar strip that holds the traffic lights and the page title.
    static let stripHeight: CGFloat = 52
    static let titleSize: CGFloat = 15
    /// Lines the title up with the left edge of the grouped form below it.
    static let titleLeading: CGFloat = 20

    static let rowHeight: CGFloat = 40
    /// Space between the sidebar edges and the selection highlight.
    static let rowInset: CGFloat = 10
    /// Space between the selection highlight's left edge and the icon.
    static let rowPadding: CGFloat = 7
    static let selectionRadius: CGFloat = 10
    static let iconSize: CGFloat = 26
    static let iconLabelSpacing: CGFloat = 6
    static let labelSize: CGFloat = 15
    /// Extra space between sidebar groups.
    static let groupGap: CGFloat = 13
}

/// macOS 15's hosting controller grows this window but will not shrink it when a
/// shorter tab is shown. Apply the measured height with the title bar held still.
private final class SettingsSizerView: NSView {
    private var applying = false
    private var reapplyObserver: NSObjectProtocol?

    var height: CGFloat = 0 {
        didSet {
            guard height != oldValue else { return }
            apply()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let reapplyObserver {
            NotificationCenter.default.removeObserver(reapplyObserver)
            self.reapplyObserver = nil
        }
        if let window {
            reapplyObserver = NotificationCenter.default.addObserver(
                forName: .macPowerReapplySettingsFrame,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.apply()
            }
        }
        apply()
        // Title-bar metrics can land a turn after the window is ordered front.
        Task { @MainActor [weak self] in
            self?.apply()
        }
    }

    /// Runs inside SwiftUI's layout pass, so the new frame and the new content
    /// reach the screen in the same commit. Resizing a turn later shows the
    /// grown area blank until the content catches up.
    private func apply() {
        guard !applying, height > 80, let window else { return }
        defer { window.styleSettingsChrome() }
        let scale = window.backingScaleFactor
        let snap = { (value: CGFloat) -> CGFloat in
            (value * scale).rounded() / scale
        }
        // The content view fills the whole window (title strip included), so
        // the measured height is the frame height. Never let that frame leave
        // the visible screen: a height past the display pushes the title bar
        // off the top and the window looks like it closed.
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let limit = visible?.height ?? height
        let targetHeight = min(max(snap(height), 80), snap(limit))
        let top = snap(window.frame.maxY)
        var frame = NSRect(
            x: snap(window.frame.minX),
            y: top - targetHeight,
            width: SettingsColumn.width,
            height: targetHeight
        )
        if let visible {
            frame.size.height = min(frame.height, visible.height)
            frame.origin.y = min(frame.origin.y, visible.maxY - frame.height)
            frame.origin.y = max(frame.origin.y, visible.minY)
        }
        let unchanged = abs(window.frame.width - frame.width) < 0.5
            && abs(window.frame.height - frame.height) < 0.5
            && abs(window.frame.origin.x - frame.origin.x) < 0.5
            && abs(window.frame.origin.y - frame.origin.y) < 0.5
        guard !unchanged else { return }
        applying = true
        defer { applying = false }
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        window.setFrame(frame, display: true, animate: false)
        NSAnimationContext.endGrouping()
    }
}

/// Observers holding the title bar's tint layers plain, keyed by layer.
@MainActor private var titlebarTintPins: [ObjectIdentifier: [NSKeyValueObservation]] = [:]

private func makePlain(_ layer: CALayer) {
    guard layer.opacity != 1 || layer.filters?.isEmpty == false else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = 1
    layer.filters = nil
    CATransaction.commit()
}

extension NSWindow {
    /// The settings content paints a solid background, so the window's background
    /// material and the title bar's blur add nothing visible.
    func styleSettingsChrome() {
        guard let themeFrame = contentView?.superview else { return }
        for view in themeFrame.subviews where view is NSVisualEffectView {
            view.isHidden = true
        }
        func hideBackdrops(in view: NSView) {
            for sub in view.subviews {
                if let layer = sub.layer, String(describing: type(of: layer)).contains("Backdrop") {
                    sub.isHidden = true
                } else {
                    hideBackdrops(in: sub)
                }
            }
        }
        // The title bar's fill must stay: it covers the strip the compositor leaves
        // black after the window grows. Its hairline over the tabs goes. Its tint is
        // the window color, but drawn translucent and through a color filter that
        // lifts it lighter than the window in dark mode, so it is held opaque and
        // unfiltered (AppKit restores both after every resize).
        func pinTint(_ layer: CALayer) {
            makePlain(layer)
            let id = ObjectIdentifier(layer)
            guard titlebarTintPins[id] == nil else { return }
            titlebarTintPins[id] = [
                layer.observe(\.opacity) { layer, _ in makePlain(layer) },
                layer.observe(\.filters) { layer, _ in makePlain(layer) },
            ]
        }
        func styleTitlebarFill(in layer: CALayer) {
            for sub in layer.sublayers ?? [] {
                if sub.frame.height > 0, sub.frame.height <= 1, sub.frame.minY < 0 {
                    sub.isHidden = true
                } else if String(describing: type(of: sub)).contains("Backdrop"),
                          sub.opacity < 1, sub.frame.width > 0 {
                    pinTint(sub)
                } else {
                    styleTitlebarFill(in: sub)
                }
            }
        }
        for container in themeFrame.subviews {
            let name = String(describing: type(of: container))
            if name.contains("Pocket") {
                container.isHidden = true
            } else if name.contains("Titlebar") {
                hideBackdrops(in: container)
                for background in container.subviews
                where String(describing: type(of: background)).contains("TitlebarBackground") {
                    if titlebarAppearsTransparent {
                        // The sidebar and the page title draw the strip themselves,
                        // like System Settings. A fill here would cut across both.
                        background.isHidden = true
                    } else if let layer = background.layer {
                        styleTitlebarFill(in: layer)
                    }
                }
            }
        }
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

/// Keeps a grouped form from scrolling sideways and hiding its labels.
private struct SettingsFormWidthLock: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsFormWidthLockView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? SettingsFormWidthLockView)?.pin()
    }
}

private final class SettingsFormWidthLockView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pin()
    }

    override func layout() {
        super.layout()
        pin()
    }

    func pin() {
        guard let scroll = nearestScrollView() else { return }
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        let clip = scroll.contentView
        guard clip.bounds.origin.x != 0 else { return }
        clip.setBoundsOrigin(NSPoint(x: 0, y: clip.bounds.origin.y))
        scroll.reflectScrolledClipView(clip)
    }

    private func nearestScrollView() -> NSScrollView? {
        var ancestor: NSView? = superview
        for _ in 0..<8 {
            guard let view = ancestor else { return nil }
            if let scroll = view as? NSScrollView { return scroll }
            if let found = Self.findScroll(in: view) { return found }
            ancestor = view.superview
        }
        return nil
    }

    private static func findScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for subview in view.subviews {
            if let found = findScroll(in: subview) { return found }
        }
        return nil
    }
}

/// What sits on a sidebar icon's tile.
private enum SettingsSidebarGlyph {
    /// System Settings' own General gear.
    case gear
    /// System Settings' own Battery glyph.
    case battery
    /// An SF Symbol, fitted so its longer side spans `extent` of the tile.
    case symbol(String, extent: CGFloat, weight: NSFont.Weight)
}

/// Tile colors measured from macOS 26 System Settings (Display P3, the gradient's
/// top and bottom rows).
private struct SettingsIconPalette {
    var top: Color
    var bottom: Color
    /// Black tiles get a faint inner edge, as the system's do, so they still read
    /// against a dark sidebar.
    var hasEdge = false

    static let blue = Self(top: p3(64, 144, 250), bottom: p3(56, 127, 239))
    static let cyan = Self(top: p3(96, 200, 236), bottom: p3(82, 182, 222))
    static let green = Self(top: p3(111, 207, 112), bottom: p3(97, 190, 99))
    static let gray = Self(top: p3(158, 158, 162), bottom: p3(136, 136, 142))
    static let black = Self(top: p3(12, 12, 12), bottom: p3(0, 0, 0), hasEdge: true)

    private static func p3(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(.displayP3, red: red / 255, green: green / 255, blue: blue / 255)
    }
}

private struct SettingsSidebarEntry: Identifiable {
    var pane: SettingsView.Pane
    var title: String
    var glyph: SettingsSidebarGlyph
    var palette: SettingsIconPalette
    var id: SettingsView.Pane { pane }
}

/// A System Settings sidebar icon. Proportions, colors and shadows are measured
/// from macOS 26 System Settings at 2x. Every glyph is drawn at exact coordinates
/// inside a tile-sized frame, so layout rounding cannot push it off center.
private struct SettingsSidebarIcon: View {
    var glyph: SettingsSidebarGlyph
    var palette: SettingsIconPalette
    var size: CGFloat = SettingsChrome.iconSize
    @Environment(\.colorScheme) private var colorScheme

    /// System glyphs are white at about 94%, so a little of the tile shows through.
    private static let ink = Color.white.opacity(0.94)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom))
                .overlay {
                    if palette.hasEdge {
                        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.07), lineWidth: 0.5)
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0.6)
            glyphLayer
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyphLayer: some View {
        switch glyph {
        case .gear:
            SettingsGearGlyph()
                .fill(Self.ink)
                .glyphShadow()
        case .battery:
            ZStack {
                SettingsBatteryTray()
                    .fill(Color.white.opacity(0.2), style: FillStyle(eoFill: true))
                SettingsBatteryGlyph()
                    .fill(Self.ink, style: FillStyle(eoFill: true))
                    .glyphShadow()
            }
        case .symbol(let name, let extent, let weight):
            if let image = SettingsSymbolGlyphs.tileImage(name, weight: weight, extent: extent, tile: size) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .foregroundStyle(Self.ink)
                    .glyphShadow()
            }
        }
    }
}

private extension View {
    /// The soft shadow System Settings puts under each white glyph.
    func glyphShadow() -> some View {
        shadow(color: .black.opacity(0.15), radius: 0.5, x: 0, y: 0.5)
    }
}

/// System Settings' General gear: 24 tapered teeth on a ring, three spokes and a
/// small hub, in fractions of the tile. Filled with the nonzero rule: the ring's
/// hole and the hub's hole run the other way round, so spokes fill where they cross them.
private struct SettingsGearGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let tipRadius = 0.373 * s
        let rootRadius = 0.3125 * s
        let ringInner = 0.269 * s
        let hubOuter = 0.0433 * s
        let hubInner = 0.0144 * s
        let spokeHalfWidth = 0.0212 * s
        let teeth = 24
        let pitch = 360.0 / Double(teeth)
        let rootHalf = 4.7
        let tipHalf = 2.1

        func point(_ radius: CGFloat, _ degrees: Double) -> CGPoint {
            let radians = degrees * .pi / 180
            return CGPoint(x: center.x + radius * cos(radians), y: center.y - radius * sin(radians))
        }

        var path = Path()

        // Teeth and the ring's outer edge, counterclockwise on screen.
        path.move(to: point(rootRadius, -pitch / 2))
        for tooth in 0..<teeth {
            let middle = Double(tooth) * pitch
            for step in 1...4 {
                let t = Double(step) / 4
                path.addLine(to: point(rootRadius, middle - pitch / 2 + (pitch / 2 - rootHalf) * t))
            }
            path.addLine(to: point(tipRadius, middle - tipHalf))
            path.addLine(to: point(tipRadius, middle))
            path.addLine(to: point(tipRadius, middle + tipHalf))
            path.addLine(to: point(rootRadius, middle + rootHalf))
            for step in 1...4 {
                let t = Double(step) / 4
                path.addLine(to: point(rootRadius, middle + rootHalf + (pitch / 2 - rootHalf) * t))
            }
        }
        path.closeSubpath()

        addCircle(&path, radius: ringInner, clockwise: true, segments: 120, point: point)
        addCircle(&path, radius: hubOuter, clockwise: false, segments: 36, point: point)
        addCircle(&path, radius: hubInner, clockwise: true, segments: 24, point: point)

        // Spokes reach a hair into the hub ring and the outer ring so the joins have no seam.
        let spokeStart = hubOuter - 0.006 * s
        let spokeEnd = ringInner + 0.012 * s
        for degrees in [0.0, 120.0, 240.0] {
            let radians = degrees * .pi / 180
            let along = CGVector(dx: cos(radians), dy: -sin(radians))
            let across = CGVector(dx: -sin(radians), dy: -cos(radians))
            func corner(_ radius: CGFloat, _ offset: CGFloat) -> CGPoint {
                CGPoint(
                    x: center.x + along.dx * radius + across.dx * offset,
                    y: center.y + along.dy * radius + across.dy * offset
                )
            }
            path.move(to: corner(spokeStart, -spokeHalfWidth))
            path.addLine(to: corner(spokeEnd, -spokeHalfWidth))
            path.addLine(to: corner(spokeEnd, spokeHalfWidth))
            path.addLine(to: corner(spokeStart, spokeHalfWidth))
            path.closeSubpath()
        }
        return path
    }

    private func addCircle(
        _ path: inout Path,
        radius: CGFloat,
        clockwise: Bool,
        segments: Int,
        point: (CGFloat, Double) -> CGPoint
    ) {
        for step in 0...segments {
            let fraction = Double(step) / Double(segments)
            let degrees = (clockwise ? 1 - fraction : fraction) * 360
            if step == 0 {
                path.move(to: point(radius, degrees))
            } else {
                path.addLine(to: point(radius, degrees))
            }
        }
        path.closeSubpath()
    }
}

/// System Settings' Battery glyph in fractions of the tile. Like the system's,
/// the body (not body plus terminal) is what sits in the middle.
private enum SettingsBatteryMetrics {
    static let bodyWidth: CGFloat = 0.641
    static let bodyHeight: CGFloat = 0.328
    static let bodyOffsetX: CGFloat = -0.0206
    static let stroke: CGFloat = 0.0337
    static let outerRadius: CGFloat = 0.0817
    static let fillInset: CGFloat = 0.0692
    static let fillRadius: CGFloat = 0.0288
    static let capGap: CGFloat = 0.0365
    static let capWidth: CGFloat = 0.0413
    static let capHeight: CGFloat = 0.1096
    static let capRadius: CGFloat = 0.0385

    static func body(in rect: CGRect) -> CGRect {
        let s = min(rect.width, rect.height)
        return CGRect(
            x: rect.midX + (bodyOffsetX - bodyWidth / 2) * s,
            y: rect.midY - bodyHeight / 2 * s,
            width: bodyWidth * s,
            height: bodyHeight * s
        )
    }

    static func inner(in rect: CGRect) -> CGRect {
        body(in: rect).insetBy(dx: stroke * min(rect.width, rect.height), dy: stroke * min(rect.width, rect.height))
    }

    static func fill(in rect: CGRect) -> CGRect {
        body(in: rect).insetBy(dx: fillInset * min(rect.width, rect.height), dy: fillInset * min(rect.width, rect.height))
    }
}

/// Outline, charge and terminal, filled even-odd.
private struct SettingsBatteryGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        typealias M = SettingsBatteryMetrics
        let body = M.body(in: rect)
        var path = Path()
        path.addRoundedRect(in: body, cornerSize: CGSize(width: M.outerRadius * s, height: M.outerRadius * s), style: .continuous)
        let innerRadius = (M.outerRadius - M.stroke) * s
        path.addRoundedRect(in: M.inner(in: rect), cornerSize: CGSize(width: innerRadius, height: innerRadius), style: .continuous)
        path.addRoundedRect(in: M.fill(in: rect), cornerSize: CGSize(width: M.fillRadius * s, height: M.fillRadius * s), style: .continuous)
        let cap = CGRect(
            x: body.maxX + M.capGap * s,
            y: rect.midY - M.capHeight / 2 * s,
            width: M.capWidth * s,
            height: M.capHeight * s
        )
        path.addPath(
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(bottomTrailing: M.capRadius * s, topTrailing: M.capRadius * s),
                style: .continuous
            )
            .path(in: cap)
        )
        return path
    }
}

/// The faint tint between the battery's outline and its charge.
private struct SettingsBatteryTray: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        typealias M = SettingsBatteryMetrics
        var path = Path()
        let innerRadius = (M.outerRadius - M.stroke) * s
        path.addRoundedRect(in: M.inner(in: rect), cornerSize: CGSize(width: innerRadius, height: innerRadius), style: .continuous)
        path.addRoundedRect(in: M.fill(in: rect), cornerSize: CGSize(width: M.fillRadius * s, height: M.fillRadius * s), style: .continuous)
        return path
    }
}

/// SF Symbols drawn as tile-sized template images. A symbol image carries text
/// layout padding above and below its ink, so centering the image leaves the
/// glyph low; these images center the drawn pixels themselves instead.
@MainActor
private enum SettingsSymbolGlyphs {
    private static var cache: [String: NSImage] = [:]

    static func tileImage(_ name: String, weight: NSFont.Weight, extent: CGFloat, tile: CGFloat) -> NSImage? {
        let key = "\(name)|\(weight.rawValue)|\(extent)|\(tile)"
        if let cached = cache[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: 100, weight: weight)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration),
              let ink = inkBounds(of: symbol) else { return nil }
        let scale = extent * tile / max(ink.width, ink.height)
        let frame = NSRect(
            x: (tile - ink.width * scale) / 2 - ink.minX * scale,
            y: (tile - ink.height * scale) / 2 - ink.minY * scale,
            width: symbol.size.width * scale,
            height: symbol.size.height * scale
        )
        let image = makeTileImage(symbol, in: frame, tile: tile)
        cache[key] = image
        return image
    }

    /// Nonisolated so the drawing handler can run wherever AppKit draws it.
    nonisolated private static func makeTileImage(_ symbol: NSImage, in frame: NSRect, tile: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: tile, height: tile), flipped: false) { _ in
            symbol.draw(in: frame)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The symbol's inked area in its own points, origin bottom left.
    private static func inkBounds(of symbol: NSImage) -> NSRect? {
        let scale: CGFloat = 2
        let width = Int((symbol.size.width * scale).rounded(.up))
        let height = Int((symbol.size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        // Draw across every pixel of the bitmap and convert back with the real
        // pixels-per-point below. Relying on the bitmap's point size instead is
        // order-sensitive: a context made before that size is set draws at 1x,
        // which halves the measured ink and doubles every glyph.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        symbol.draw(in: NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.bitmapData else { return nil }
        var minX = width, maxX = -1, minY = height, maxY = -1
        for row in 0..<height {
            for column in 0..<width where data[row * width * 4 + column * 4 + 3] > 24 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let pixelsPerPointX = CGFloat(width) / symbol.size.width
        let pixelsPerPointY = CGFloat(height) / symbol.size.height
        // Bitmap rows run top to bottom; image points run bottom to top.
        return NSRect(
            x: CGFloat(minX) / pixelsPerPointX,
            y: CGFloat(height - 1 - maxY) / pixelsPerPointY,
            width: CGFloat(maxX - minX + 1) / pixelsPerPointX,
            height: CGFloat(maxY - minY + 1) / pixelsPerPointY
        )
    }
}

/// The system sidebar material, so the column picks up the desktop behind the
/// window and dims when the window is inactive, as System Settings does.
private struct SettingsSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// One sidebar row. The selection is the accent color with white text while the
/// window is active and turns gray when it is not, as in System Settings.
private struct SettingsSidebarRow: View {
    var item: SettingsSidebarEntry
    var selected: Bool
    var select: () -> Void
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        let emphasized = selected && activeState != .inactive
        let highlight = RoundedRectangle(cornerRadius: SettingsChrome.selectionRadius, style: .continuous)
        Button(action: select) {
            HStack(spacing: SettingsChrome.iconLabelSpacing) {
                SettingsSidebarIcon(glyph: item.glyph, palette: item.palette)
                Text(item.title)
                    .font(.system(size: SettingsChrome.labelSize))
                    .foregroundStyle(emphasized ? Color.white : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SettingsChrome.rowPadding)
            .frame(height: SettingsChrome.rowHeight)
            .background {
                if selected {
                    // The sidebar's emphasized selection color, a shade deeper than the
                    // plain accent color, as System Settings draws it.
                    highlight.fill(
                        emphasized
                            ? AnyShapeStyle(Color(nsColor: .selectedContentBackgroundColor))
                            : AnyShapeStyle(Color.primary.opacity(0.1))
                    )
                }
            }
            .contentShape(highlight)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SettingsView: View {
    fileprivate enum Pane: String, CaseIterable, Identifiable {
        case general, permissions, panel, tutorial, menuBar, rings, flow, topApps, lowPower, localIP, batteryCycle, about
        var id: String { rawValue }
    }

    /// Pages inside the Tutorial sidebar tab. Titles reuse settings names when they match.
    private enum TutorialPage: String, CaseIterable, Identifiable {
        case start, panel, menuBar, rings, flow, topApps, lowPower, localIP, batteryCycle
        var id: String { rawValue }

        /// The settings page this tutorial page explains.
        var settingsPane: Pane? {
            switch self {
            case .start: nil
            case .panel: .panel
            case .menuBar: .menuBar
            case .rings: .rings
            case .flow: .flow
            case .topApps: .topApps
            case .lowPower: .lowPower
            case .localIP: .localIP
            case .batteryCycle: .batteryCycle
            }
        }

        var titleKey: String {
            switch self {
            case .start: "tutorial.page.start"
            case .menuBar: "settings.section.icon"
            case .rings: "settings.tab.rings"
            case .flow: "settings.tab.flow"
            case .topApps: "settings.tab.topApps"
            case .lowPower: "settings.tab.lowPower"
            case .panel: "settings.popover.order"
            case .localIP: "settings.tab.localIP"
            case .batteryCycle: "settings.tab.batteryCycle"
            }
        }
    }

    @Bindable var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var pane: Pane
    @State private var tutorialPage: TutorialPage = .start
    @State private var ringColorSelectionID: UUID?
    @State private var saveDialog: SaveTintDialog?
    @State private var menuBarTintOrigin: MenuBarTintPreset?
    @State private var showsAllMenuBarPresets = false
    @State private var menuBarEditingBandID: UUID?
    @State private var flowEditingMode: EnergyFlowMode = .discharging
    @State private var flowEditingBandID: UUID?
    @State private var flowTintOrigin: PopoverTintPreset?
    @State private var ringTintOrigin: PopoverTintPreset?
    @State private var ringEditingBandID: UUID?
    @State private var ringOptionsItemID: String?
    @State private var showingBluetoothDevices = false
    @State private var showingAuthorSupport = false
    @State private var bluetoothIconEditor: BluetoothIconEdit?
    @State private var showingBluetoothPermissionReason = false
    @State private var permissionRefresh = Date()

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
    @State private var ringItemDrag = RingItemDragState()
    @State private var popoverDrag = PopoverBlockDragState()
    @State private var ringScaleSlot: RingSlot?
    @State private var ringIconEditor: RingSlot?

    init(appState: AppState) {
        self.appState = appState
        // First interactive launch lands on Tutorial. Later opens keep the default pane.
        _pane = State(initialValue: appState.showsWelcomeGuide ? .tutorial : .general)
    }

    private var screenLimit: CGFloat {
        NSScreen.main?.visibleFrame.height ?? 900
    }

    /// One window size for every page. The detail column scrolls instead of resizing.
    private var displayHeight: CGFloat {
        min(SettingsColumn.preferredHeight, screenLimit)
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            settingsDetail
        }
        // The sidebar and the detail column each run up under the transparent
        // title strip and leave SettingsChrome.stripHeight for it themselves.
        .frame(width: SettingsColumn.width, height: displayHeight, alignment: .topLeading)
        .background {
            SettingsWindowSizer(height: displayHeight)
                .frame(width: 0, height: 0)
        }
        .frame(width: SettingsColumn.width, alignment: .topLeading)
        // A zero minimum keeps NSHostingView from growing the window on its own to
        // fit a taller tab (and adding the title bar twice with a full-size content
        // view). SettingsWindowSizer is the only thing that sizes this window.
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        .animation(nil, value: pane)
        .background(Color(nsColor: .windowBackgroundColor))
        // Full-size content view: the title strip is left by hand in each column,
        // so SwiftUI's safe area cannot shift the tabs between panes.
        .ignoresSafeArea()
        .environment(\.locale, appState.settings.resolvedLocale)
        .id(appState.settings.language)
        .onChange(of: appState.settings.language) { _, _ in
            appState.refreshLocalizedChrome()
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

    /// Sidebar entries in System Settings style groups: the app as a whole, how it
    /// shows itself, the panel's sections, then help. Colors follow System
    /// Settings' own mix: mostly blue, with gray, black, cyan and green between.
    private var settingsSidebarGroups: [[SettingsSidebarEntry]] {
        let language = appState.settings.language
        func entry(_ pane: Pane, _ key: String, _ glyph: SettingsSidebarGlyph, _ palette: SettingsIconPalette) -> SettingsSidebarEntry {
            SettingsSidebarEntry(
                pane: pane,
                title: Localization.string(key, language: language),
                glyph: glyph,
                palette: palette
            )
        }
        func symbol(_ name: String, _ extent: CGFloat, _ weight: NSFont.Weight = .medium) -> SettingsSidebarGlyph {
            .symbol(name, extent: extent, weight: weight)
        }
        return [
            [
                // System Settings' General.
                entry(.general, "settings.section.general", .gear, .gray),
                entry(.permissions, "settings.tab.permissions", symbol("lock.shield.fill", 0.6), .blue),
            ],
            [
                // System Settings' Battery.
                entry(.menuBar, "settings.section.icon", .battery, .green),
                // Black like System Settings' Desktop & Dock.
                entry(.panel, "settings.popover.order", symbol("rectangle.3.group", 0.62), .black),
            ],
            [
                entry(.rings, "settings.tab.rings", symbol("circle.circle", 0.62), .blue),
                entry(.flow, "settings.tab.flow", symbol("bolt.fill", 0.64), .cyan),
                entry(.topApps, "settings.tab.topApps", symbol("chart.bar.fill", 0.58), .blue),
                entry(.lowPower, "settings.tab.lowPower", symbol("leaf.fill", 0.6), .green),
                // System Settings' Network.
                entry(.localIP, "settings.tab.localIP", symbol("network", 0.65, .regular), .blue),
                entry(.batteryCycle, "settings.tab.batteryCycle", symbol("arrow.triangle.2.circlepath", 0.64), .gray),
            ],
            [
                entry(.tutorial, "settings.tab.tutorial", symbol("book.closed.fill", 0.6), .blue),
                entry(.about, "settings.tab.about", symbol("info.circle", 0.62), .gray),
            ],
        ]
    }

    private var selectedTitle: String {
        settingsSidebarGroups.joined().first { $0.pane == pane }?.title ?? ""
    }

    private var settingsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(settingsSidebarGroups.enumerated()), id: \.offset) { index, group in
                    if index > 0 {
                        Spacer(minLength: 0)
                            .frame(height: SettingsChrome.groupGap)
                    }
                    ForEach(group) { item in
                        SettingsSidebarRow(item: item, selected: pane == item.pane) {
                            pane = item.pane
                        }
                    }
                }
            }
            .padding(.horizontal, SettingsChrome.rowInset)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .scrollIndicators(.hidden)
        // The traffic lights sit in the strip above the first row.
        .padding(.top, SettingsChrome.stripHeight)
        .frame(width: SettingsColumn.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            SettingsSidebarMaterial()
        }
    }

    private var settingsDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The page title lives in the title strip, beside the traffic lights'
            // row, the way System Settings shows it in its toolbar.
            Text(selectedTitle)
                .font(.system(size: SettingsChrome.titleSize, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, SettingsChrome.titleLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: SettingsChrome.stripHeight)
                .accessibilityAddTraits(.isHeader)
            if pane == .tutorial {
                tutorialPane
            } else {
                settingsForm
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: SettingsColumn.contentWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// The tutorial as a short book: a contents menu, one page at a time, and
    /// buttons to turn the page or jump to the settings it describes.
    private var tutorialPane: some View {
        let pages = TutorialPage.allCases
        let index = pages.firstIndex(of: tutorialPage) ?? 0
        let language = appState.settings.language
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(pages) { page in
                        Button {
                            tutorialPage = page
                        } label: {
                            if page == tutorialPage {
                                Label(Localization.string(page.titleKey, language: language), systemImage: "checkmark")
                            } else {
                                Text(Localization.string(page.titleKey, language: language))
                            }
                        }
                    }
                } label: {
                    Label("tutorial.contents", systemImage: "list.bullet")
                }
                .fixedSize()
                Spacer(minLength: 8)
                Text(Localization.string("tutorial.pageOf %lld %lld", language: language, index + 1, pages.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if tutorialPage != .start {
                        Text(LocalizedStringKey(tutorialPage.titleKey))
                            .font(.system(size: 17, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                    }
                    tutorialPageContent
                    if let target = tutorialPage.settingsPane {
                        Button {
                            pane = target
                        } label: {
                            HStack(spacing: 3) {
                                Text(Localization.string(
                                    "tutorial.openSettings %@",
                                    language: language,
                                    Localization.string(tutorialPage.titleKey, language: language)
                                ))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(tutorialPage)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()
            HStack(spacing: 10) {
                Button("tutorial.previous") {
                    tutorialPage = pages[max(index - 1, 0)]
                }
                .disabled(index == 0)
                Spacer(minLength: 8)
                if appState.showsWelcomeGuide {
                    Button("welcome.done") {
                        appState.completeWelcomeGuide()
                    }
                    .keyboardShortcut(index == pages.count - 1 ? .defaultAction : nil)
                }
                if index < pages.count - 1 {
                    Button("tutorial.next") {
                        tutorialPage = pages[index + 1]
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var tutorialPageContent: some View {
        switch tutorialPage {
        case .start:
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("welcome.title")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    justifiedBody("welcome.subtitle")
                }
                welcomeMenuPreview
                welcomeStep(
                    index: 1,
                    title: "welcome.icon.title",
                    body: "welcome.icon.body",
                    actionTitle: "welcome.icon.button",
                    action: { appState.openMenuBarSettings() }
                )
                welcomeStep(
                    index: 2,
                    title: "welcome.menu.title",
                    body: "welcome.menu.body"
                )
            }
        case .menuBar:
            tutorialIllustrated("tutorial.menuBar.body") { menuBarTutorialPreview }
        case .rings:
            VStack(alignment: .leading, spacing: 16) {
                ringsTutorialPreview
                    .frame(maxWidth: .infinity, alignment: .center)
                tutorialNote(title: "settings.rings.layout", "tutorial.rings.rows")
                tutorialNote(title: "settings.rings.bluetooth", "tutorial.rings.bluetooth")
                tutorialNote(title: "settings.icon.tint.preset", "tutorial.rings.colors")
                tutorialNote(title: "settings.rings.scale", "tutorial.rings.scale")
                tutorialNote(title: "settings.rings.thermalState", "tutorial.rings.thermal")
            }
        case .flow:
            tutorialIllustrated("tutorial.flow.body") { flowTutorialPreview }
        case .topApps:
            VStack(alignment: .leading, spacing: 16) {
                topAppsTutorialPreview
                    .frame(maxWidth: .infinity, alignment: .center)
                tutorialNote(title: "settings.topApps.chart", "tutorial.topApps.view")
                tutorialNote(title: "settings.topApps.window", "tutorial.topApps.window")
                tutorialNote(title: "popover.topApps.title", "tutorial.topApps.impact")
            }
        case .lowPower:
            VStack(alignment: .leading, spacing: 16) {
                lowPowerTutorialPreview
                    .frame(maxWidth: .infinity, alignment: .center)
                tutorialNote(title: "popover.lowPower.strategy", "tutorial.lowPower.strategy")
                tutorialNote(title: "popover.lowPower.now", "tutorial.lowPower.now")
                tutorialNote(title: "settings.lowPower.buttons", "tutorial.lowPower.buttons")
                tutorialNote(title: "settings.lowPower.layout", "tutorial.lowPower.layout")
            }
        case .panel:
            VStack(alignment: .leading, spacing: 18) {
                panelArrowDiagram
                    .frame(maxWidth: .infinity, alignment: .center)
                tutorialNote(title: "settings.popover.arrow", "tutorial.panel.arrow")
                panelButtonDiagram
                    .frame(maxWidth: .infinity, alignment: .center)
                tutorialNote(title: "settings.button.placement", "tutorial.panel.button")
                tutorialNote(title: "settings.popover.order", "tutorial.panel.blocks")
            }
        case .localIP:
            tutorialIllustrated("tutorial.localIP.body") { networkTutorialPreview }
        case .batteryCycle:
            tutorialIllustrated("tutorial.batteryCycle.body") { cycleTutorialPreview }
        }
    }

    private func tutorialNote(title: LocalizedStringKey, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            justifiedBody(body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func justifiedBody(_ key: String) -> some View {
        JustifiedBody(text: Localization.string(key, language: appState.settings.language))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tutorialIllustrated<Picture: View>(
        title: LocalizedStringKey? = nil,
        _ body: String,
        @ViewBuilder picture: () -> Picture
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            picture()
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityHidden(true)
            justifiedBody(body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Same bitmap the status item draws, including outline, tint, bolt, and beside-percent title.
    private var menuBarStatusIcon: some View {
        let appearance = NSApp.effectiveAppearance
        let image = MenuBarBatteryRenderer.image(
            snapshot: appState.snapshot,
            style: appState.settings.iconStyle,
            fill: appState.menuBarFill(appearance: appearance),
            appearance: appearance,
            showChargeGlyphs: appState.settings.showChargeGlyphs
        )
        return HStack(spacing: 0) {
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
            if appState.settings.digitPlacement == .beside {
                Text(" \(Int(appState.snapshot.percent.rounded()))%")
                    .font(.body)
            }
        }
    }

    /// Sample glyphs for the menu-bar tutorial. Each one is drawn by `MenuBarBatteryRenderer`.
    private struct MenuBarTutorialSample: Identifiable {
        var id: String
        var percent: Double
        var flowMode: EnergyFlowMode
        var style: MenuBarIconStyle
        var swatch: MenuBarTintSwatch
        var showChargeGlyphs: Bool
        var captionKeys: [String]
    }

    /// Filled and outline, percent inside and beside, a charge bolt, and green / yellow / red.
    private var menuBarTutorialSamples: [MenuBarTutorialSample] {
        [
            MenuBarTutorialSample(
                id: "fill-green",
                percent: 84,
                flowMode: .discharging,
                style: .systemFill,
                swatch: .systemGreen,
                showChargeGlyphs: false,
                captionKeys: ["settings.icon.border.off"]
            ),
            MenuBarTutorialSample(
                id: "inside-yellow",
                percent: 46,
                flowMode: .discharging,
                style: .systemPercentInside,
                swatch: .systemYellow,
                showChargeGlyphs: false,
                captionKeys: ["settings.icon.digits.inside"]
            ),
            MenuBarTutorialSample(
                id: "beside-red",
                percent: 12,
                flowMode: .discharging,
                style: .classicBeside,
                swatch: .systemRed,
                showChargeGlyphs: false,
                captionKeys: ["settings.icon.digits.beside"]
            ),
            MenuBarTutorialSample(
                id: "outline-green",
                percent: 84,
                flowMode: .discharging,
                style: .outlineFill,
                swatch: .systemGreen,
                showChargeGlyphs: false,
                captionKeys: ["settings.icon.border.on"]
            ),
            MenuBarTutorialSample(
                id: "outline-inside-yellow",
                percent: 46,
                flowMode: .discharging,
                style: .outlinePercentInside,
                swatch: .systemYellow,
                showChargeGlyphs: false,
                captionKeys: ["settings.icon.border.on", "settings.icon.digits.inside"]
            ),
            MenuBarTutorialSample(
                id: "bolt-green",
                percent: 68,
                flowMode: .charging,
                style: .systemFill,
                swatch: .systemGreen,
                showChargeGlyphs: true,
                captionKeys: ["settings.icon.chargeGlyphs"]
            ),
        ]
    }

    private var menuBarTutorialPreview: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
        return VStack(spacing: 16) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(menuBarTutorialSamples) { sample in
                    menuBarTutorialSampleCell(sample)
                }
            }
            Divider()
            VStack(spacing: 6) {
                menuBarStatusIcon
                Text("tutorial.menuBar.current")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: 460)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .center)
        .id(colorScheme)
    }

    private func menuBarTutorialSampleCell(_ sample: MenuBarTutorialSample) -> some View {
        VStack(spacing: 8) {
            menuBarTutorialGlyph(sample)
            menuBarSampleCaption(sample.captionKeys)
        }
        .frame(maxWidth: .infinity)
    }

    private func menuBarSampleCaption(_ keys: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                if index > 0 {
                    Text(" · ")
                }
                Text(LocalizedStringKey(key))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func menuBarTutorialGlyph(_ sample: MenuBarTutorialSample) -> some View {
        let appearance = NSApp.effectiveAppearance
        let tint = MenuBarTintScheme(
            preset: .custom,
            mode: .always,
            bands: [MenuBarTintBand(throughPercent: 100, swatch: sample.swatch)]
        )
        let snapshot = tutorialPowerSnapshot(percent: sample.percent, flowMode: sample.flowMode)
        let fill = tint.fill(percent: sample.percent, flowMode: sample.flowMode, appearance: appearance)
        let image = MenuBarBatteryRenderer.image(
            snapshot: snapshot,
            style: sample.style,
            fill: fill,
            appearance: appearance,
            showChargeGlyphs: sample.showChargeGlyphs
        )
        let scale: CGFloat = 1.65
        return HStack(spacing: 2) {
            Image(nsImage: image)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .frame(width: image.size.width * scale, height: image.size.height * scale)
            if sample.style.showsPercentBeside {
                Text("\(Int(snapshot.percent.rounded()))%")
                    .font(.system(size: 11 * scale, weight: .medium))
                    .monospacedDigit()
            }
        }
        .frame(height: 26)
    }

    private func tutorialPowerSnapshot(percent: Double, flowMode: EnergyFlowMode) -> PowerSnapshot {
        PowerSnapshot(
            hasBattery: true,
            percent: percent,
            isCharging: flowMode == .charging,
            externalConnected: flowMode != .discharging,
            fullyCharged: false,
            adapterCeilingWatts: flowMode == .discharging ? 0 : 70,
            adapterInWatts: flowMode == .discharging ? 0 : 45,
            systemLoadWatts: 12,
            batteryWatts: flowMode == .charging ? 30 : -12,
            remainingCapacityWh: 50,
            missingCapacityWh: 10,
            systemTimeToEmptyMinutes: nil,
            systemTimeToFullMinutes: nil,
            timeToEmptyMinutes: nil,
            timeToFullMinutes: nil,
            flowMode: flowMode
        )
    }

    private var ringsTutorialPreview: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 2) {
                    tutorialMetricRing(.battery, percent: 88)
                    tutorialMetricRing(.cpu, percent: 36)
                    tutorialMetricRing(.memory, percent: 72)
                }
                HStack(alignment: .top, spacing: 2) {
                    tutorialSpeedRing(bytesPerSecond: 2.4 * 1024 * 1024, upload: false)
                    tutorialTemperatureRing(celsius: 42)
                    tutorialThermalRing(.serious)
                }
            }
            tutorialRingOrderRow
        }
        .allowsHitTesting(false)
    }

    private func tutorialMetricRing(_ kind: RingKind, percent: Double) -> some View {
        let language = appState.settings.language
        let colors = appState.settings.ringTint.scheme(for: kind).colors(percent: percent)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: Localization.string(kind.captionKey, language: language, Int64(percent.rounded())),
            accessibilityName: Localization.string(kind.localizationKey, language: language),
            glyph: appState.settings.ringIcons.slot(for: kind)
        )
        .frame(width: 78)
    }

    private func tutorialSpeedRing(bytesPerSecond: Double, upload: Bool) -> some View {
        let language = appState.settings.language
        let center = Double(upload ? appState.settings.uploadHalfKilobytes : appState.settings.downloadHalfKilobytes) * 1024
        let percent = NetworkRateFormat.ringPercent(
            bytesPerSecond: bytesPerSecond,
            centerBytesPerSecond: center
        )
        let segment: RingColorSegment = upload ? .upload : .download
        let colors = appState.settings.ringTint.scheme(forSegment: segment).colors(percent: percent)
        let rate = NetworkRateFormat.string(bytesPerSecond: bytesPerSecond)
        let name = Localization.string(upload ? "settings.rings.upload" : "settings.rings.download", language: language)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: rate,
            accessibilityName: name,
            glyph: appState.settings.ringIcons.slot(for: upload ? .upload : .download),
            glyphTint: colors.left,
            accessibilityValue: "\(name) \(rate)"
        )
        .frame(width: 78)
    }

    private func tutorialTemperatureRing(celsius: Double) -> some View {
        let language = appState.settings.language
        let percent = BatteryTemperatureFormat.ringPercent(
            celsius: celsius,
            centerCelsius: Double(appState.settings.temperatureHalfCelsius)
        )
        let colors = appState.settings.ringTint.scheme(forSegment: .batteryTemperature).colors(percent: percent)
        let unit = appState.settings.temperatureUnit
        let value = BatteryTemperatureFormat.caption(celsius: celsius, unit: unit)
        let caption = Localization.string("ring.caption.batteryTemperature %@", language: language, value)
        let name = Localization.string("settings.rings.batteryTemperature", language: language)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: caption,
            accessibilityName: name,
            glyph: appState.settings.ringIcons.slot(for: .batteryTemperature),
            glyphTint: colors.left,
            accessibilityValue: "\(name) \(caption)"
        )
        .frame(width: 78)
    }

    private func tutorialThermalRing(_ level: MacThermalState) -> some View {
        let language = appState.settings.language
        let percent = level.ringPercent(
            nominal: appState.settings.thermalNominalPercent,
            fair: appState.settings.thermalFairPercent,
            serious: appState.settings.thermalSeriousPercent,
            critical: appState.settings.thermalCriticalPercent
        )
        let colors = appState.settings.ringTint.scheme(forSegment: .thermalState).colors(percent: percent)
        let caption = Localization.string(level.captionKey, language: language)
        let name = Localization.string("settings.rings.thermalState", language: language)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: caption,
            accessibilityName: name,
            glyph: appState.settings.ringIcons.slot(for: .thermalState),
            glyphTint: colors.left,
            accessibilityValue: "\(name) \(caption)"
        )
        .frame(width: 78)
    }

    /// Same row as Settings → Rings: grip, name, scale button, switch on the trailing edge.
    private var tutorialRingOrderRow: some View {
        Form {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 22)
                Toggle(isOn: .constant(true)) {
                    HStack(spacing: 6) {
                        Text("settings.rings.download")
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 16)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var flowTutorialPreview: some View {
        let snapshot = flowTutorialSnapshot
        return VStack(alignment: .leading, spacing: 4) {
            TimeEstimateRow(snapshot: snapshot, language: appState.settings.language)
            EnergyFlowView(
                snapshot: snapshot,
                theme: AppTheme.resolved(palette: appState.settings.palette, colorScheme: colorScheme),
                flowTint: appState.settings.flowTint,
                flowIcons: appState.settings.flowIcons,
                isAnimating: false,
                motion: appState.settings.motionStyle,
                motionFrameRate: appState.settings.motionFrameRate,
                pulseFlowIcons: appState.settings.pulseFlowIcons,
                flowIconScale: appState.settings.flowIconScale,
                language: appState.settings.language,
                showsFooter: true
            )
        }
        .frame(width: PopoverLayout.width - PopoverLayout.padding * 2, alignment: .leading)
        .allowsHitTesting(false)
    }

    /// Charging example so the row above the ribbon is 「预计充满」, matching the panel.
    private var flowTutorialSnapshot: PowerSnapshot {
        var snapshot = appState.snapshot
        snapshot.hasBattery = true
        if snapshot.percent < 1 { snapshot.percent = 55 }
        snapshot.isCharging = true
        snapshot.externalConnected = true
        snapshot.fullyCharged = false
        snapshot.flowMode = .charging
        if snapshot.adapterCeilingWatts <= 0 { snapshot.adapterCeilingWatts = 70 }
        if snapshot.systemLoadWatts <= 0 { snapshot.systemLoadWatts = 18 }
        if snapshot.chargeWatts <= 0 { snapshot.batteryWatts = 27 }
        if snapshot.timeToFullMinutes == nil { snapshot.timeToFullMinutes = 72 }
        return snapshot
    }

    private var topAppsTutorialPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(TopAppsChartStyle.allCases) { style in
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(style.localizationKey))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TopAppsSection(
                        list: tutorialTopApps,
                        language: appState.settings.language,
                        rowCount: 3,
                        chart: style
                    )
                }
            }
        }
        .frame(width: PopoverLayout.width - PopoverLayout.padding * 2, alignment: .leading)
        .allowsHitTesting(false)
    }

    private var tutorialTopApps: TopAppList {
        if case .apps(let apps) = appState.topApps, !apps.isEmpty {
            return .apps(Array(apps.prefix(3)))
        }
        return .apps([
            TopAppEntry(id: "safari", name: "Safari", iconPath: "/System/Applications/Safari.app", impact: 18.2),
            TopAppEntry(id: "finder", name: "Finder", iconPath: "/System/Library/CoreServices/Finder.app", impact: 9.4),
            TopAppEntry(id: "mail", name: "Mail", iconPath: "/System/Applications/Mail.app", impact: 3.1),
        ])
    }

    private var lowPowerTutorialPreview: some View {
        let language = appState.settings.language
        let strategy = appState.settings.lowPowerStrategy ?? appState.lowPowerPreset ?? .onlyBattery
        let labels = LowPowerPreset.allCases.map {
            Localization.string($0.shortLocalizationKey, language: language)
        }
        let lowTitle = Localization.string("popover.lowPower.now", language: language)
        let sideBySide = LowPowerButtonRowLayout.placesSideBySide(
            layout: appState.settings.lowPowerButtonLayout,
            visibility: .both,
            strategyLabels: labels,
            lowPowerLabel: lowTitle,
            panelWidth: PopoverLayout.width
        )
        let strategyButton = EnergyModeButton(
            title: Localization.string(strategy.shortLocalizationKey, language: language),
            lineLimit: LowPowerButtonRowLayout.strategyLines,
            fillsHeight: sideBySide,
            reserveTitles: labels,
            showsMenuIndicator: true
        )
        let nowButton = EnergyModeButton(
            title: lowTitle,
            systemImage: "battery.25percent",
            iconActive: appState.lowPowerNow == true,
            lineLimit: LowPowerButtonRowLayout.lowPowerLines,
            fillsHeight: sideBySide
        )
        let defaultControl = LowPowerLabeledButton(label: Localization.string("popover.lowPower.defaultState", language: language)) {
            strategyButton
        }
        let currentControl = LowPowerLabeledButton(label: Localization.string("popover.lowPower.currentState", language: language)) {
            nowButton
        }
        return Group {
            if sideBySide {
                HStack(alignment: .top, spacing: LowPowerButtonRowLayout.buttonSpacing) {
                    defaultControl
                    currentControl
                }
            } else {
                VStack(alignment: .leading, spacing: LowPowerButtonRowLayout.buttonSpacing) {
                    defaultControl
                    currentControl
                }
            }
        }
        .frame(width: PopoverLayout.width - PopoverLayout.padding * 2, alignment: .leading)
        .allowsHitTesting(false)
    }

    /// Open panel, with and without the menu-bar arrow. The arrow is the popover's
    /// own triangle, sitting on the top edge and aimed at the status icon.
    private var panelArrowDiagram: some View {
        VStack(spacing: 22) {
            panelArrowSample(showsArrow: true)
            panelArrowSample(showsArrow: false)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func panelArrowSample(showsArrow: Bool) -> some View {
        VStack(spacing: showsArrow ? 2 : 10) {
            menuBarStatusIcon
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    if showsArrow {
                        Capsule(style: .continuous)
                            .fill(Color(nsColor: .selectedContentBackgroundColor).opacity(0.22))
                    }
                }
            panelPopoverCard(showsArrow: showsArrow) {
                VStack(alignment: .leading, spacing: 4) {
                    TimeEstimateRow(snapshot: appState.snapshot, language: appState.settings.language)
                    tutorialEnergyFlow(showsFooter: true)
                }
            }
        }
    }

    /// Where the settings control actually appears. Inside-a-block has two hosts:
    /// a ring cell, and a corner gear on any other block.
    private var panelButtonDiagram: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                panelButtonSample("settings.button.rightClickOnly", width: 220) {
                    VStack(spacing: 4) {
                        menuBarStatusIcon
                        statusItemMenuCard
                    }
                }
                panelButtonSample("settings.button.ownBlock", width: 220) {
                    panelPlainCard {
                        VStack(alignment: .leading, spacing: 12) {
                            tutorialCycleSection(showsSettingsButton: false)
                            tutorialOwnBlockButton
                        }
                    }
                }
            }
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    panelPlainCard {
                        HStack(alignment: .top, spacing: PopoverLayout.ringSpacing) {
                            tutorialMetricRing(.battery, percent: 100)
                            tutorialMetricRing(.cpu, percent: 44)
                            RingSettingsCell(
                                title: Localization.string("settings.title", language: appState.settings.language)
                            )
                            .frame(width: 78)
                        }
                    }
                    .frame(width: 266, alignment: .leading)
                    panelPlainCard {
                        VStack(alignment: .leading, spacing: 10) {
                            tutorialEnergyFooter
                            tutorialCycleSection(showsSettingsButton: true)
                        }
                    }
                    .frame(minWidth: 168, maxWidth: .infinity, alignment: .leading)
                }
                Text("settings.button.insideBlock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func panelButtonSample<Picture: View>(
        _ caption: LocalizedStringKey,
        width: CGFloat,
        @ViewBuilder picture: () -> Picture
    ) -> some View {
        VStack(spacing: 8) {
            picture()
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width)
        }
        .frame(width: width, alignment: .top)
    }

    /// Same control the settings block draws at the bottom of the panel.
    private var tutorialOwnBlockButton: some View {
        let title = Localization.string("settings.title", language: appState.settings.language)
        return EnergyModeButton(title: title, systemImage: "gearshape")
            .accessibilityLabel(title)
    }

    private func tutorialCycleSection(showsSettingsButton: Bool) -> some View {
        BatteryCycleSection(
            hasBattery: appState.snapshot.hasBattery,
            cycleCount: appState.snapshot.cycleCount,
            fullChargeMilliAmpHours: appState.snapshot.fullChargeMilliAmpHours,
            designCapacityMilliAmpHours: appState.snapshot.designCapacityMilliAmpHours,
            capacityStyle: appState.settings.batteryCapacityStyle,
            language: appState.settings.language,
            showsSettingsButton: showsSettingsButton
        )
    }

    /// Charger-rating line the energy ribbon draws under itself, so the corner
    /// gear sits on the same trailing edge as that value.
    private var tutorialEnergyFooter: some View {
        let language = appState.settings.language
        return Group {
            switch EnergyFlowFooterPresentation.forSnapshot(appState.snapshot) {
            case .unplugged:
                Text(Localization.string("energy.noExternalPower", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .chargerRating(let watts):
                HStack {
                    Text(Localization.string("energy.chargerRating", language: language))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(watts > 0 ? String(format: "%.0f W", watts) : "—")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .lineLimit(1)
                }
                .font(.caption)
            }
        }
    }

    private func tutorialEnergyFlow(showsFooter: Bool) -> some View {
        EnergyFlowView(
            snapshot: appState.snapshot,
            theme: AppTheme.resolved(palette: appState.settings.palette, colorScheme: colorScheme),
            flowTint: appState.settings.flowTint,
            flowIcons: appState.settings.flowIcons,
            isAnimating: false,
            motion: appState.settings.motionStyle,
            motionFrameRate: appState.settings.motionFrameRate,
            pulseFlowIcons: appState.settings.pulseFlowIcons,
            flowIconScale: appState.settings.flowIconScale,
            language: appState.settings.language,
            showsFooter: showsFooter
        )
    }

    /// Popover body. The arrow, when shown, is part of the top edge and points at the icon above.
    private func panelPopoverCard<Content: View>(showsArrow: Bool, @ViewBuilder content: () -> Content) -> some View {
        let arrow: CGFloat = showsArrow ? PanelPopoverShape.arrowHeight : 0
        return content()
            .padding(.horizontal, PopoverLayout.padding)
            .padding(.top, PopoverLayout.padding + arrow)
            .padding(.bottom, PopoverLayout.padding)
            .frame(width: PopoverLayout.width, alignment: .leading)
            .background {
                PanelPopoverShape(showsArrow: showsArrow)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
            }
            .overlay {
                PanelPopoverShape(showsArrow: showsArrow)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
    }

    private func panelPlainCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10))
            }
    }

    /// Menu-bar popover outline. The triangle is the top edge, centered, pointing up.
    private struct PanelPopoverShape: Shape {
        static let arrowWidth: CGFloat = 28
        static let arrowHeight: CGFloat = 12
        var showsArrow: Bool
        var cornerRadius: CGFloat = 16

        func path(in rect: CGRect) -> Path {
            let radius = cornerRadius
            let arrow = showsArrow ? Self.arrowHeight : 0
            let body = CGRect(
                x: rect.minX,
                y: rect.minY + arrow,
                width: rect.width,
                height: max(rect.height - arrow, radius * 2)
            )
            guard showsArrow else {
                return Path(roundedRect: body, cornerRadius: radius, style: .continuous)
            }
            let mid = rect.midX
            let half = Self.arrowWidth / 2
            let top = body.minY
            let bottom = body.maxY
            let left = body.minX
            let right = body.maxX
            var path = Path()
            path.move(to: CGPoint(x: left + radius, y: top))
            path.addLine(to: CGPoint(x: mid - half, y: top))
            path.addLine(to: CGPoint(x: mid, y: rect.minY))
            path.addLine(to: CGPoint(x: mid + half, y: top))
            path.addLine(to: CGPoint(x: right - radius, y: top))
            path.addArc(
                tangent1End: CGPoint(x: right, y: top),
                tangent2End: CGPoint(x: right, y: top + radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: right, y: bottom - radius))
            path.addArc(
                tangent1End: CGPoint(x: right, y: bottom),
                tangent2End: CGPoint(x: right - radius, y: bottom),
                radius: radius
            )
            path.addLine(to: CGPoint(x: left + radius, y: bottom))
            path.addArc(
                tangent1End: CGPoint(x: left, y: bottom),
                tangent2End: CGPoint(x: left, y: bottom - radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: left, y: top + radius))
            path.addArc(
                tangent1End: CGPoint(x: left, y: top),
                tangent2End: CGPoint(x: left + radius, y: top),
                radius: radius
            )
            path.closeSubpath()
            return path
        }
    }

    private var networkTutorialPreview: some View {
        LocalIPSection(
            rows: tutorialIPRows,
            language: appState.settings.language,
            panelWidth: PopoverLayout.width
        )
        .frame(width: PopoverLayout.width - PopoverLayout.padding * 2, alignment: .leading)
        .allowsHitTesting(false)
    }

    /// Fixed examples covering every scope, both families, two interfaces, and a failed lookup.
    private var tutorialIPRows: [IPAddressRow] {
        [
            IPAddressRow(scope: .local, family: .ipv4, interfaceName: "en0", address: "192.168.1.24", failed: false),
            IPAddressRow(scope: .local, family: .ipv4, interfaceName: "en1", address: "10.0.1.18", failed: false),
            IPAddressRow(scope: .local, family: .ipv6, interfaceName: "en0", address: "240e:3b1:12:34:a1b2:c3d4:e5f6:7890", failed: false),
            IPAddressRow(scope: .publicAddress, family: .ipv4, interfaceName: nil, address: "203.0.113.48", failed: false),
            IPAddressRow(scope: .publicAddress, family: .ipv6, interfaceName: nil, address: "2001:db8:85a3::8a2e:370:7334", failed: false),
            IPAddressRow(scope: .publicAddress, family: .ipv4, interfaceName: nil, address: "", failed: true),
            IPAddressRow(scope: .loopback, family: .ipv4, interfaceName: "lo0", address: "127.0.0.1", failed: false),
            IPAddressRow(scope: .loopback, family: .ipv6, interfaceName: "lo0", address: "::1", failed: false),
            IPAddressRow(scope: .linkLocal, family: .ipv4, interfaceName: "en0", address: "169.254.42.16", failed: false),
            IPAddressRow(scope: .linkLocal, family: .ipv6, interfaceName: "en0", address: "fe80::a1b2:c3d4:e5f6:7890", failed: false),
        ]
    }

    private var cycleTutorialPreview: some View {
        BatteryCycleSection(
            hasBattery: appState.snapshot.hasBattery,
            cycleCount: appState.snapshot.cycleCount,
            fullChargeMilliAmpHours: appState.snapshot.fullChargeMilliAmpHours,
            designCapacityMilliAmpHours: appState.snapshot.designCapacityMilliAmpHours,
            capacityStyle: appState.settings.batteryCapacityStyle,
            language: appState.settings.language
        )
        .frame(width: PopoverLayout.width - PopoverLayout.padding * 2, alignment: .leading)
        .allowsHitTesting(false)
    }

    /// Right-click menu under the status icon: Open Settings, then Quit.
    private var statusItemMenuCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("menu.openSettings")
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .padding(4)
            Text("settings.quit")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .padding(.top, 2)
        }
        .font(.system(size: 13))
        .frame(width: 220)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
    }

    private var welcomeMenuPreview: some View {
        VStack(alignment: .trailing, spacing: 8) {
            VStack(spacing: 2) {
                menuBarStatusIcon
                Text("welcome.preview.icon")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            statusItemMenuCard
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func welcomeStep(
        index: Int,
        title: LocalizedStringKey,
        body: String,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                justifiedBody(body)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .controlSize(.regular)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var settingsForm: some View {
        Form {
            switch pane {
            case .general: generalSections
            case .permissions: permissionsSections
            case .panel: panelSections
            case .menuBar: menuBarSections
            case .rings: ringsSections
            case .flow: flowSections
            case .topApps: topAppsSections
            case .lowPower: lowPowerSections
            case .localIP: localIPSections
            case .batteryCycle: batteryCycleSections
            case .about: aboutSections
            case .tutorial: EmptyView()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsFormWidthLock())
        .onChange(of: pane) { _, newPane in
            if newPane == .permissions {
                refreshPermissionStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard pane == .permissions else { return }
            refreshPermissionStatus()
        }
        .alert(
            "settings.permissions.bluetooth.reason.title",
            isPresented: $showingBluetoothPermissionReason
        ) {
            Button("settings.permissions.bluetooth.reason.continue") {
                Task { await requestBluetoothFromSettings() }
            }
            Button("settings.permissions.bluetooth.reason.cancel", role: .cancel) {}
        } message: {
            Text("settings.permissions.bluetooth.reason.body")
        }
    }

    private func refreshPermissionStatus() {
        appState.launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        permissionRefresh = Date()
    }

    private func requestBluetoothFromSettings() async {
        _ = await AppPermissions.requestBluetoothAccess()
        refreshPermissionStatus()
        if AppPermissions.status(for: .bluetooth) == .allowed {
            await appState.refreshBluetoothNow()
        }
    }


    @ViewBuilder
    private var permissionsSections: some View {
        let _ = permissionRefresh
        Section {
            Text("settings.permissions.intro")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        Section {
            permissionBluetoothRow
        } header: {
            Text("settings.permissions.bluetooth.header")
        } footer: {
            Text("settings.permissions.bluetooth.footer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        Section {
            Toggle(isOn: launchAtLoginBinding) {
                SettingsRowLabel(
                    title: "settings.permissions.login.title",
                    caption: "settings.permissions.login.caption"
                )
            }
            permissionStatusLine(AppPermissions.status(for: .loginItem))
            Button("settings.permissions.login.openSettings") {
                AppPermissions.openSystemSettings(for: .loginItem)
            }
        } header: {
            Text("settings.permissions.login.header")
        } footer: {
            Text("settings.permissions.login.footer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        Section {
            Button("settings.permissions.refresh") {
                refreshPermissionStatus()
            }
        }
    }

    @ViewBuilder
    private var permissionBluetoothRow: some View {
        let status = AppPermissions.status(for: .bluetooth)
        VStack(alignment: .leading, spacing: 10) {
            SettingsRowLabel(
                title: "settings.permissions.bluetooth.title",
                caption: "settings.permissions.bluetooth.caption"
            )
            permissionStatusLine(status)
            HStack(spacing: 8) {
                switch status {
                case .notDetermined:
                    Button("settings.permissions.bluetooth.allow") {
                        showingBluetoothPermissionReason = true
                    }
                    .keyboardShortcut(.defaultAction)
                case .denied, .restricted:
                    Button("settings.permissions.bluetooth.openSettings") {
                        AppPermissions.openSystemSettings(for: .bluetooth)
                    }
                    .keyboardShortcut(.defaultAction)
                case .allowed, .unknown:
                    Button("settings.permissions.bluetooth.openSettings") {
                        AppPermissions.openSystemSettings(for: .bluetooth)
                    }
                }
                if status == .allowed {
                    Text("settings.permissions.bluetooth.revokeHint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func permissionStatusLine(_ status: AppPermissionStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: permissionStatusSymbol(status))
                .foregroundStyle(permissionStatusColor(status))
            Text(LocalizedStringKey(status.localizationKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func permissionStatusSymbol(_ status: AppPermissionStatus) -> String {
        switch status {
        case .allowed: "checkmark.circle.fill"
        case .denied, .restricted: "xmark.octagon.fill"
        case .notDetermined: "questionmark.circle.fill"
        case .unknown: "exclamationmark.circle.fill"
        }
    }

    private func permissionStatusColor(_ status: AppPermissionStatus) -> Color {
        switch status {
        case .allowed: .green
        case .denied, .restricted: .red
        case .notDetermined: .orange
        case .unknown: .secondary
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
            Toggle("settings.launchAtLogin", isOn: launchAtLoginBinding)
        }

        Section {
            HStack(spacing: 10) {
                SettingsAppIcon(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "MacPower \(AppState.marketingVersion)")
                        .fontWeight(.semibold)
                    if appState.isCheckingForUpdates {
                        Text("settings.updates.checking")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button("settings.updates.check") {
                    appState.checkForUpdates(reason: .manual)
                }
                .disabled(appState.isCheckingForUpdates)
            }
            Toggle(
                isOn: Binding(
                    get: { appState.settings.automaticallyCheckForUpdates },
                    set: { appState.setAutomaticUpdateChecking($0, checkNow: true) }
                )
            ) {
                SettingsRowLabel(title: "settings.updates.automatic", caption: "settings.updates.automatic.caption")
            }
        } header: {
            Text("settings.updates.header")
        }

        Section {
            HStack(spacing: 12) {
                SettingsRowLabel(title: "settings.quit", caption: "settings.quit.caption")
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Text("settings.quit.button")
                        .foregroundStyle(.red)
                }
            }
        }
    }


    @ViewBuilder
    private var panelSections: some View {
        Section {
            SettingsPreviewCard(title: "settings.preview.panel") {
                panelPreviewSchematic
            }
        }
        Section {
            ForEach(appState.settings.popoverOrder) { entry in
                popoverOrderEntry(entry)
            }
            Button {
                appState.settings.addPopoverDivider()
            } label: {
                Label("settings.popover.addDivider", systemImage: "plus")
            }
        } header: {
            Text("settings.popover.contents")
        } footer: {
            Text("settings.popover.order.footer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        Section {
            Toggle(isOn: $appState.settings.showPopoverArrow) {
                SettingsRowLabel(title: "settings.popover.arrow", caption: "tutorial.panel.arrow")
            }
            .onChange(of: appState.settings.showPopoverArrow) { _, _ in
                appState.onPopoverChromeChange?()
            }
            Picker("settings.button.placement", selection: $appState.settings.settingsButtonPlacement) {
                ForEach(SettingsButtonPlacement.allCases) { placement in
                    Text(LocalizedStringKey(placement.localizationKey)).tag(placement)
                }
            }
            if appState.settings.settingsButtonPlacement == .insideBlock {
                Picker("settings.button.host", selection: $appState.settings.settingsButtonHost) {
                    ForEach(appState.settings.visibleSettingsHosts) { host in
                        Text(LocalizedStringKey(host.localizationKey)).tag(host)
                    }
                }
                .padding(.leading, 16)
            }
        } header: {
            Text("settings.popover.appearance")
        } footer: {
            Text("settings.button.footer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// The panel's blocks in their current order, as a small outline: hidden
    /// blocks drop out, dividers show as rules, and a gear marks the settings button.
    private var panelPreviewSchematic: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(appState.settings.popoverOrder) { entry in
                panelPreviewLine(entry)
            }
        }
        .padding(10)
        .frame(width: 240, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    @ViewBuilder
    private func panelPreviewLine(_ entry: PopoverEntry) -> some View {
        let placement = appState.settings.settingsButtonPlacement
        switch entry {
        case .block(let block):
            if popoverVisibilityBinding(block).wrappedValue, block != .settings || placement == .ownBlock {
                let icon = popoverBlockIcon(block)
                HStack(spacing: 6) {
                    SettingsSidebarIcon(glyph: icon.glyph, palette: icon.palette, size: 16)
                    Text(LocalizedStringKey(block.localizationKey))
                        .font(.system(size: 11))
                    Spacer(minLength: 4)
                    if placement == .insideBlock, appState.settings.settingsButtonHost.rawValue == block.rawValue {
                        Image(systemName: "gearshape")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .divider:
            Divider()
        }
    }

    /// The sidebar's icon for each panel block, so the list matches the pages.
    private func popoverBlockIcon(_ block: PopoverBlock) -> (glyph: SettingsSidebarGlyph, palette: SettingsIconPalette) {
        switch block {
        case .rings: (.symbol("circle.circle", extent: 0.62, weight: .medium), .blue)
        case .flow: (.symbol("bolt.fill", extent: 0.64, weight: .medium), .cyan)
        case .topApps: (.symbol("chart.bar.fill", extent: 0.58, weight: .medium), .blue)
        case .lowPower: (.symbol("leaf.fill", extent: 0.6, weight: .medium), .green)
        case .localIP: (.symbol("network", extent: 0.65, weight: .regular), .blue)
        case .batteryCycle: (.symbol("arrow.triangle.2.circlepath", extent: 0.64, weight: .medium), .gray)
        case .settings: (.gear, .gray)
        }
    }


    @ViewBuilder
    private var localIPSections: some View {
        Section {
            SettingsPreviewCard(title: "settings.preview.panel") {
                LocalIPSection(
                    rows: tutorialIPRows.filter {
                        appState.settings.ipScopes.contains($0.scope)
                            && appState.settings.ipFamilies.contains($0.family)
                    },
                    language: appState.settings.language,
                    panelWidth: PopoverLayout.width
                )
                .frame(width: PopoverLayout.width - PopoverLayout.padding * 2, alignment: .leading)
                .allowsHitTesting(false)
            }
        }
        Section {
            ForEach(IPAddressScope.allCases) { scope in
                Toggle(isOn: ipScopeBinding(scope)) {
                    SettingsRowLabel(
                        title: LocalizedStringKey(scope.localizationKey),
                        caption: LocalizedStringKey(ipScopeCaptionKey(scope))
                    )
                }
            }
        } header: {
            Text("settings.localIP.scopes")
        }
        Section {
            Picker(selection: ipFamilyChoiceBinding) {
                Text(verbatim: "IPv4").tag(IPFamilyChoice.ipv4)
                Text(verbatim: "IPv6").tag(IPFamilyChoice.ipv6)
                Text("settings.localIP.families.both").tag(IPFamilyChoice.both)
            } label: {
                SettingsRowLabel(title: "settings.localIP.families.show", caption: "settings.localIP.families.caption")
            }
            .pickerStyle(.segmented)
        } header: {
            Text("settings.localIP.families")
        }
    }

    private enum IPFamilyChoice: Hashable {
        case ipv4, ipv6, both
    }

    private var ipFamilyChoiceBinding: Binding<IPFamilyChoice> {
        Binding(
            get: {
                let families = appState.settings.ipFamilies
                if families.contains(.ipv4), families.contains(.ipv6) { return .both }
                return families.contains(.ipv6) ? .ipv6 : .ipv4
            },
            set: { choice in
                switch choice {
                case .ipv4: appState.settings.ipFamilies = [.ipv4]
                case .ipv6: appState.settings.ipFamilies = [.ipv6]
                case .both: appState.settings.ipFamilies = [.ipv4, .ipv6]
                }
            }
        )
    }

    private func ipScopeCaptionKey(_ scope: IPAddressScope) -> String {
        switch scope {
        case .local: "settings.localIP.scope.local.caption"
        case .publicAddress: "settings.localIP.scope.public.caption"
        case .loopback: "settings.localIP.scope.loopback.caption"
        case .linkLocal: "settings.localIP.scope.linkLocal.caption"
        }
    }


    @ViewBuilder
    private var topAppsSections: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(TopAppsChartStyle.allCases) { style in
                    SettingsChoiceCard(
                        title: LocalizedStringKey(style.localizationKey),
                        selected: appState.settings.topAppsChart == style,
                        action: { appState.settings.topAppsChart = style }
                    ) {
                        topAppsChartThumbnail(style)
                    }
                }
            }
        } header: {
            Text("settings.topApps.chart.header")
        } footer: {
            Text("tutorial.topApps.view")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Section {
            topAppStepper(
                "settings.topApps.window.title",
                caption: "settings.topApps.window.caption",
                value: appState.settings.topAppWindowMinutes,
                unit: "settings.topApps.minutes",
                range: AppSettings.topAppWindowRange,
                step: 1
            ) { appState.settings.topAppWindowMinutes = $0 }
            topAppStepper(
                "settings.topApps.interval.title",
                value: appState.settings.topAppIntervalSeconds,
                unit: "settings.topApps.seconds",
                range: AppSettings.topAppIntervalRange,
                step: 5
            ) { appState.settings.topAppIntervalSeconds = $0 }
            topAppStepper(
                "settings.topApps.limit.title",
                value: appState.settings.topAppLimit,
                unit: nil,
                range: AppSettings.topAppLimitRange,
                step: 1
            ) { appState.settings.topAppLimit = $0 }
        } header: {
            Text("settings.topApps.how")
        } footer: {
            Text("settings.topApps.footer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A small drawing of each chart style: three apps, the busiest first.
    @ViewBuilder
    private func topAppsChartThumbnail(_ style: TopAppsChartStyle) -> some View {
        let shares: [CGFloat] = [1, 0.57, 0.16]
        let values = ["12.4", "7.1", "2.0"]
        switch style {
        case .list:
            VStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 6) {
                        Capsule().fill(Color.primary.opacity(0.22)).frame(width: 30, height: 5)
                        Spacer(minLength: 4)
                        Text(verbatim: values[index])
                            .font(.system(size: 9))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .bars:
            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 64 * shares[index], height: 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .columns:
            HStack(alignment: .bottom, spacing: 9) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 12, height: 34 * shares[index] + 2)
                }
            }
            .frame(height: 38, alignment: .bottom)
        }
    }


    @ViewBuilder
    private var lowPowerSections: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(LowPowerButtonVisibility.allCases) { visibility in
                    SettingsChoiceCard(
                        title: LocalizedStringKey(visibility.localizationKey),
                        selected: appState.settings.lowPowerButtonVisibility == visibility,
                        action: { appState.settings.lowPowerButtonVisibility = visibility }
                    ) {
                        lowPowerButtonsThumbnail(visibility)
                    }
                }
            }
        } header: {
            Text("settings.lowPower.buttons.header")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("tutorial.lowPower.strategy")
                Text("tutorial.lowPower.now")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Section {
            HStack(spacing: 10) {
                ForEach(LowPowerButtonLayout.allCases) { layout in
                    SettingsChoiceCard(
                        title: LocalizedStringKey(layout.localizationKey),
                        selected: appState.settings.lowPowerButtonLayout == layout,
                        action: { appState.settings.lowPowerButtonLayout = layout }
                    ) {
                        lowPowerLayoutThumbnail(layout)
                    }
                }
            }
            .disabled(appState.settings.lowPowerButtonVisibility != .both)
        } header: {
            Text("settings.lowPower.layout.header")
        } footer: {
            Text("settings.lowPower.layout.note")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// The panel's buttons as each choice would show them, with the current strategy's name.
    private func lowPowerButtonsThumbnail(_ visibility: LowPowerButtonVisibility) -> some View {
        let language = appState.settings.language
        let strategy = appState.settings.lowPowerStrategy ?? appState.lowPowerPreset ?? .onlyBattery
        let strategyTitle = Localization.string(strategy.shortLocalizationKey, language: language)
        let lowPowerTitle = Localization.string("popover.lowPower.now", language: language)
        return HStack(spacing: 5) {
            if visibility != .lowPower {
                lowPowerMiniButton(strategyTitle, symbol: "chevron.down", symbolFirst: false)
            }
            if visibility != .strategy {
                lowPowerMiniButton(lowPowerTitle, symbol: "", symbolFirst: true)
            }
        }
    }

    /// Match the panel's inactive low-power button in the settings preview.
    private var lowPowerBatteryGlyph: some View {
        Image(systemName: "battery.25percent")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 10)
            .accessibilityHidden(true)
    }

    private func lowPowerMiniButton(_ title: String, symbol: String, symbolFirst: Bool) -> some View {
        HStack(spacing: 3) {
            if symbolFirst {
                lowPowerBatteryGlyph
            }
            Text(verbatim: title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !symbolFirst {
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .bold))
            }
        }
        .font(.system(size: 10))
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 22)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func lowPowerLayoutThumbnail(_ layout: LowPowerButtonLayout) -> some View {
        let block = RoundedRectangle(cornerRadius: 5, style: .continuous)
        switch layout {
        case .fitTwoPerRow:
            HStack(spacing: 6) {
                block.fill(Color.primary.opacity(0.09)).frame(height: 20)
                block.fill(Color.primary.opacity(0.09)).frame(height: 20)
            }
        case .alwaysOnePerRow:
            VStack(spacing: 5) {
                block.fill(Color.primary.opacity(0.09)).frame(height: 16)
                block.fill(Color.primary.opacity(0.09)).frame(height: 16)
            }
        }
    }


    @ViewBuilder
    private var batteryCycleSections: some View {
        Section {
            SettingsPreviewCard(title: "settings.preview.panel") {
                cycleTutorialPreview
            }
        }
        Section {
            HStack(spacing: 10) {
                ForEach(BatteryCapacityStyle.allCases) { style in
                    SettingsChoiceCard(
                        title: LocalizedStringKey(style.localizationKey),
                        selected: appState.settings.batteryCapacityStyle == style,
                        action: { appState.settings.batteryCapacityStyle = style }
                    ) {
                        Text(verbatim: capacitySample(style))
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
        } header: {
            Text("settings.batteryCycle.format")
        }
    }

    /// The capacity the panel would show in each format, from this Mac's battery when it has one.
    private func capacitySample(_ style: BatteryCapacityStyle) -> String {
        let full = appState.snapshot.fullChargeMilliAmpHours ?? 4820
        let design = appState.snapshot.designCapacityMilliAmpHours ?? 5400
        let percent = design > 0 ? Int((Double(full) / Double(design) * 100).rounded()) : 100
        let milliampHours = "\(full.formatted()) mAh"
        switch style {
        case .percent: return "\(percent)%"
        case .milliampHours: return milliampHours
        case .both: return "\(percent)% · \(full.formatted())"
        }
    }

    private func speedHalfStepper(
        _ title: LocalizedStringKey,
        kilobytes: Int,
        set: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            Text(NetworkRateFormat.midpointLabel(kilobytesPerSecond: kilobytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper(
                title,
                value: Binding(get: { kilobytes }, set: set),
                in: AppSettings.halfSpeedRange,
                step: 64
            )
            .labelsHidden()
            .fixedSize()
        }
    }


    private func topAppStepper(
        _ title: LocalizedStringKey,
        caption: LocalizedStringKey? = nil,
        value: Int,
        unit: LocalizedStringKey?,
        range: ClosedRange<Int>,
        step: Int,
        set: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            SettingsRowLabel(title: title, caption: caption)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text("\(value)")
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                }
            }
            .foregroundStyle(.secondary)
            Stepper(title, value: Binding(get: { value }, set: set), in: range, step: step)
                .labelsHidden()
                .fixedSize()
        }
    }


    @ViewBuilder
    private var aboutSections: some View {
        let language = appState.settings.language
        Section {
            VStack(spacing: 6) {
                SettingsAppIcon(size: 72)
                Text(verbatim: "MacPower")
                    .font(.system(size: 20, weight: .bold))
                Text(versionLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }

        Section {
            SettingsLinkRow(
                title: "GitHub",
                caption: Localization.string("settings.about.github.caption", language: language),
                url: UpdateChecker.githubRepoURL
            ) {
                Image("GitHubMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: 13, height: 13)
                    .frame(width: 22, height: 22)
                    .background(Color(white: 0.12).gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            SettingsLinkRow(
                title: "Gitee",
                caption: Localization.string("settings.about.gitee.caption", language: language),
                url: UpdateChecker.giteeRepoURL
            ) {
                SettingsRowTile(symbol: "g.circle.fill", color: Color(red: 0.78, green: 0.11, blue: 0.14))
            }
            SettingsLinkRow(
                title: Localization.string("settings.about.star", language: language),
                caption: nil,
                url: UpdateChecker.githubRepoURL
            ) {
                SettingsRowTile(symbol: "star.fill", color: Color(red: 0.98, green: 0.70, blue: 0.10))
            }
            Button {
                showingAuthorSupport = true
            } label: {
                SettingsLeadingRow(
                    title: Localization.string("settings.about.tip", language: language),
                    caption: Localization.string("settings.about.tip.caption", language: language),
                    trailingSymbol: "chevron.right"
                ) {
                    SettingsRowTile(symbol: "cup.and.saucer.fill", color: Color(red: 1, green: 0.37, blue: 0.36))
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingAuthorSupport, arrowEdge: .trailing) {
                authorSupportPopover
                    .environment(\.locale, appState.settings.resolvedLocale)
            }
        }
    }

    private var authorSupportPopover: some View {
        VStack(spacing: 16) {
            aboutLink(
                title: Localization.string("settings.about.coffee", language: appState.settings.language),
                url: UpdateChecker.koFiURL
            ) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 1, green: 0.37, blue: 0.36))
            }
            HStack(alignment: .top, spacing: 12) {
                paymentCode(image: "WeChatPay", titleKey: "settings.about.wechat")
                paymentCode(image: "Alipay", titleKey: "settings.about.alipay")
            }
        }
        .padding(16)
        .frame(width: 460)
    }

    private func aboutLink<Icon: View>(title: String, url: URL, @ViewBuilder icon: () -> Icon) -> some View {
        Link(destination: url) {
            aboutChrome(title: title, icon: icon)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func aboutChrome<Icon: View>(title: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 7) {
            icon()
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func paymentCode(image: String, titleKey: String) -> some View {
        let title = Localization.string(titleKey, language: appState.settings.language)
        return VStack(spacing: 8) {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 236)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var menuBarSections: some View {
        Section {
            SettingsPreviewCard(title: "settings.menuBar.preview.current") {
                VStack(spacing: 12) {
                    menuBarStripPreview
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.menuBar.preview.levels")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        menuBarLevelsPreview
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        Section {
            Picker("settings.icon.border", selection: $appState.settings.iconOutlined) {
                Text("settings.icon.border.off").tag(false)
                Text("settings.icon.border.on").tag(true)
            }
            .pickerStyle(.segmented)
            Picker("settings.icon.digits", selection: $appState.settings.digitPlacement) {
                ForEach(MenuBarDigitPlacement.allCases) { placement in
                    Text(LocalizedStringKey(placement.localizationKey)).tag(placement)
                }
            }
            .pickerStyle(.segmented)
            Toggle(isOn: $appState.settings.showChargeGlyphs) {
                SettingsRowLabel(title: "settings.icon.chargeGlyphs", caption: "settings.icon.chargeGlyphs.caption")
            }
        } header: {
            Text("settings.icon.header")
        }

        Section {
            menuBarPresetStatusRow
            menuBarPresetGallery
            if appState.settings.menuBarTint.preset != .off {
                Toggle(isOn: menuBarOnBatteryOnlyBinding) {
                    SettingsRowLabel(
                        title: "settings.icon.tint.onBatteryOnly",
                        caption: "settings.icon.tint.onBatteryOnly.caption"
                    )
                }
                menuBarRampRow
            }
        } header: {
            Text("settings.color.header")
        } footer: {
            if appState.settings.menuBarTint.preset == .off {
                Text("settings.icon.tint.offNote")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A slice of the menu bar over a soft wallpaper, with the real status icon in it.
    private var menuBarStripPreview: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: "wifi")
            Image(systemName: "switch.2")
            menuBarStatusIcon
            Text(Date(), format: .dateTime.weekday(.abbreviated).hour().minute())
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 26)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.62, blue: 0.94),
                    Color(red: 0.74, green: 0.62, blue: 0.93),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private struct MenuBarLevelSample: Identifiable {
        var id: String
        var percent: Double
        var flowMode: EnergyFlowMode
    }

    private var menuBarLevelSamples: [MenuBarLevelSample] {
        [
            MenuBarLevelSample(id: "5", percent: 5, flowMode: .discharging),
            MenuBarLevelSample(id: "15", percent: 15, flowMode: .discharging),
            MenuBarLevelSample(id: "50", percent: 50, flowMode: .discharging),
            MenuBarLevelSample(id: "100", percent: 100, flowMode: .discharging),
            MenuBarLevelSample(id: "charging", percent: 60, flowMode: .charging),
        ]
    }

    private var menuBarLevelsPreview: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(menuBarLevelSamples) { sample in
                VStack(spacing: 6) {
                    menuBarGlyph(percent: sample.percent, flowMode: sample.flowMode, scheme: appState.settings.menuBarTint, scale: 1.35)
                    Group {
                        if sample.flowMode == .charging {
                            Text("settings.menuBar.preview.charging")
                        } else {
                            Text(verbatim: "\(Int(sample.percent))%")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .id(colorScheme)
    }

    /// The battery exactly as the status item would draw it with `scheme`.
    private func menuBarGlyph(percent: Double, flowMode: EnergyFlowMode, scheme: MenuBarTintScheme, scale: CGFloat) -> some View {
        let appearance = NSApp.effectiveAppearance
        let snapshot = tutorialPowerSnapshot(percent: percent, flowMode: flowMode)
        let fill = scheme.fill(percent: percent, flowMode: flowMode, appearance: appearance)
        let style = appState.settings.iconStyle
        let image = MenuBarBatteryRenderer.image(
            snapshot: snapshot,
            style: style,
            fill: fill,
            appearance: appearance,
            showChargeGlyphs: appState.settings.showChargeGlyphs
        )
        return HStack(spacing: 2) {
            Image(nsImage: image)
                .renderingMode(fill.isTemplate ? .template : .original)
                .resizable()
                .interpolation(.high)
                .frame(width: image.size.width * scale, height: image.size.height * scale)
            if style.showsPercentBeside {
                Text(verbatim: "\(Int(percent))%")
                    .font(.system(size: 11 * scale, weight: .medium))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.primary)
        .frame(height: 16 * scale + 2)
    }

    private var menuBarSavedPreset: SavedTintPreset<MenuBarTintScheme>? {
        guard let id = appState.settings.menuBarActiveSavedID else { return nil }
        return appState.settings.savedTintLibrary.menuBar.first { $0.id == id }
    }

    private var menuBarSavedPresetModified: Bool {
        guard let saved = menuBarSavedPreset else { return false }
        let current = appState.settings.menuBarTint
        return saved.payload.bands != current.bands || saved.payload.mode != current.mode
    }

    private var menuBarPresetStatus: String {
        let language = appState.settings.language
        let tint = appState.settings.menuBarTint
        if let saved = menuBarSavedPreset {
            return menuBarSavedPresetModified
                ? Localization.string("settings.tint.status.modified %@", language: language, saved.name)
                : saved.name
        }
        if tint.preset != .custom {
            return Localization.string(tint.preset.localizationKey, language: language)
        }
        if let origin = menuBarTintOrigin {
            let name = Localization.string(origin.localizationKey, language: language)
            return Localization.string("settings.tint.status.modified %@", language: language, name)
        }
        return Localization.string("settings.icon.tint.custom", language: language)
    }

    private var menuBarCanRevert: Bool {
        if menuBarSavedPreset != nil { return menuBarSavedPresetModified }
        return appState.settings.menuBarTint.preset == .custom && menuBarTintOrigin != nil
    }

    private var menuBarPresetStatusRow: some View {
        tintPresetStatusRow(
            status: menuBarPresetStatus,
            canRevert: menuBarCanRevert,
            onRevert: {
                menuBarEditingBandID = nil
                if let saved = menuBarSavedPreset {
                    appState.settings.applySavedMenuBarTint(id: saved.id)
                } else if let origin = menuBarTintOrigin {
                    appState.settings.applyTintPreset(origin)
                }
            },
            canSave: menuBarSavedPresetModified,
            onSave: { _ = appState.settings.updateMenuBarTintPreset() },
            onSaveAs: {
                savePresetName = defaultSaveName(for: .menuBar)
                saveDialog = .menuBar
            },
            onDelete: menuBarSavedPreset == nil ? nil : {
                if let saved = menuBarSavedPreset {
                    appState.settings.deleteSavedMenuBarTint(id: saved.id)
                }
            }
        )
    }

    /// Save, save as, and delete for an icon pack, on one trailing row.
    private func iconPresetActions(
        canOverwrite: Bool,
        onSave: @escaping () -> Void,
        onSaveAs: @escaping () -> Void,
        deleteID: UUID?,
        onDelete: @escaping (UUID) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if canOverwrite {
                Button("settings.tint.save", action: onSave)
            }
            Button("settings.tint.saveAsPreset", action: onSaveAs)
            if let deleteID {
                Button {
                    onDelete(deleteID)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(Localization.string("settings.tint.delete", language: appState.settings.language))
                .accessibilityLabel(Text("settings.tint.delete"))
            }
        }
    }

    /// "Preset  Sunset · Edited" with the actions that make sense right now.
    private func tintPresetStatusRow(
        status: String,
        canRevert: Bool,
        onRevert: @escaping () -> Void,
        canSave: Bool,
        onSave: @escaping () -> Void,
        onSaveAs: @escaping () -> Void,
        onDelete: (() -> Void)?
    ) -> some View {
        HStack(spacing: 8) {
            Text("settings.tint.presetLabel")
            Text(status)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if canRevert {
                Button("settings.tint.revert", action: onRevert)
            }
            if canSave {
                Button("settings.tint.save", action: onSave)
            }
            Button("settings.tint.saveAsPreset", action: onSaveAs)
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(Localization.string("settings.tint.delete", language: appState.settings.language))
                .accessibilityLabel(Text("settings.tint.delete"))
            }
        }
    }

    private static let featuredMenuBarPresets: [MenuBarTintPreset] = [
        .systemDefault, .defaultSlide, .defaultGradient, .batteryLevel, .smoothLevel,
        .sunset, .ocean, .aurora, .lava, .off,
    ]

    private var menuBarPresetGallery: some View {
        let language = appState.settings.language
        let tint = appState.settings.menuBarTint
        let savedID = appState.settings.menuBarActiveSavedID
        let allPresets = MenuBarTintPreset.pickerCases.filter { $0 != .custom }
        let saved = appState.settings.savedTintLibrary.menuBar
        let needsAll = savedID != nil || (tint.preset != .custom && !Self.featuredMenuBarPresets.contains(tint.preset))
        let expanded = showsAllMenuBarPresets || needsAll
        let presets = expanded ? allPresets : Self.featuredMenuBarPresets
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(presets) { preset in
                    TintPresetChip(
                        title: Localization.string(preset.localizationKey, language: language),
                        selected: savedID == nil && tint.preset == preset
                    ) {
                        menuBarEditingBandID = nil
                        menuBarTintOrigin = preset
                        appState.settings.applyTintPreset(preset)
                    } thumbnail: {
                        TintRampBar(bands: MenuBarTintScheme.preset(preset).bands)
                    }
                }
            }
            if expanded, !saved.isEmpty {
                Text("settings.tint.myPresets")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(saved) { item in
                        TintPresetChip(title: item.name, selected: savedID == item.id) {
                            menuBarEditingBandID = nil
                            menuBarTintOrigin = nil
                            appState.settings.applySavedMenuBarTint(id: item.id)
                        } thumbnail: {
                            TintRampBar(bands: item.payload.bands)
                        }
                    }
                }
            }
            if !needsAll {
                Button {
                    showsAllMenuBarPresets.toggle()
                } label: {
                    if expanded {
                        Text("settings.tint.showFewer")
                    } else if saved.isEmpty {
                        Text(Localization.string("settings.tint.showAll %lld", language: language, allPresets.count))
                    } else {
                        Text(Localization.string("settings.tint.showAllAndMine %lld", language: language, allPresets.count))
                    }
                }
                .buttonStyle(.link)
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    private var menuBarOnBatteryOnlyBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.menuBarTint.mode == .onBattery },
            set: { onBatteryOnly in
                var scheme = appState.settings.menuBarTint.markedCustom()
                scheme.mode = onBatteryOnly ? .onBattery : .always
                appState.settings.menuBarTint = scheme
            }
        )
    }

    private var menuBarTransitionBinding: Binding<TintTransition?> {
        Binding(
            get: { TintRamp.transition(of: appState.settings.menuBarTint.bands) },
            set: { transition in
                guard let transition else { return }
                setMenuBarBands(TintRamp.applying(transition, to: appState.settings.menuBarTint.bands))
            }
        )
    }

    private func setMenuBarBands(_ bands: [MenuBarTintBand]) {
        var scheme = appState.settings.menuBarTint.markedCustom()
        scheme.bands = bands
        appState.settings.menuBarTint = scheme.normalized()
    }

    private var menuBarRampRow: some View {
        let bands = appState.settings.menuBarTint.bands
        let language = appState.settings.language
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("settings.icon.tint.byCharge")
                Spacer(minLength: 8)
                Text("settings.tint.transition")
                    .foregroundStyle(.secondary)
                Picker("settings.tint.transition", selection: menuBarTransitionBinding) {
                    ForEach(TintTransition.allCases) { transition in
                        Text(LocalizedStringKey(transition.localizationKey)).tag(Optional(transition))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            TintRampEditor(
                bands: bands,
                followLabel: "settings.tint.menuBarDefault",
                language: language,
                editingID: $menuBarEditingBandID,
                onChange: setMenuBarBands
            ) { band, lower in
                menuBarSegmentEditor(band, lower: lower)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("settings.tint.ramp.hint")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    if let result = TintRamp.addingBoundary(to: bands) {
                        setMenuBarBands(result.bands)
                        menuBarEditingBandID = result.newID
                    }
                } label: {
                    Label("settings.tint.addBoundary", systemImage: "plus")
                }
                .disabled(bands.count >= 8)
            }
        }
        .padding(.vertical, 4)
    }

    private func menuBarSegmentEditor(_ band: MenuBarTintBand, lower: Int) -> some View {
        let ordered = TintRamp.sorted(appState.settings.menuBarTint.bands)
        let index = ordered.firstIndex { $0.id == band.id }
        let previous = index.flatMap { $0 > 0 ? ordered[$0 - 1] : nil }
        return TintSegmentEditor(
            band: band,
            lower: lower,
            previous: previous,
            language: appState.settings.language,
            rangeKey: "settings.tint.segment.range %lld %lld",
            captionKey: "settings.tint.segment.caption",
            atKey: "settings.tint.color.at %lld",
            followName: "settings.tint.menuBarDefault",
            followNote: "settings.tint.menuBarDefault.note",
            canDelete: ordered.count > 1,
            upperRange: index.flatMap { $0 < ordered.count - 1 ? TintRamp.boundaryRange(at: $0, in: ordered) : nil },
            onSetUpper: { setMenuBarBands(TintRamp.moving(band.id, to: $0, in: appState.settings.menuBarTint.bands)) },
            onChange: { next in
                setMenuBarBands(TintRamp.replacing(next, in: appState.settings.menuBarTint.bands))
            },
            onDelete: {
                menuBarEditingBandID = nil
                setMenuBarBands(TintRamp.removing(band.id, from: appState.settings.menuBarTint.bands))
            }
        ) {
            menuBarSegmentPreview(band, lower: lower)
        }
    }

    /// The icon at the bottom and top of a segment, so the effect is visible at a glance.
    private func menuBarSegmentPreview(_ band: MenuBarTintBand, lower: Int) -> some View {
        var scheme = appState.settings.menuBarTint.markedCustom()
        scheme.mode = .always
        let low = Double(min(band.throughPercent, lower + 1))
        let high = Double(band.throughPercent)
        return HStack(spacing: 4) {
            if band.blend.slides, low < high {
                menuBarGlyph(percent: low, flowMode: .discharging, scheme: scheme, scale: 1.2)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            menuBarGlyph(percent: high, flowMode: .discharging, scheme: scheme, scale: 1.2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private var ringsSections: some View {
        Section {
            SettingsPreviewCard(title: "settings.rings.preview") {
                ringsPanelPreview
            }
            .task {
                // Headphone levels are read only while the panel is open; read once for the preview.
                if !appState.settings.bluetoothRingDevices.isEmpty {
                    await appState.refreshBluetoothNow()
                }
            }
        }

        ForEach(Array(appState.settings.ringRows.enumerated()), id: \.offset) { rowIndex, row in
            Section {
                ringRowItems(rowIndex: rowIndex, row: row)
            } header: {
                ringRowHeader(rowIndex)
            }
        }
        ringHiddenSection
        Section {
            HStack(spacing: 10) {
                Button {
                    appState.settings.addRingRow()
                } label: {
                    Label("settings.rings.addRow", systemImage: "plus")
                }
                Button {
                    showingBluetoothDevices = true
                } label: {
                    Label("settings.rings.bluetooth.addDevice", systemImage: "headphones")
                }
                Spacer(minLength: 0)
            }
            Picker("settings.rings.oddRow.title", selection: $appState.settings.ringOddRow) {
                Text("settings.rings.oddAlign.title").tag(RingOddRow.align)
                Text("settings.rings.oddStagger.title").tag(RingOddRow.stagger)
            }
            .pickerStyle(.segmented)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("settings.rings.dragHint")
                Text("settings.rings.bluetooth.connectHint")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingBluetoothDevices, onDismiss: {
            appState.bluetoothScanWanted = false
        }) {
            BluetoothDevicePicker(appState: appState)
                .onAppear {
                    appState.bluetoothScanWanted = true
                    Task { await appState.refreshBluetoothNow() }
                }
        }

        Section {
            tintPresetStatusRow(
                status: ringPresetStatus,
                canRevert: ringCanRevert,
                onRevert: revertRingTint,
                canSave: ringSavedPresetModified,
                onSave: { _ = appState.settings.updateRingTintPreset() },
                onSaveAs: {
                    savePresetName = defaultSaveName(for: .ring)
                    saveDialog = .ring
                },
                onDelete: ringSavedPreset == nil ? nil : {
                    if let saved = ringSavedPreset {
                        appState.settings.deleteSavedRingTint(id: saved.id)
                    }
                }
            )
            ringPresetGallery
            ringColorList
            if let color = selectedRingColor() {
                ringColorRampRow(color)
            }
        } header: {
            Text("settings.color.header")
        } footer: {
            Text("settings.rings.colors.footer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        Section {
            speedHalfStepper(
                "settings.rings.half.download.title",
                kilobytes: appState.settings.downloadHalfKilobytes
            ) { appState.settings.downloadHalfKilobytes = $0 }
            speedHalfStepper(
                "settings.rings.half.upload.title",
                kilobytes: appState.settings.uploadHalfKilobytes
            ) { appState.settings.uploadHalfKilobytes = $0 }
            temperatureHalfStepper(title: "settings.rings.half.temperature.title")
            HStack(spacing: 8) {
                SettingsRowLabel(title: "settings.rings.half.swap.title", caption: "settings.rings.half.swap.caption")
                Spacer(minLength: 8)
                Text(SwapUsageFormat.string(bytes: Double(appState.settings.swapHalfMegabytes) * 1_048_576))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(
                    "settings.rings.half.swap.title",
                    value: Binding(
                        get: { appState.settings.swapHalfMegabytes },
                        set: { appState.settings.swapHalfMegabytes = $0 }
                    ),
                    in: AppSettings.swapHalfLimit(),
                    step: AppSettings.swapHalfStep
                )
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 8) {
                SettingsRowLabel(title: "settings.rings.half.compressor.title", caption: "settings.rings.half.compressor.caption")
                Spacer(minLength: 8)
                Text(SwapUsageFormat.string(bytes: Double(appState.settings.compressorHalfMegabytes) * 1_048_576))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(
                    "settings.rings.half.compressor.title",
                    value: Binding(
                        get: { appState.settings.compressorHalfMegabytes },
                        set: { appState.settings.compressorHalfMegabytes = $0 }
                    ),
                    in: AppSettings.swapHalfLimit(),
                    step: AppSettings.swapHalfStep
                )
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 8) {
                SettingsRowLabel(title: "settings.rings.half.overflow.title", caption: "settings.rings.half.overflow.caption")
                Spacer(minLength: 8)
                Text(SwapUsageFormat.string(bytes: Double(appState.settings.overflowHalfMegabytes) * 1_048_576))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(
                    "settings.rings.half.overflow.title",
                    value: Binding(
                        get: { appState.settings.overflowHalfMegabytes },
                        set: { appState.settings.overflowHalfMegabytes = $0 }
                    ),
                    in: AppSettings.swapHalfLimit(),
                    step: AppSettings.swapHalfStep
                )
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.rings.thermal.title")
                    Text(verbatim: thermalScaleSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("settings.rings.thermal.adjust") {
                    ringScaleSlot = .thermalState
                }
                .popover(isPresented: ringScalePresented(.thermalState), arrowEdge: .bottom) {
                    ringScalePopover(.thermalState)
                        .environment(\.locale, appState.settings.resolvedLocale)
                }
            }
            Picker("settings.rings.temperatureUnit", selection: $appState.settings.temperatureUnit) {
                ForEach(TemperatureUnit.allCases) { unit in
                    Text(LocalizedStringKey(unit.localizationKey)).tag(unit)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("settings.rings.scale.header")
        } footer: {
            Text("settings.rings.scale.footer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            VStack(spacing: 16) {
                let slots = RingSlot.iconSlots
                ringIconSlotRow(Array(slots.prefix(4)))
                ringIconSlotRow(Array(slots.dropFirst(4).prefix(4)))
                ringIconSlotRow(Array(slots.dropFirst(8)))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            iconPresetActions(
                canOverwrite: appState.settings.ringActiveSavedIconID != nil,
                onSave: { _ = appState.settings.updateRingIconPreset() },
                onSaveAs: {
                    savePresetName = defaultSaveName(for: .ringIcon)
                    saveDialog = .ringIcon
                },
                deleteID: appState.settings.ringActiveSavedIconID,
                onDelete: { appState.settings.deleteSavedRingIcon(id: $0) }
            )
            bluetoothIconSettings
            ForEach([RingSlot.batteryTemperature, .thermalState]) { slot in
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(slot.localizationKey))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    slotIconColorControls(slot)
                }
            }
        } header: {
            Text("settings.icon.header")
        } footer: {
            Text("settings.icons.footer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// The panel's ring grid exactly as the panel draws it, with live readings.
    /// A row too wide for this column is scaled down to fit.
    private var ringsPanelPreview: some View {
        let rows = appState.settings.displayedRingRows(seen: appState.bluetoothDevices)
        let gear = appState.settings.settingsButtonPlacement.drawsRingGear(
            host: appState.settings.settingsButtonHost,
            ringsVisible: appState.settings.showStatusRings
        )
        var counts = rows.map(\.count)
        if gear {
            if counts.isEmpty { counts = [1] } else { counts[counts.count - 1] += 1 }
        }
        let width = PopoverLayout.width(rowCounts: counts) - PopoverLayout.padding * 2
        let shownRows = counts.filter { $0 > 0 }.count
        let height = CGFloat(shownRows) * (StatusRingView.diameter + 24) + CGFloat(max(shownRows - 1, 0)) * 10
        let scale = min(1, 420 / max(width, 1))
        return Group {
            if counts.allSatisfy({ $0 == 0 }) {
                Text("settings.rings.preview.empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                RingHeaderLayout(rowCounts: counts) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        ForEach(row) { item in
                            RingItemCell(appState: appState, item: item)
                        }
                    }
                    if gear {
                        RingSettingsCell(title: Localization.string("settings.title", language: appState.settings.language))
                    }
                }
                .frame(width: width, height: height, alignment: .top)
                .scaleEffect(scale)
                .frame(width: width * scale, height: height * scale)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private func ringIsShown(_ item: RingItem) -> Bool {
        guard let slot = item.slot else { return true }
        return appState.settings.enabledRingSlots.contains(slot)
    }

    private func ringRowHeader(_ rowIndex: Int) -> some View {
        HStack(spacing: 8) {
            Text("settings.rings.row \(rowIndex + 1)")
            Spacer(minLength: 8)
            if appState.settings.ringRows.count > 1 {
                Button("settings.rings.removeRow") {
                    appState.settings.removeRingRow(rowIndex)
                }
                .buttonStyle(.link)
                .font(.subheadline)
            }
        }
        .onDrop(of: [.plainText], delegate: RingItemRowDropDelegate(
            row: rowIndex,
            drag: ringItemDrag,
            move: { id, row in appState.settings.moveRingItem(id: id, toEndOfRow: row) }
        ))
    }

    @ViewBuilder
    private func ringRowItems(rowIndex: Int, row: [RingItem]) -> some View {
        let shown = row.filter(ringIsShown)
        if shown.isEmpty {
            Text("settings.rings.row.empty")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .onDrop(of: [.plainText], delegate: RingItemRowDropDelegate(
                    row: rowIndex,
                    drag: ringItemDrag,
                    move: { id, row in appState.settings.moveRingItem(id: id, toEndOfRow: row) }
                ))
        }
        ForEach(shown) { item in
            ringShownRow(item, rowIndex: rowIndex)
        }
    }

    private func ringShownRow(_ item: RingItem, rowIndex: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .onDrag {
                    ringItemDrag.itemID = item.id
                    return NSItemProvider(object: item.id as NSString)
                }
                .help(Localization.string("settings.rings.dragHint", language: appState.settings.language))
            ringItemIcon(item)
            VStack(alignment: .leading, spacing: 1) {
                Text(ringItemTitle(item))
                    .lineLimit(1)
                if let caption = ringItemCaption(item) {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if item.slot == .speedPair {
                ringColorPicker(.download, symbol: "arrow.down")
                ringColorPicker(.upload, symbol: "arrow.up")
            } else if let slot = item.slot, let segment = RingColorSegment(rawValue: slot.rawValue) {
                ringColorPicker(segment)
            }
            if item.slot == nil {
                Button("settings.rings.bluetooth.options") {
                    ringOptionsItemID = item.id
                }
                .popover(isPresented: Binding(
                    get: { ringOptionsItemID == item.id },
                    set: { if !$0, ringOptionsItemID == item.id { ringOptionsItemID = nil } }
                ), arrowEdge: .bottom) {
                    ringBluetoothOptions(item)
                        .environment(\.locale, appState.settings.resolvedLocale)
                }
            }
            ringMoveMenu(item, rowIndex: rowIndex)
        }
        .contentShape(Rectangle())
        .onDrop(of: [.plainText], delegate: RingItemDropDelegate(
            itemID: item.id,
            drag: ringItemDrag,
            move: { id, target in appState.settings.moveRingItem(id: id, to: target) }
        ))
    }

    private func ringItemIcon(_ item: RingItem) -> some View {
        let glyph: GlyphSlot = {
            if let slot = item.slot {
                return slot == .speedPair ? .system("arrow.up.arrow.down") : appState.settings.ringIcons.slot(for: slot)
            }
            let device = appState.settings.bluetoothRingDevices.first { $0.address == item.address }
            let ring = device?.rings.first { $0.id == item.ringID }
            return ring?.shownGlyph(model: device?.model ?? .generic, parts: ring?.parts ?? []) ?? .system("headphones")
        }()
        return GlyphSlotView(slot: glyph, systemPointSize: 12, assetSide: 15, prefersMonochrome: true)
            .frame(width: 24, height: 24)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }

    private func ringItemCaption(_ item: RingItem) -> String? {
        let language = appState.settings.language
        if item.slot == nil {
            return Localization.string("settings.rings.bluetooth.caption", language: language)
        }
        if item.slot == .speedPair {
            return Localization.string("settings.rings.speedPair.caption", language: language)
        }
        return nil
    }

    private func ringColorPicker(_ segment: RingColorSegment, symbol: String? = nil) -> some View {
        let tint = appState.settings.ringTint
        let colors = tint.colors
        let current = tint.assignments[segment] ?? colors.first?.id
        let currentScheme = colors.first { $0.id == current }?.scheme
        return HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if let currentScheme {
                TintRampBar(bands: currentScheme.bands, cornerRadius: 2)
                    .frame(width: 18, height: 8)
            }
            Picker(LocalizedStringKey(segment.localizationKey), selection: Binding(
                get: { current ?? UUID() },
                set: { id in
                    appState.settings.ringTint = appState.settings.ringTint.assigning(segment, to: id)
                }
            )) {
                ForEach(Array(colors.enumerated()), id: \.element.id) { index, item in
                    Text(ringColorTitle(index)).tag(item.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
        .help(Localization.string("settings.rings.color.pick", language: appState.settings.language))
    }

    private func ringMoveMenu(_ item: RingItem, rowIndex: Int) -> some View {
        let rowCount = appState.settings.ringRows.count
        return Menu {
            ForEach(0..<rowCount, id: \.self) { index in
                if index != rowIndex {
                    Button(Localization.string("settings.rings.moveToRow %lld", language: appState.settings.language, index + 1)) {
                        appState.settings.moveRingItem(id: item.id, toEndOfRow: index)
                    }
                }
            }
            Button("settings.rings.moveToNewRow") {
                moveRingItemToNewRow(item.id)
            }
            Divider()
            if let slot = item.slot {
                Button("settings.rings.hide") {
                    appState.settings.setRingSlot(slot, visible: false)
                }
            } else if let address = item.address {
                Button("settings.rings.bluetooth.remove", role: .destructive) {
                    appState.settings.removeBluetoothDevice(address: address)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Localization.string("settings.rings.more", language: appState.settings.language))
    }

    private func moveRingItemToNewRow(_ id: String) {
        appState.settings.addRingRow()
        appState.settings.moveRingItem(id: id, toEndOfRow: appState.settings.ringRows.count - 1)
    }

    /// Shows a hidden ring at the end of a row, or on a row of its own.
    private func showRing(_ slot: RingSlot, inRow row: Int?) {
        let settings = appState.settings
        settings.setRingSlot(slot, visible: true)
        let id = RingItem.slot(slot).id
        if let row {
            settings.moveRingItem(id: id, toEndOfRow: row)
        } else {
            moveRingItemToNewRow(id)
        }
    }

    @ViewBuilder
    private var ringHiddenSection: some View {
        let hidden = appState.settings.ringCatalog.filter { !appState.settings.enabledRingSlots.contains($0) }
        if !hidden.isEmpty {
            Section {
                ForEach(hidden) { slot in
                    HStack(spacing: 8) {
                        ringItemIcon(.slot(slot))
                            .opacity(0.6)
                        Text(LocalizedStringKey(slot.localizationKey))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Menu {
                            ForEach(0..<appState.settings.ringRows.count, id: \.self) { index in
                                Button(Localization.string("settings.rings.addToRow %lld", language: appState.settings.language, index + 1)) {
                                    showRing(slot, inRow: index)
                                }
                            }
                            Button("settings.rings.addToNewRow") {
                                showRing(slot, inRow: nil)
                            }
                        } label: {
                            Label("settings.rings.show", systemImage: "plus.circle.fill")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            } header: {
                Text("settings.rings.hiddenGroup")
            }
        }
    }

    @ViewBuilder
    private func ringBluetoothOptions(_ item: RingItem) -> some View {
        if let device = appState.settings.bluetoothRingDevices.first(where: { $0.address == item.address }),
           let ring = device.rings.first(where: { $0.id == item.ringID }) {
            let index = device.rings.firstIndex(where: { $0.id == ring.id }) ?? 0
            let catalog: [BluetoothBatteryPart] = device.multi ? [.left, .right, .box] : []
            VStack(alignment: .leading, spacing: 10) {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                bluetoothRingEditor(device: device, ring: ring, index: index, catalog: catalog)
                if device.rings.count < 3, device.multi {
                    Button("settings.rings.bluetooth.addRing") {
                        appState.settings.addBluetoothDisplayRing(address: device.address)
                    }
                }
            }
            .padding(14)
            .frame(width: 320)
        }
    }

    private var thermalScaleSummary: String {
        let language = appState.settings.language
        let parts = [
            ("ring.thermal.nominal", appState.settings.thermalNominalPercent),
            ("ring.thermal.fair", appState.settings.thermalFairPercent),
            ("ring.thermal.serious", appState.settings.thermalSeriousPercent),
            ("ring.thermal.critical", appState.settings.thermalCriticalPercent),
        ]
        return parts.map { "\(Localization.string($0.0, language: language)) \($0.1)%" }.joined(separator: " · ")
    }

    private var ringSavedPreset: SavedTintPreset<RingTintSettings>? {
        guard let id = appState.settings.ringActiveSavedID else { return nil }
        return appState.settings.savedTintLibrary.ring.first { $0.id == id }
    }

    private var ringSavedPresetModified: Bool {
        guard let saved = ringSavedPreset else { return false }
        let current = appState.settings.ringTint
        return saved.payload.colors != current.colors || saved.payload.assignments != current.assignments
    }

    private var ringPresetStatus: String {
        let language = appState.settings.language
        let tint = appState.settings.ringTint
        if let saved = ringSavedPreset {
            return ringSavedPresetModified
                ? Localization.string("settings.tint.status.modified %@", language: language, saved.name)
                : saved.name
        }
        if tint.preset != .custom {
            return Localization.string(tint.preset.localizationKey, language: language)
        }
        if let origin = ringTintOrigin {
            let name = Localization.string(origin.localizationKey, language: language)
            return Localization.string("settings.tint.status.modified %@", language: language, name)
        }
        return Localization.string("settings.icon.tint.custom", language: language)
    }

    private var ringCanRevert: Bool {
        if ringSavedPreset != nil { return ringSavedPresetModified }
        return appState.settings.ringTint.preset == .custom && ringTintOrigin != nil
    }

    private func revertRingTint() {
        ringEditingBandID = nil
        if let saved = ringSavedPreset {
            appState.settings.applySavedRingTint(id: saved.id)
        } else if let origin = ringTintOrigin {
            appState.settings.applyRingTintPreset(origin)
        }
    }

    private var ringPresetGallery: some View {
        let language = appState.settings.language
        let tint = appState.settings.ringTint
        let savedID = appState.settings.ringActiveSavedID
        let saved = appState.settings.savedTintLibrary.ring
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(PopoverTintPreset.allCases.filter { $0 != .custom }) { preset in
                    TintPresetChip(
                        title: Localization.string(preset.localizationKey, language: language),
                        selected: savedID == nil && tint.preset == preset
                    ) {
                        ringEditingBandID = nil
                        ringTintOrigin = preset
                        appState.settings.applyRingTintPreset(preset)
                    } thumbnail: {
                        ringPresetThumbnail(RingTintSettings.preset(preset))
                    }
                }
            }
            if !saved.isEmpty {
                Text("settings.tint.myPresets")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(saved) { item in
                        TintPresetChip(title: item.name, selected: savedID == item.id) {
                            ringEditingBandID = nil
                            ringTintOrigin = nil
                            appState.settings.applySavedRingTint(id: item.id)
                        } thumbnail: {
                            ringPresetThumbnail(item.payload)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func ringPresetThumbnail(_ tint: RingTintSettings) -> some View {
        HStack(spacing: 2) {
            ForEach(tint.colors.prefix(4)) { color in
                TintRampBar(bands: color.scheme.bands, cornerRadius: 2)
            }
        }
    }

    private func ringColorUsage(_ color: RingColor) -> String {
        let language = appState.settings.language
        let tint = appState.settings.ringTint
        let fallback = tint.colors.first?.id
        let names = RingColorSegment.allCases
            .filter { (tint.assignments[$0] ?? fallback) == color.id }
            .map { Localization.string($0.localizationKey, language: language) }
        guard !names.isEmpty else {
            return Localization.string("settings.rings.color.unused", language: language)
        }
        let formatter = ListFormatter()
        formatter.locale = appState.settings.resolvedLocale
        let list = formatter.string(from: names) ?? names.joined(separator: ", ")
        return Localization.string("settings.rings.color.usedBy %@", language: language, list)
    }

    private var ringColorList: some View {
        let colors = appState.settings.ringTint.colors
        let selected = selectedRingColor()?.id
        return VStack(alignment: .leading, spacing: 6) {
            Text("settings.rings.colors.title")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(colors.enumerated()), id: \.element.id) { index, color in
                    if index > 0 {
                        Divider().padding(.leading, 64)
                    }
                    Button {
                        ringEditingBandID = nil
                        ringColorSelectionID = color.id
                    } label: {
                        HStack(spacing: 10) {
                            TintRampBar(bands: color.scheme.bands)
                                .frame(width: 44, height: 12)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ringColorTitle(index))
                                    .font(.system(size: 13, weight: selected == color.id ? .semibold : .regular))
                                Text(ringColorUsage(color))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            if selected == color.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == color.id ? .isSelected : [])
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            HStack(spacing: 10) {
                Button {
                    let tint = appState.settings.ringTint
                    appState.settings.ringTint = tint.addingColor(copying: selected)
                    ringEditingBandID = nil
                    ringColorSelectionID = appState.settings.ringTint.colors.last?.id
                } label: {
                    Label("settings.rings.color.new", systemImage: "plus")
                }
                if let selected, colors.count > 1 {
                    Button("settings.rings.color.delete", role: .destructive) {
                        let tint = appState.settings.ringTint
                        let fallback = tint.colors.first { $0.id != selected }
                        ringEditingBandID = nil
                        appState.settings.ringTint = tint.removingColor(id: selected)
                        ringColorSelectionID = fallback?.id
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }

    private func setRingColorBands(_ id: UUID, _ bands: [MenuBarTintBand]) {
        let scheme = ValueTintScheme(bands: bands).normalized()
        appState.settings.ringTint = appState.settings.ringTint.updatingColor(id: id, scheme: scheme)
    }

    private func ringColorRampRow(_ color: RingColor) -> some View {
        let language = appState.settings.language
        let bands = color.scheme.bands
        let index = appState.settings.ringTint.colors.firstIndex { $0.id == color.id } ?? 0
        let transition = Binding<TintTransition?>(
            get: { TintRamp.transition(of: bands) },
            set: { next in
                guard let next else { return }
                setRingColorBands(color.id, TintRamp.applying(next, to: bands))
            }
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(Localization.string("settings.rings.color.edit %@", language: language, ringColorTitle(index)))
                Spacer(minLength: 8)
                Text("settings.tint.transition")
                    .foregroundStyle(.secondary)
                Picker("settings.tint.transition", selection: transition) {
                    ForEach(TintTransition.allCases) { item in
                        Text(LocalizedStringKey(item.localizationKey)).tag(Optional(item))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            TintRampEditor(
                bands: bands,
                followLabel: "settings.tint.labelColor",
                language: language,
                editingID: $ringEditingBandID,
                onChange: { setRingColorBands(color.id, $0) }
            ) { band, lower in
                ringValueSegmentEditor(band, lower: lower, bands: bands) { setRingColorBands(color.id, $0) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("settings.rings.ramp.hint")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    if let result = TintRamp.addingBoundary(to: bands) {
                        setRingColorBands(color.id, result.bands)
                        ringEditingBandID = result.newID
                    }
                } label: {
                    Label("settings.tint.addBoundary", systemImage: "plus")
                }
                .disabled(bands.count >= 8)
            }
        }
        .padding(.vertical, 4)
    }

    private func ringValueSegmentEditor(
        _ band: MenuBarTintBand,
        lower: Int,
        bands: [MenuBarTintBand],
        onChange: @escaping ([MenuBarTintBand]) -> Void
    ) -> some View {
        let ordered = TintRamp.sorted(bands)
        let index = ordered.firstIndex { $0.id == band.id }
        let previous = index.flatMap { $0 > 0 ? ordered[$0 - 1] : nil }
        return TintSegmentEditor(
            band: band,
            lower: lower,
            previous: previous,
            language: appState.settings.language,
            rangeKey: "settings.tint.segment.valueRange %lld %lld",
            captionKey: "settings.rings.segment.caption",
            atKey: "settings.tint.color.atValue %lld",
            followName: "settings.tint.labelColor",
            followNote: "settings.tint.labelColor.note",
            canDelete: ordered.count > 1,
            upperRange: index.flatMap { $0 < ordered.count - 1 ? TintRamp.boundaryRange(at: $0, in: ordered) : nil },
            onSetUpper: { onChange(TintRamp.moving(band.id, to: $0, in: bands)) },
            onChange: { next in onChange(TintRamp.replacing(next, in: bands)) },
            onDelete: {
                ringEditingBandID = nil
                onChange(TintRamp.removing(band.id, from: bands))
            }
        ) {
            ringSegmentPreview(band, lower: lower)
        }
    }

    /// A small ring filled to the top of the segment in the segment's colors.
    private func ringSegmentPreview(_ band: MenuBarTintBand, lower: Int) -> some View {
        let scheme = ValueTintScheme(bands: [MenuBarTintBand(
            throughPercent: 100,
            swatch: band.highRight,
            blend: band.blend == .slide || band.blend == .slideGradient ? .constant : band.blend,
            highLeft: band.highLeft
        )])
        let colors = scheme.colors(percent: 100)
        let progress = Double(max(band.throughPercent, 8)) / 100
        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [colors.left, colors.right], center: .center),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 30, height: 30)
        .padding(4)
    }

    @ViewBuilder
    private var flowSections: some View {
        Section {
            SettingsPreviewCard(verbatim: flowPreviewTitle) {
                flowStatePreview
            }
        }

        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("settings.flow.chooseState")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Self.flowModes, id: \.self) { mode in
                        TintPresetChip(
                            title: Localization.string(Self.flowModeKey(mode), language: appState.settings.language),
                            selected: flowEditingMode == mode
                        ) {
                            flowEditingBandID = nil
                            flowEditingMode = mode
                        } thumbnail: {
                            TintRampBar(bands: appState.settings.flowTint.scheme(for: mode).bands)
                        }
                    }
                }
            }
            .padding(.vertical, 4)

            tintPresetStatusRow(
                status: flowPresetStatus,
                canRevert: flowCanRevert,
                onRevert: revertFlowTint,
                canSave: flowSavedPresetModified,
                onSave: { _ = appState.settings.updateFlowTintPreset() },
                onSaveAs: {
                    savePresetName = defaultSaveName(for: .flow)
                    saveDialog = .flow
                },
                onDelete: flowSavedPreset == nil ? nil : {
                    if let saved = flowSavedPreset {
                        appState.settings.deleteSavedFlowTint(id: saved.id)
                    }
                }
            )
            flowPresetGallery
            flowRampRow
            flowMotionColorRow
        } header: {
            Text("settings.color.header")
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
            HStack(alignment: .top, spacing: 10) {
                ForEach(FlowIconRole.allCases) { role in
                    flowIconSlotControl(role)
                }
            }
            .padding(.vertical, 6)
            iconPresetActions(
                canOverwrite: appState.settings.flowActiveSavedIconID != nil,
                onSave: { _ = appState.settings.updateFlowIconPreset() },
                onSaveAs: {
                    savePresetName = defaultSaveName(for: .flowIcon)
                    saveDialog = .flowIcon
                },
                deleteID: appState.settings.flowActiveSavedIconID,
                onDelete: { appState.settings.deleteSavedFlowIcon(id: $0) }
            )
            FlowIconSizeControl(settings: appState.settings)
        } header: {
            Text("settings.icon.header")
        } footer: {
            Text("settings.icons.footer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            Toggle(isOn: $appState.settings.pulseFlowIcons) {
                SettingsRowLabel(title: "settings.motion.pulseIcons", caption: "settings.motion.pulseIcons.note")
            }
        } header: {
            Text("settings.motion.header")
        } footer: {
            Text(LocalizedStringKey(Self.motionNoteKey(appState.settings.motionStyle)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private static let flowModes: [EnergyFlowMode] = [.charging, .discharging, .adapterHold, .underpowered]

    private static func flowModeKey(_ mode: EnergyFlowMode) -> String {
        switch mode {
        case .charging: "settings.flow.tint.charging"
        case .discharging: "settings.flow.tint.discharging"
        case .adapterHold: "settings.flow.tint.hold"
        case .underpowered: "settings.flow.tint.underpowered"
        }
    }

    private static func motionNoteKey(_ style: EnergyMotionStyle) -> String {
        switch style {
        case .sheen: "settings.motion.note.sheen"
        case .filaments, .filamentsSolid, .filamentsWhite: "settings.motion.note.filaments"
        case .particles, .particlesSolid, .particlesWhite: "settings.motion.note.particles"
        case .off: "settings.motion.note.off"
        }
    }

    private var flowPreviewTitle: String {
        let language = appState.settings.language
        let state = Localization.string(Self.flowModeKey(flowEditingMode), language: language)
        return Localization.string("settings.flow.preview %@", language: language, state)
    }

    /// The panel's energy ribbon in the state being edited, at this Mac's charge.
    private var flowStatePreview: some View {
        EnergyFlowView(
            snapshot: flowPreviewSnapshot(flowEditingMode),
            theme: AppTheme.resolved(palette: appState.settings.palette, colorScheme: colorScheme),
            flowTint: appState.settings.flowTint,
            flowIcons: appState.settings.flowIcons,
            isAnimating: false,
            motion: appState.settings.motionStyle,
            motionFrameRate: appState.settings.motionFrameRate,
            pulseFlowIcons: appState.settings.pulseFlowIcons,
            flowIconScale: appState.settings.flowIconScale,
            language: appState.settings.language,
            showsFooter: true
        )
        .frame(width: PopoverLayout.width - PopoverLayout.padding * 2, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func flowPreviewSnapshot(_ mode: EnergyFlowMode) -> PowerSnapshot {
        let live = appState.snapshot
        let percent = live.hasBattery && live.percent >= 1 ? live.percent : 62
        var snapshot = tutorialPowerSnapshot(percent: percent, flowMode: mode)
        switch mode {
        case .charging:
            snapshot.adapterInWatts = 45
            snapshot.systemLoadWatts = 18
            snapshot.batteryWatts = 27
            snapshot.timeToFullMinutes = 72
        case .discharging:
            snapshot.timeToEmptyMinutes = 245
        case .adapterHold:
            snapshot.adapterInWatts = 14
            snapshot.systemLoadWatts = 14
            snapshot.batteryWatts = 0
        case .underpowered:
            snapshot.adapterCeilingWatts = 30
            snapshot.adapterInWatts = 28
            snapshot.systemLoadWatts = 40
            snapshot.batteryWatts = -12
            snapshot.timeToEmptyMinutes = 300
        }
        return snapshot
    }

    private var flowSavedPreset: SavedTintPreset<FlowTintSettings>? {
        guard let id = appState.settings.flowActiveSavedID else { return nil }
        return appState.settings.savedTintLibrary.flow.first { $0.id == id }
    }

    private static func sameFlowColors(_ a: FlowTintSettings, _ b: FlowTintSettings) -> Bool {
        a.charging == b.charging && a.discharging == b.discharging
            && a.adapterHold == b.adapterHold && a.underpowered == b.underpowered
            && a.motionColor == b.motionColor
    }

    private var flowSavedPresetModified: Bool {
        guard let saved = flowSavedPreset else { return false }
        return !Self.sameFlowColors(saved.payload, appState.settings.flowTint)
    }

    private var flowPresetStatus: String {
        let language = appState.settings.language
        let tint = appState.settings.flowTint
        if let saved = flowSavedPreset {
            return flowSavedPresetModified
                ? Localization.string("settings.tint.status.modified %@", language: language, saved.name)
                : saved.name
        }
        if tint.preset != .custom {
            return Localization.string(tint.preset.localizationKey, language: language)
        }
        if let origin = flowTintOrigin {
            let name = Localization.string(origin.localizationKey, language: language)
            return Localization.string("settings.tint.status.modified %@", language: language, name)
        }
        return Localization.string("settings.icon.tint.custom", language: language)
    }

    private var flowCanRevert: Bool {
        if flowSavedPreset != nil { return flowSavedPresetModified }
        return appState.settings.flowTint.preset == .custom && flowTintOrigin != nil
    }

    private func revertFlowTint() {
        flowEditingBandID = nil
        if let saved = flowSavedPreset {
            appState.settings.applySavedFlowTint(id: saved.id)
        } else if let origin = flowTintOrigin {
            appState.settings.applyFlowTintPreset(origin)
        }
    }

    private var flowPresetGallery: some View {
        let language = appState.settings.language
        let tint = appState.settings.flowTint
        let savedID = appState.settings.flowActiveSavedID
        let saved = appState.settings.savedTintLibrary.flow
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(PopoverTintPreset.allCases.filter { $0 != .custom }) { preset in
                    TintPresetChip(
                        title: Localization.string(preset.localizationKey, language: language),
                        selected: savedID == nil && tint.preset == preset
                    ) {
                        flowEditingBandID = nil
                        flowTintOrigin = preset
                        appState.settings.applyFlowTintPreset(preset)
                    } thumbnail: {
                        flowPresetThumbnail(FlowTintSettings.preset(preset))
                    }
                }
            }
            if !saved.isEmpty {
                Text("settings.tint.myPresets")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(saved) { item in
                        TintPresetChip(title: item.name, selected: savedID == item.id) {
                            flowEditingBandID = nil
                            flowTintOrigin = nil
                            appState.settings.applySavedFlowTint(id: item.id)
                        } thumbnail: {
                            flowPresetThumbnail(item.payload)
                        }
                    }
                }
            }
            Text("settings.flow.presetOrder")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    /// Four short bars, one per state, in the order the state cards use.
    private func flowPresetThumbnail(_ tint: FlowTintSettings) -> some View {
        HStack(spacing: 2) {
            ForEach(Self.flowModes, id: \.self) { mode in
                TintRampBar(bands: tint.scheme(for: mode).bands, cornerRadius: 2)
            }
        }
    }

    private func setFlowBands(_ bands: [MenuBarTintBand]) {
        let scheme = ValueTintScheme(bands: bands).normalized()
        appState.settings.flowTint = appState.settings.flowTint.replacing(flowEditingMode, with: scheme)
    }

    private var flowTransitionBinding: Binding<TintTransition?> {
        Binding(
            get: { TintRamp.transition(of: appState.settings.flowTint.scheme(for: flowEditingMode).bands) },
            set: { transition in
                guard let transition else { return }
                setFlowBands(TintRamp.applying(transition, to: appState.settings.flowTint.scheme(for: flowEditingMode).bands))
            }
        )
    }

    private var flowRampRow: some View {
        let language = appState.settings.language
        let scheme = appState.settings.flowTint.scheme(for: flowEditingMode)
        let bands = scheme.bands
        let state = Localization.string(Self.flowModeKey(flowEditingMode), language: language)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(Localization.string("settings.flow.byCharge %@", language: language, state))
                Spacer(minLength: 8)
                Text("settings.tint.transition")
                    .foregroundStyle(.secondary)
                Picker("settings.tint.transition", selection: flowTransitionBinding) {
                    ForEach(TintTransition.allCases) { transition in
                        Text(LocalizedStringKey(transition.localizationKey)).tag(Optional(transition))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            TintRampEditor(
                bands: bands,
                followLabel: "settings.tint.labelColor",
                language: language,
                editingID: $flowEditingBandID,
                onChange: setFlowBands
            ) { band, lower in
                valueSegmentEditor(
                    band,
                    lower: lower,
                    bands: bands,
                    captionKey: "settings.flow.segment.caption",
                    onChange: setFlowBands,
                    onClose: { flowEditingBandID = nil }
                )
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("settings.tint.ramp.hint")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    if let result = TintRamp.addingBoundary(to: bands) {
                        setFlowBands(result.bands)
                        flowEditingBandID = result.newID
                    }
                } label: {
                    Label("settings.tint.addBoundary", systemImage: "plus")
                }
                .disabled(bands.count >= 8)
            }
            Button("settings.flow.applyToAll") {
                let source = appState.settings.flowTint.scheme(for: flowEditingMode)
                appState.settings.flowTint = appState.settings.flowTint.mapAll { _ in source }
            }
            .disabled(Self.flowModes.allSatisfy { appState.settings.flowTint.scheme(for: $0) == scheme })
        }
        .padding(.vertical, 4)
    }

    /// The segment popover for schemes that color the panel rather than the menu bar.
    private func valueSegmentEditor(
        _ band: MenuBarTintBand,
        lower: Int,
        bands: [MenuBarTintBand],
        captionKey: LocalizedStringKey,
        onChange: @escaping ([MenuBarTintBand]) -> Void,
        onClose: @escaping () -> Void
    ) -> some View {
        let ordered = TintRamp.sorted(bands)
        let index = ordered.firstIndex { $0.id == band.id }
        let previous = index.flatMap { $0 > 0 ? ordered[$0 - 1] : nil }
        return TintSegmentEditor(
            band: band,
            lower: lower,
            previous: previous,
            language: appState.settings.language,
            rangeKey: "settings.tint.segment.range %lld %lld",
            captionKey: captionKey,
            atKey: "settings.tint.color.at %lld",
            followName: "settings.tint.labelColor",
            followNote: "settings.tint.labelColor.note",
            canDelete: ordered.count > 1,
            upperRange: index.flatMap { $0 < ordered.count - 1 ? TintRamp.boundaryRange(at: $0, in: ordered) : nil },
            onSetUpper: { onChange(TintRamp.moving(band.id, to: $0, in: bands)) },
            onChange: { next in onChange(TintRamp.replacing(next, in: bands)) },
            onDelete: {
                onClose()
                onChange(TintRamp.removing(band.id, from: bands))
            }
        ) {
            TintBandFill(band: band)
                .frame(width: 56, height: 16)
                .clipShape(Capsule())
                .overlay { Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5) }
        }
    }

    private enum MotionColorChoice: Hashable {
        case ribbon, custom
    }

    private var motionColorChoiceBinding: Binding<MotionColorChoice> {
        Binding(
            get: { motionColorEnabledBinding.wrappedValue ? .custom : .ribbon },
            set: { motionColorEnabledBinding.wrappedValue = $0 == .custom }
        )
    }

    private var flowMotionColorRow: some View {
        HStack(spacing: 8) {
            Text("settings.flow.motionColor")
            Spacer(minLength: 8)
            if appState.settings.flowTint.motionColor != nil {
                ColorPicker("settings.flow.motionColor", selection: motionColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .fixedSize()
            }
            Picker("settings.flow.motionColor", selection: motionColorChoiceBinding) {
                Text("settings.flow.motionColor.ribbon").tag(MotionColorChoice.ribbon)
                Text("settings.flow.motionColor.custom").tag(MotionColorChoice.custom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .disabled(appState.settings.motionStyle.pigment == nil)
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

    private var iconSlotColumnWidth: CGFloat { 56 }

    private func iconZoomSlider(value: Binding<Double>, name: String, width: CGFloat? = nil) -> some View {
        let percent = Int((value.wrappedValue * 100).rounded())
        let language = appState.settings.language
        return VStack(spacing: 2) {
            Slider(value: value, in: GlyphSlot.minScale...GlyphSlot.maxScale, step: 0.01)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(Text(verbatim: Localization.string("settings.icons.zoom.for %@", language: language, name)))
                .accessibilityValue(Text(verbatim: "\(percent)%"))
            Text("\(percent)%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .frame(width: width ?? iconSlotColumnWidth)
        .help(Localization.string("settings.icons.zoom", language: appState.settings.language))
    }

    @ViewBuilder
    private func popoverOrderEntry(_ entry: PopoverEntry) -> some View {
        switch entry {
        case .block(let block):
            if block != .settings || appState.settings.settingsButtonPlacement == .ownBlock {
                popoverOrderRow(block)
            }
        case .divider(let id):
            popoverDividerRow(id)
        }
    }


    private func popoverOrderRow(_ block: PopoverBlock) -> some View {
        let entry = PopoverEntry.block(block)
        let icon = popoverBlockIcon(block)
        return HStack(spacing: 8) {
            popoverDragHandle {
                popoverDrag.entry = entry
                return NSItemProvider(object: entry.rawValue as NSString)
            }
            SettingsSidebarIcon(glyph: icon.glyph, palette: icon.palette, size: 22)
            Toggle(LocalizedStringKey(block.localizationKey), isOn: popoverVisibilityBinding(block))
                .disabled(appState.settings.isSoleVisiblePopoverBlock(block))
        }
        .onDrop(of: [.plainText], delegate: popoverDropDelegate(for: entry))
    }


    private func popoverDividerRow(_ id: UUID) -> some View {
        let entry = PopoverEntry.divider(id)
        return HStack(spacing: 8) {
            popoverDragHandle {
                popoverDrag.entry = entry
                return NSItemProvider(object: entry.rawValue as NSString)
            }
            SettingsDashedRule()
            Text("settings.popover.divider")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize()
            SettingsDashedRule()
            Button {
                appState.settings.removePopoverDivider(id: id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(LocalizedStringKey("settings.popover.removeDivider"))
        }
        .onDrop(of: [.plainText], delegate: popoverDropDelegate(for: entry))
    }

    private func popoverDragHandle(_ onDrag: @escaping () -> NSItemProvider) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 22)
            .contentShape(Rectangle())
            .onDrag(onDrag)
    }

    private func popoverDropDelegate(for entry: PopoverEntry) -> PopoverBlockDropDelegate {
        PopoverBlockDropDelegate(
            entry: entry,
            drag: popoverDrag,
            move: { item, target in
                appState.settings.movePopoverEntry(item, to: target)
            }
        )
    }

    private func popoverVisibilityBinding(_ block: PopoverBlock) -> Binding<Bool> {
        switch block {
        case .rings: $appState.settings.showStatusRings
        case .flow: $appState.settings.showEnergyFlow
        case .topApps: $appState.settings.showTopApps
        case .lowPower: $appState.settings.showLowPower
        case .localIP: $appState.settings.showLocalIP
        case .batteryCycle: $appState.settings.showBatteryCycle
        case .settings: $appState.settings.showSettingsBlock
        }
    }

    private func ipScopeBinding(_ scope: IPAddressScope) -> Binding<Bool> {
        Binding(
            get: { appState.settings.ipScopes.contains(scope) },
            set: { enabled in
                if enabled {
                    appState.settings.ipScopes.insert(scope)
                } else {
                    appState.settings.ipScopes.remove(scope)
                }
            }
        )
    }

    private func ringRowEditor(rowIndex: Int, row: [RingItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("settings.rings.row \(rowIndex + 1)")
                Spacer()
                if appState.settings.ringRows.count > 1 {
                    Button("settings.rings.removeRow") {
                        appState.settings.removeRingRow(rowIndex)
                    }
                }
            }
            if row.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .onDrop(of: [.plainText], delegate: RingItemRowDropDelegate(
                        row: rowIndex,
                        drag: ringItemDrag,
                        move: { id, row in
                            appState.settings.moveRingItem(id: id, toEndOfRow: row)
                        }
                    ))
            }
            ForEach(row) { item in
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 22)
                    Text(ringItemTitle(item))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                .onDrag {
                    ringItemDrag.itemID = item.id
                    return NSItemProvider(object: item.id as NSString)
                }
                .onDrop(of: [.plainText], delegate: RingItemDropDelegate(
                    itemID: item.id,
                    drag: ringItemDrag,
                    move: { id, target in
                        appState.settings.moveRingItem(id: id, to: target)
                    }
                ))
            }
        }
        .padding(.vertical, 4)
    }

    private func ringItemTitle(_ item: RingItem) -> String {
        let language = appState.settings.language
        if let slot = item.slot {
            return Localization.string(slot.localizationKey, language: language)
        }
        let device = appState.settings.bluetoothRingDevices.first { $0.address == item.address }
        let name = device?.name ?? item.address ?? ""
        let parts = device?.rings.first { $0.id == item.ringID }?.parts ?? []
        if parts.isEmpty || parts == [.single] { return name }
        let detail = parts.map { Localization.string($0.localizationKey, language: language) }.joined(separator: " + ")
        return "\(name) · \(detail)"
    }

    private func bluetoothDeviceEditor(_ device: BluetoothRingDevice) -> some View {
        let catalog: [BluetoothBatteryPart] = device.multi ? [.left, .right, .box] : []
        let unused = catalog.filter { part in !device.rings.contains { $0.parts.contains(part) } }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(device.name)
                Spacer()
                Button("settings.rings.bluetooth.remove") {
                    appState.settings.removeBluetoothDevice(address: device.address)
                }
            }
            if device.rings.isEmpty {
                Text("settings.rings.bluetooth.empty")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(device.rings.enumerated()), id: \.element.id) { offset, ring in
                bluetoothRingEditor(device: device, ring: ring, index: offset, catalog: catalog)
            }
            if device.rings.count < 3, !unused.isEmpty || (!device.multi && device.rings.isEmpty) {
                Button("settings.rings.bluetooth.addRing") {
                    appState.settings.addBluetoothDisplayRing(address: device.address)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func bluetoothRingEditor(
        device: BluetoothRingDevice,
        ring: BluetoothDisplayRing,
        index: Int,
        catalog: [BluetoothBatteryPart]
    ) -> some View {
        let usedElsewhere = Set(device.rings.filter { $0.id != ring.id }.flatMap(\.parts))
        let choices = catalog.filter { ring.parts.contains($0) || !usedElsewhere.contains($0) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("settings.rings.bluetooth.ring \(index + 1)")
                Spacer()
                if device.rings.count > 1 {
                    Button("settings.rings.bluetooth.removeRing") {
                        appState.settings.removeBluetoothDisplayRing(address: device.address, ringID: ring.id)
                    }
                }
            }
            if !choices.isEmpty {
                Text("settings.rings.bluetooth.partsInRing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(choices) { part in
                    Toggle(isOn: Binding(
                        get: { ring.parts.contains(part) },
                        set: { appState.settings.setBluetoothRingPart(address: device.address, ringID: ring.id, part: part, included: $0) }
                    )) {
                        Text(LocalizedStringKey(part.localizationKey))
                    }
                }
            }
            Picker("settings.rings.bluetooth.disconnected", selection: Binding(
                get: { ring.whenDisconnected },
                set: { appState.settings.setBluetoothRingDisconnected(address: device.address, ringID: ring.id, style: $0) }
            )) {
                ForEach(BluetoothDisconnectedStyle.allCases) { style in
                    Text(LocalizedStringKey(style.localizationKey)).tag(style)
                }
            }
            if ring.parts.count > 1 {
                Picker("settings.rings.bluetooth.incomplete", selection: Binding(
                    get: { ring.whenIncomplete },
                    set: { appState.settings.setBluetoothRingIncomplete(address: device.address, ringID: ring.id, style: $0) }
                )) {
                    ForEach(BluetoothIncompleteStyle.allCases) { style in
                        Text(LocalizedStringKey(style.localizationKey)).tag(style)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private struct BluetoothIconTarget: Identifiable {
        var device: BluetoothRingDevice
        var ring: BluetoothDisplayRing
        var part: BluetoothBatteryPart?
        var id: String { "\(ring.id.uuidString):\(part?.rawValue ?? "center")" }
    }

    @ViewBuilder
    private var bluetoothIconSettings: some View {
        let targets = appState.settings.bluetoothRingDevices.flatMap { device in
            device.rings.flatMap { ring -> [BluetoothIconTarget] in
                if ring.parts.count == 2 {
                    return ring.parts.map { BluetoothIconTarget(device: device, ring: ring, part: $0) }
                }
                return [BluetoothIconTarget(device: device, ring: ring, part: nil)]
            }
        }
        if !targets.isEmpty {
            ForEach(targets) { target in
                bluetoothIconRow(target)
            }
        }
    }

    private func bluetoothIconRow(_ target: BluetoothIconTarget) -> some View {
        let language = appState.settings.language
        let model = target.device.model
        let ring = target.ring
        let glyph = target.part.map { ring.shownGlyph(model: model, part: $0) }
            ?? ring.shownGlyph(model: model, parts: ring.parts)
        let stored = target.part.flatMap { ring.sideColors[$0] } ?? (target.part == nil ? ring.iconColor : nil)
        let followsLevel = target.part != nil
        var title = target.device.name
        if let part = target.part {
            title += " · " + Localization.string(part.localizationKey, language: language)
        } else if ring.parts.count == 1, let part = ring.parts.first, part != .single {
            title += " · " + Localization.string(part.localizationKey, language: language)
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    bluetoothIconEditor = BluetoothIconEdit(ringID: ring.id, part: target.part)
                } label: {
                    ringGlyphPlate(slot: glyph, diameter: 44)
                }
                .buttonStyle(.plain)
                .popover(isPresented: bluetoothIconPresented(ring.id, part: target.part), arrowEdge: .bottom) {
                    bluetoothIconChoices(device: target.device, ring: ring, part: target.part)
                        .environment(\.locale, appState.settings.resolvedLocale)
                }
                Text(title)
                    .lineLimit(2)
                Spacer(minLength: 8)
            }
            Picker("settings.rings.bluetooth.iconColor", selection: Binding(
                get: { stored == nil ? RingIconColorChoice.system : .custom },
                set: { choice in
                    let color = choice == .custom ? (stored ?? RingIconRGB(red: 0.2, green: 0.55, blue: 0.35)) : nil
                    appState.settings.setBluetoothRingIconColor(
                        address: target.device.address,
                        ringID: ring.id,
                        part: target.part,
                        color: color
                    )
                }
            )) {
                Text(followsLevel ? "settings.rings.bluetooth.colorLevel" : "settings.rings.bluetooth.colorSystem")
                    .tag(RingIconColorChoice.system)
                Text("settings.rings.bluetooth.colorCustom").tag(RingIconColorChoice.custom)
            }
            if let stored {
                ColorPicker(
                    "settings.rings.bluetooth.iconColor",
                    selection: Binding(
                        get: { stored.color },
                        set: {
                            appState.settings.setBluetoothRingIconColor(
                                address: target.device.address,
                                ringID: ring.id,
                                part: target.part,
                                color: RingIconRGB(color: $0)
                            )
                        }
                    ),
                    supportsOpacity: false
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func bluetoothIconPresented(_ id: UUID, part: BluetoothBatteryPart?) -> Binding<Bool> {
        Binding(
            get: { bluetoothIconEditor == BluetoothIconEdit(ringID: id, part: part) },
            set: { show in
                let edit = BluetoothIconEdit(ringID: id, part: part)
                bluetoothIconEditor = show ? edit : (bluetoothIconEditor == edit ? nil : bluetoothIconEditor)
            }
        )
    }

    private func bluetoothIconChoices(
        device: BluetoothRingDevice,
        ring: BluetoothDisplayRing,
        part: BluetoothBatteryPart?
    ) -> some View {
        let columns = Array(repeating: GridItem(.fixed(44), spacing: 10), count: 4)
        let current = part.map { ring.shownGlyph(model: device.model, part: $0) } ?? ring.glyph
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(HeadphoneSymbols.choices(model: device.model).enumerated()), id: \.offset) { _, choice in
                    Button {
                        var glyph = choice
                        glyph.scale = current.scale
                        appState.settings.setBluetoothRingGlyph(
                            address: device.address,
                            ringID: ring.id,
                            part: part,
                            glyph: glyph
                        )
                        bluetoothIconEditor = nil
                    } label: {
                        bluetoothChoiceGlyph(choice)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .frame(width: 44 * 4 + 10 * 3 + 24, height: 280)
    }

    /// Wide symbols (keyboard, headset, gamepad) must fit the cell. The ring glyph plate clips to a square.
    @ViewBuilder
    private func bluetoothChoiceGlyph(_ slot: GlyphSlot) -> some View {
        let side: CGFloat = 30
        if slot.name.hasPrefix(HeadphoneSymbols.systemImagePrefix),
           let artwork = HeadphoneSymbols.systemImage(named: String(slot.name.dropFirst(HeadphoneSymbols.systemImagePrefix.count))) {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .frame(width: 44, height: 44)
        } else {
            Image(systemName: slot.name)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .frame(width: side, height: side)
                .frame(width: 44, height: 44)
        }
    }

    private func slotIconColorControls(_ slot: RingSlot) -> some View {
        let stored = appState.settings.slotIconColors[slot.rawValue]
        return VStack(alignment: .leading, spacing: 4) {
            Picker("settings.rings.bluetooth.iconColor", selection: Binding(
                get: { stored == nil ? RingIconColorChoice.system : .custom },
                set: { choice in
                    let color = choice == .custom ? (stored ?? RingIconRGB(red: 0.15, green: 0.15, blue: 0.15)) : nil
                    appState.settings.setSlotIconColor(slot, color: color)
                }
            )) {
                Text("settings.rings.bluetooth.colorSystem").tag(RingIconColorChoice.system)
                Text("settings.rings.bluetooth.colorCustom").tag(RingIconColorChoice.custom)
            }
            if let stored {
                ColorPicker(
                    "settings.rings.bluetooth.iconColor",
                    selection: Binding(
                        get: { stored.color },
                        set: { appState.settings.setSlotIconColor(slot, color: RingIconRGB(color: $0)) }
                    ),
                    supportsOpacity: false
                )
            }
        }
    }

    private func temperatureHalfStepper(title: LocalizedStringKey = "settings.rings.half.temperature") -> some View {
        let unit = appState.settings.temperatureUnit
        let bounds = AppSettings.temperatureHalfRange
        let shown = unit.display(appState.settings.temperatureHalfCelsius)
        return topAppStepper(
            title,
            value: shown,
            unit: LocalizedStringKey(stringLiteral: unit.symbol),
            range: unit.display(bounds.lowerBound)...unit.display(bounds.upperBound),
            step: 1
        ) { displayed in
            let celsius = unit.storedCelsius(fromDisplayed: displayed)
            appState.settings.temperatureHalfCelsius = min(max(celsius, bounds.lowerBound), bounds.upperBound)
        }
    }

    private func ringScalePresented(_ slot: RingSlot) -> Binding<Bool> {
        Binding(
            get: { ringScaleSlot == slot },
            set: { presented in
                if presented {
                    ringScaleSlot = slot
                } else if ringScaleSlot == slot {
                    ringScaleSlot = nil
                }
            }
        )
    }

    @ViewBuilder
    private func ringScalePopover(_ slot: RingSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch slot {
            case .download:
                speedHalfStepper(
                    "settings.rings.half.download",
                    kilobytes: appState.settings.downloadHalfKilobytes
                ) { appState.settings.downloadHalfKilobytes = $0 }
            case .upload:
                speedHalfStepper(
                    "settings.rings.half.upload",
                    kilobytes: appState.settings.uploadHalfKilobytes
                ) { appState.settings.uploadHalfKilobytes = $0 }
            case .speedPair:
                speedHalfStepper(
                    "settings.rings.half.download",
                    kilobytes: appState.settings.downloadHalfKilobytes
                ) { appState.settings.downloadHalfKilobytes = $0 }
                speedHalfStepper(
                    "settings.rings.half.upload",
                    kilobytes: appState.settings.uploadHalfKilobytes
                ) { appState.settings.uploadHalfKilobytes = $0 }
            case .swap:
                HStack(spacing: 8) {
                    Text("settings.rings.half.swap")
                    Spacer(minLength: 8)
                    Text(SwapUsageFormat.string(bytes: Double(appState.settings.swapHalfMegabytes) * 1_048_576))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper(
                        "settings.rings.half.swap",
                        value: Binding(
                            get: { appState.settings.swapHalfMegabytes },
                            set: { appState.settings.swapHalfMegabytes = $0 }
                        ),
                        in: AppSettings.swapHalfLimit(),
                        step: AppSettings.swapHalfStep
                    )
                    .labelsHidden()
                    .fixedSize()
                }
                Text("settings.rings.half.swap.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .compressor:
                HStack(spacing: 8) {
                    Text("settings.rings.half.compressor")
                    Spacer(minLength: 8)
                    Text(SwapUsageFormat.string(bytes: Double(appState.settings.compressorHalfMegabytes) * 1_048_576))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper(
                        "settings.rings.half.compressor",
                        value: Binding(
                            get: { appState.settings.compressorHalfMegabytes },
                            set: { appState.settings.compressorHalfMegabytes = $0 }
                        ),
                        in: AppSettings.swapHalfLimit(),
                        step: AppSettings.swapHalfStep
                    )
                    .labelsHidden()
                    .fixedSize()
                }
                Text("settings.rings.half.compressor.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .overflow:
                HStack(spacing: 8) {
                    Text("settings.rings.half.overflow")
                    Spacer(minLength: 8)
                    Text(SwapUsageFormat.string(bytes: Double(appState.settings.overflowHalfMegabytes) * 1_048_576))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper(
                        "settings.rings.half.overflow",
                        value: Binding(
                            get: { appState.settings.overflowHalfMegabytes },
                            set: { appState.settings.overflowHalfMegabytes = $0 }
                        ),
                        in: AppSettings.swapHalfLimit(),
                        step: AppSettings.swapHalfStep
                    )
                    .labelsHidden()
                    .fixedSize()
                }
                Text("settings.rings.half.overflow.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .batteryTemperature:
                temperatureHalfStepper()
            case .thermalState:
                topAppStepper(
                    "ring.thermal.nominal",
                    value: appState.settings.thermalNominalPercent,
                    unit: "%",
                    range: AppSettings.thermalPercentRange,
                    step: 5
                ) { appState.settings.thermalNominalPercent = $0 }
                topAppStepper(
                    "ring.thermal.fair",
                    value: appState.settings.thermalFairPercent,
                    unit: "%",
                    range: AppSettings.thermalPercentRange,
                    step: 5
                ) { appState.settings.thermalFairPercent = $0 }
                topAppStepper(
                    "ring.thermal.serious",
                    value: appState.settings.thermalSeriousPercent,
                    unit: "%",
                    range: AppSettings.thermalPercentRange,
                    step: 5
                ) { appState.settings.thermalSeriousPercent = $0 }
                topAppStepper(
                    "ring.thermal.critical",
                    value: appState.settings.thermalCriticalPercent,
                    unit: "%",
                    range: AppSettings.thermalPercentRange,
                    step: 5
                ) { appState.settings.thermalCriticalPercent = $0 }
            default:
                EmptyView()
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func ringIconSlotRow(_ rings: [RingSlot]) -> some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(rings) { ring in
                ringIconSlotControl(ring)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func ringIconSlotControl(_ ring: RingSlot) -> some View {
        let language = appState.settings.language
        let slot = appState.settings.ringIcons.slot(for: ring)
        let column = StatusRingView.diameter
        VStack(spacing: 6) {
            Text(Localization.string(ring.localizationKey, language: language))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: column)
                .multilineTextAlignment(.center)
            Button {
                ringIconEditor = ring
            } label: {
                ringGlyphPlate(slot: slot, diameter: StatusRingView.diameter)
            }
            .buttonStyle(.plain)
            .help(Localization.string("settings.icons.clickToChange", language: language))
            .accessibilityLabel(Text(verbatim: Localization.string("settings.icons.change.for %@", language: language, Localization.string(ring.localizationKey, language: language))))
            .popover(isPresented: ringIconEditorPresented(ring), arrowEdge: .bottom) {
                ringIconChoicePopover(ring)
                    .environment(\.locale, appState.settings.resolvedLocale)
            }
            iconZoomSlider(
                value: Binding(
                    get: { appState.settings.ringIcons.slot(for: ring).scale },
                    set: { appState.settings.ringIcons = appState.settings.ringIcons.withScale($0, for: ring) }
                ),
                name: Localization.string(ring.localizationKey, language: language),
                width: column
            )
        }
        .frame(width: column)
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
            .accessibilityLabel(Text(verbatim: Localization.string("settings.icons.change.for %@", language: language, Localization.string(role.localizationKey, language: language))))
            iconZoomSlider(
                value: Binding(
                    get: { appState.settings.flowIcons.slot(for: role).scale },
                    set: { appState.settings.flowIcons = appState.settings.flowIcons.withScale($0, for: role) }
                ),
                name: Localization.string(role.localizationKey, language: language)
            )
        }
        .frame(width: iconSlotColumnWidth)
        .frame(maxWidth: .infinity)
    }

    private func ringIconEditorPresented(_ ring: RingSlot) -> Binding<Bool> {
        Binding(
            get: { ringIconEditor == ring },
            set: { show in
                if show {
                    ringIconEditor = ring
                } else if ringIconEditor == ring {
                    ringIconEditor = nil
                }
            }
        )
    }

    private func ringIconChoicePopover(_ ring: RingSlot) -> some View {
        let language = appState.settings.language
        let current = appState.settings.ringIcons.slot(for: ring)
        let choices = ring.symbolChoices
        let diameter = StatusRingView.diameter
        let perRow = min(max(choices.count, 1), 4)
        let columns = Array(repeating: GridItem(.fixed(diameter), spacing: 14), count: perRow)
        return VStack(alignment: .leading, spacing: 12) {
            Button(Localization.string("settings.icons.upload", language: language)) {
                ringIconEditor = nil
                uploadRingIcon(ring)
            }
            if current.source == .custom {
                Toggle(
                    Localization.string("settings.icons.template", language: language),
                    isOn: ringTemplateBinding(ring)
                )
            }
            LazyVGrid(columns: columns, alignment: .center, spacing: 14) {
                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                    let shown = choice.withScale(current.scale)
                    Button {
                        appState.settings.ringIcons = appState.settings.ringIcons.replacing(ring, with: shown)
                        ringIconEditor = nil
                    } label: {
                        ringGlyphPlate(slot: shown, diameter: diameter)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(width: CGFloat(perRow) * diameter + 14 * CGFloat(max(perRow - 1, 0)) + 32)
    }

    /// Same diameter, stroke, and glyph size as a panel ring.
    private func ringGlyphPlate(slot: GlyphSlot, diameter: CGFloat) -> some View {
        let scale = diameter / StatusRingView.diameter
        let zoom = CGFloat(slot.normalizedScale)
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.35), lineWidth: StatusRingView.lineWidth * scale)
                .frame(
                    width: diameter - StatusRingView.lineWidth * scale,
                    height: diameter - StatusRingView.lineWidth * scale
                )
            GlyphSlotView(
                slot: slot,
                systemPointSize: StatusRingView.glyphPointSize * scale * zoom,
                assetSide: StatusRingView.glyphAssetSide * scale * zoom,
                prefersMonochrome: true
            )
        }
        .frame(width: diameter, height: diameter)
    }

    /// Fixed-size glyph preview; no chevron — caption says to click the icon.
    @ViewBuilder
    private func iconSlotMenuPreview<Content: View>(
        slot: GlyphSlot,
        ringSized: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let scale = CGFloat(slot.normalizedScale)
        let side = ringSized ? StatusRingView.diameter : iconSlotColumnWidth - 8
        let pointSize = ringSized ? StatusRingView.glyphPointSize * scale : 17
        let assetSide = ringSized ? StatusRingView.glyphAssetSide * scale : 20
        Menu(content: content) {
            ZStack {
                if ringSized {
                    Circle()
                        .stroke(Color.secondary.opacity(0.35), lineWidth: StatusRingView.lineWidth)
                        .frame(
                            width: StatusRingView.diameter - StatusRingView.lineWidth,
                            height: StatusRingView.diameter - StatusRingView.lineWidth
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                }
                GlyphSlotView(
                    slot: slot,
                    systemPointSize: pointSize,
                    assetSide: assetSide,
                    prefersMonochrome: ringSized
                )
            }
            .frame(width: side, height: side)
            .contentShape(ringSized ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: side, height: side)
        .help(Localization.string("settings.icons.clickToChange", language: appState.settings.language))
    }

    private func ringTemplateBinding(_ ring: RingSlot) -> Binding<Bool> {
        Binding(
            get: { appState.settings.ringIcons.slot(for: ring).template },
            set: { enabled in
                var slot = appState.settings.ringIcons.slot(for: ring)
                slot.template = enabled
                appState.settings.ringIcons = appState.settings.ringIcons.replacing(ring, with: slot)
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

    private func uploadRingIcon(_ ring: RingSlot) {
        let title = Localization.string("settings.icons.upload", language: appState.settings.language)
        let slot = appState.settings.ringIcons.slot(for: ring)
        guard let url = CustomIconStore.pickImage(title: title),
              let id = CustomIconStore.save(fromFile: url) else { return }
        appState.settings.ringIcons = appState.settings.ringIcons.replacing(
            ring,
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

    private func selectedRingColor() -> RingColor? {
        let colors = appState.settings.ringTint.colors
        if let id = ringColorSelectionID, let color = colors.first(where: { $0.id == id }) {
            return color
        }
        return colors.first
    }

    private func ringColorTitle(_ index: Int) -> String {
        Localization.string(
            "settings.tint.color %lld",
            language: appState.settings.language,
            index + 1
        )
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

private final class PopoverBlockDragState {
    var entry: PopoverEntry?
}

private struct PopoverBlockDropDelegate: DropDelegate {
    var entry: PopoverEntry
    var drag: PopoverBlockDragState
    var move: (PopoverEntry, PopoverEntry) -> Void

    func dropEntered(info: DropInfo) {
        guard let item = drag.entry, item.id != entry.id else { return }
        move(item, entry)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag.entry = nil
        return true
    }
}

private final class RingDragState {
    var slot: RingSlot?
}

private final class RingItemDragState {
    var itemID: String?
}

private struct RingItemDropDelegate: DropDelegate {
    var itemID: String
    var drag: RingItemDragState
    var move: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let item = drag.itemID, item != itemID else { return }
        move(item, itemID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag.itemID = nil
        return true
    }
}

private struct RingItemRowDropDelegate: DropDelegate {
    var row: Int
    var drag: RingItemDragState
    var move: (String, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let item = drag.itemID else { return }
        move(item, row)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag.itemID = nil
        return true
    }
}

private struct RingSlotDropDelegate: DropDelegate {
    var slot: RingSlot
    var drag: RingDragState
    var move: (RingSlot, RingSlot) -> Void

    func dropEntered(info: DropInfo) {
        guard let item = drag.slot, item != slot else { return }
        move(item, slot)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag.slot = nil
        return true
    }
}

private struct JustifiedBody: NSViewRepresentable {
    var text: String

    func makeNSView(context: Context) -> JustifiedTextField {
        let field = JustifiedTextField(wrappingLabelWithString: "")
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        return field
    }

    func updateNSView(_ field: JustifiedTextField, context: Context) {
        let style = NSMutableParagraphStyle()
        style.alignment = .justified
        style.lineBreakMode = .byWordWrapping
        style.hyphenationFactor = 0.6
        field.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: style
            ]
        )
        field.invalidateIntrinsicContentSize()
    }

    /// Wrap to the width SwiftUI offers on the first pass. Waiting for
    /// `layout()` left the first frame as one long, clipped line.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: JustifiedTextField, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        field.preferredMaxLayoutWidth = width
        let bounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
        let height = field.cell?.cellSize(forBounds: bounds).height ?? field.intrinsicContentSize.height
        return CGSize(width: width, height: ceil(height))
    }
}

private final class JustifiedTextField: NSTextField {
    override func layout() {
        let width = bounds.width
        if width > 0, preferredMaxLayoutWidth != width {
            preferredMaxLayoutWidth = width
            invalidateIntrinsicContentSize()
        }
        super.layout()
    }
}

private struct BluetoothIconEdit: Equatable {
    var ringID: UUID
    var part: BluetoothBatteryPart?
}

private enum RingIconColorChoice: String, Hashable {
    case system
    case custom
}

private struct BluetoothDevicePicker: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var candidates: [BluetoothSeenDevice] {
        let taken = Set(appState.settings.bluetoothRingDevices.map(\.address))
        return appState.bluetoothDevices
            .filter { !$0.levels.isEmpty && !taken.contains($0.address) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings.rings.bluetooth.add")
                .font(.headline)
            if candidates.isEmpty {
                Text("settings.rings.bluetooth.none")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(candidates) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                            Text(candidateDetail(device))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("settings.rings.bluetooth.add") {
                            appState.settings.addBluetoothDevice(device)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("settings.rings.bluetooth.close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func candidateDetail(_ device: BluetoothSeenDevice) -> String {
        let language = appState.settings.language
        return device.levels.keys.sorted { $0.rawValue < $1.rawValue }.map { part in
            let name = Localization.string(part.localizationKey, language: language)
            return "\(name) \(device.levels[part] ?? 0)%"
        }.joined(separator: "  ")
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
