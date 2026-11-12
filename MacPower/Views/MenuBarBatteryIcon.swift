import CoreText
import AppKit

enum MenuBarBatteryRenderer {
    /// Chrome stays a template so the menu bar can tint it for light/dark wallpaper.
    /// Colored charge is a separate non-template overlay on the status item.
    struct StatusItemContent {
        var chrome: NSImage
        var charge: NSImage?
    }

    private enum Layer {
        case full
        case chrome
        case charge
    }

    static func image(
        snapshot: PowerSnapshot,
        style: MenuBarIconStyle,
        fill: MenuBarResolvedFill,
        appearance: NSAppearance,
        showChargeGlyphs: Bool
    ) -> NSImage {
        let prepared = prepare(snapshot: snapshot, style: style, fill: fill, appearance: appearance, showChargeGlyphs: showChargeGlyphs)
        let image = rasterImage(size: prepared.size, appearance: appearance) { rect in
            drawBattery(
                in: rect,
                metrics: prepared.metrics,
                percent: snapshot.percent / 100,
                style: style,
                fill: fill,
                neutralFill: prepared.neutralFill,
                glyph: prepared.glyph,
                layer: .full
            )
        }
        image.isTemplate = fill.isTemplate
        return image
    }

    static func statusItemContent(
        snapshot: PowerSnapshot,
        style: MenuBarIconStyle,
        fill: MenuBarResolvedFill,
        appearance: NSAppearance,
        showChargeGlyphs: Bool
    ) -> StatusItemContent {
        if fill.isTemplate {
            let image = image(
                snapshot: snapshot,
                style: style,
                fill: fill,
                appearance: appearance,
                showChargeGlyphs: showChargeGlyphs
            )
            return StatusItemContent(chrome: image, charge: nil)
        }

        let prepared = prepare(snapshot: snapshot, style: style, fill: fill, appearance: appearance, showChargeGlyphs: showChargeGlyphs)
        // Template black for chrome — AppKit retints it to the menu bar's adaptive color.
        let chromeNeutral = MenuBarResolvedFill.template
        let chrome = rasterImage(size: prepared.size, appearance: appearance) { rect in
            drawBattery(
                in: rect,
                metrics: prepared.metrics,
                percent: snapshot.percent / 100,
                style: style,
                fill: fill,
                neutralFill: chromeNeutral,
                glyph: prepared.glyph,
                layer: .chrome
            )
        }
        chrome.isTemplate = true

        let charge = rasterImage(size: prepared.size, appearance: appearance) { rect in
            drawBattery(
                in: rect,
                metrics: prepared.metrics,
                percent: snapshot.percent / 100,
                style: style,
                fill: fill,
                neutralFill: chromeNeutral,
                glyph: prepared.glyph,
                layer: .charge
            )
        }
        charge.isTemplate = false
        return StatusItemContent(chrome: chrome, charge: charge)
    }

    private struct Prepared {
        var metrics: Metrics
        var size: NSSize
        var glyph: MenuBarGlyph?
        var neutralFill: MenuBarResolvedFill
    }

    private static func prepare(
        snapshot: PowerSnapshot,
        style: MenuBarIconStyle,
        fill: MenuBarResolvedFill,
        appearance: NSAppearance,
        showChargeGlyphs: Bool
    ) -> Prepared {
        let percent = Int(snapshot.percent.rounded(.towardZero))
        let charging = snapshot.flowMode == .charging
        let plugged = snapshot.flowMode == .adapterHold || snapshot.flowMode == .underpowered
        let glyph: MenuBarGlyph? = {
            guard showChargeGlyphs else { return nil }
            if charging || plugged { return .bolt }
            return nil
        }()

        let neutralFill: MenuBarResolvedFill
        if fill.isTemplate {
            neutralFill = fill
        } else {
            // In-window previews bake the label color for the current appearance.
            let color = MenuBarTintSwatch.menuBar.paintNSColor(appearance: appearance)
            neutralFill = MenuBarResolvedFill(left: color, right: color, isTemplate: false)
        }
        let height: CGFloat = 16
        let metrics = layout(percent: percent, style: style, glyph: glyph, height: height)
        return Prepared(
            metrics: metrics,
            size: NSSize(width: metrics.totalWidth, height: height),
            glyph: glyph,
            neutralFill: neutralFill
        )
    }

    /// Draw at 2x so the terminal gap stays a real hole after template scaling.
    private static func rasterImage(
        size: NSSize,
        appearance: NSAppearance,
        draw: @escaping (NSRect) -> Void
    ) -> NSImage {
        let scale: CGFloat = 2
        let image = NSImage(size: size)
        let pixelsWide = max(1, Int((size.width * scale).rounded(.up)))
        let pixelsHigh = max(1, Int((size.height * scale).rounded(.up)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: size, flipped: false) { rect in
                appearance.performAsCurrentDrawingAppearance { draw(rect) }
                return true
            }
        }
        rep.size = size
        image.addRepresentation(rep)
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            appearance.performAsCurrentDrawingAppearance {
                draw(NSRect(origin: .zero, size: size))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return image
    }

    private enum MenuBarGlyph {
        case bolt
    }

    private struct Metrics {
        var totalWidth: CGFloat
        var body: NSRect
        var cap: NSRect
        var digitBox: NSRect
        var font: NSFont
        var text: String
        var kern: CGFloat
        var glyphBox: NSRect
    }

    /// Prefer PingFang Semibold: its digit widths fit the 23pt system body the way
    /// SF Rounded Semibold does not. Fall back to the system rounded face.
    private static func percentFont(size: CGFloat) -> NSFont {
        for name in ["PingFangSC-Semibold", "PingFangSC-Medium"] {
            if let font = NSFont(name: name, size: size), font.fontName.hasPrefix("PingFang") {
                return font
            }
        }
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return NSFont(descriptor: rounded, size: size) ?? base
    }

    private static func layout(
        percent: Int,
        style: MenuBarIconStyle,
        glyph: MenuBarGlyph?,
        height: CGFloat
    ) -> Metrics {
        let bodyHeight: CGFloat = 12
        let bodyY = (height - bodyHeight) / 2
        let percentInside = style == .systemPercentInside
        let capWidth: CGFloat = style.isOutlined ? 2 : 1.5
        let capHeight: CGFloat = style.isOutlined ? bodyHeight : (percentInside ? 3.95 : 4)
        let capGap: CGFloat = style.isOutlined ? 1 : (percentInside ? 1.00 : 1.22)
        let showsText = style.showsPercentInside
        let text = showsText ? "\(percent)" : ""
        let digits = text.count
        let fontSize: CGFloat = {
            // The outlined body keeps a 2pt gutter, so the shared size fills the interior.
            if style.isOutlined, showsText { return digits >= 3 ? 7.2 : 8.0 }
            // Beside the bolt the system shrinks three digits to 13px; alone they stay 15px.
            // Semibold PingFang reads closer to the system's weight than Medium.
            if digits >= 3 { return glyph != nil ? 9.2 : 10.2 }
            return 10.4
        }()
        let insideKnockout = showsText && !style.isOutlined
        let font = percentFont(size: fontSize)
        var textSize = text.isEmpty
            ? NSSize.zero
            : (text as NSString).size(withAttributes: [.font: font])
        // The system spaces three inside digits slightly wider than the font does.
        let kern: CGFloat = insideKnockout && digits >= 3 ? (glyph != nil ? 0.4 : 0.35) : 0
        if insideKnockout {
            // Space the knockout by ink so the bolt sits as close to the digits as the system's.
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .kern: kern]))
            textSize.width = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds]).width
        }
        let insideBolt = insideBoltInkSize(digits: digits)
        let glyphAdvance: CGFloat
        switch glyph {
        case .bolt: glyphAdvance = insideKnockout ? insideBolt.width : (showsText ? 5.8 : 8.8)
        case nil: glyphAdvance = 0
        }
        let gap: CGFloat = (showsText && glyph != nil) ? (insideKnockout ? (digits >= 3 ? 0.9 : 0.7) : 0.45) : 0
        let groupWidth = (showsText ? textSize.width : 0) + gap + glyphAdvance
        let bodyWidth: CGFloat = {
            if !showsText { return 23 }
            // Measured from the system menu-bar battery: 46px at 2x, for two and three digits.
            if style == .systemPercentInside { return 23 }
            return digits >= 3 ? 24.0 : (style.isOutlined ? 23 : 22.5)
        }()
        let body = NSRect(x: style.isOutlined ? 0 : 0.35, y: bodyY, width: bodyWidth, height: bodyHeight)
        let cap = NSRect(
            x: body.maxX + capGap,
            y: body.midY - capHeight / 2,
            width: capWidth,
            height: capHeight
        )
        let groupX = body.midX - groupWidth / 2
        let digitBox = NSRect(
            x: groupX,
            y: body.minY,
            width: showsText ? textSize.width : body.width,
            height: body.height
        )
        let glyphBox = NSRect(
            x: groupX + (showsText ? textSize.width + gap : 0),
            y: body.minY,
            width: max(glyphAdvance, showsText ? 0 : body.width),
            height: body.height
        )
        return Metrics(
            totalWidth: cap.maxX + 1.0,
            body: body,
            cap: cap,
            digitBox: digitBox,
            font: font,
            text: text,
            kern: kern,
            glyphBox: glyphBox
        )
    }

    private static func drawBattery(
        in rect: NSRect,
        metrics: Metrics,
        percent: CGFloat,
        style: MenuBarIconStyle,
        fill: MenuBarResolvedFill,
        neutralFill: MenuBarResolvedFill,
        glyph: MenuBarGlyph?,
        layer: Layer
    ) {
        let body = metrics.body
        if style.isOutlined {
            drawOutlinedChargeLevel(
                body: body,
                cap: metrics.cap,
                percent: percent,
                fill: fill,
                neutralFill: neutralFill,
                layer: layer
            )
            if layer != .charge, style.showsPercentInside {
                drawOutlinedText(metrics: metrics, percent: percent, fill: neutralFill)
            }
            if layer == .charge, style.showsPercentInside {
                // Punch digits through the colored charge so wallpaper shows through.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                punchCenteredText(metrics.text, font: metrics.font, in: metrics.digitBox)
                NSGraphicsContext.restoreGraphicsState()
            }
            if glyph != nil {
                let target = style.showsPercentInside ? metrics.glyphBox : body
                if layer != .charge {
                    drawOutlinedChargeMark(in: target, compact: style.showsPercentInside, fill: neutralFill)
                } else if style.showsPercentInside {
                    punchOutlinedChargeMark(in: target, compact: true)
                }
            }
            return
        }
        let percentInside = style == .systemPercentInside
        drawChargeLevel(
            body: body,
            cap: metrics.cap,
            percent: percent,
            fill: fill,
            neutralFill: neutralFill,
            bodyPath: percentInside
                ? NSBezierPath(roundedRect: body, xRadius: 4.04, yRadius: 4.04)
                : continuousRoundedRect(body, radius: 3.8),
            backingAlpha: percentInside ? 0.50 : 0.52,
            terminalAlpha: percentInside ? 0.60 : 0.62,
            terminalKappa: percentInside ? 0.46 : 0.55228475,
            layer: layer
        )

        guard !style.showsPercentBeside || glyph != nil else { return }

        // Full knockout: the system battery punches clean holes. Glyph rasterization
        // already softens edges; leaving body under the ink made 100% look grey.
        let knockout = NSColor.black
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        knockout.setFill()
        knockout.setStroke()

        if style.showsPercentInside, !metrics.text.isEmpty {
            punchCenteredText(
                metrics.text,
                font: metrics.font,
                in: metrics.digitBox,
                color: knockout,
                kern: metrics.kern,
                snapsBaseline: true,
                opticalNudgeY: percentInside ? 0.5 : 0
            )
        }

        NSGraphicsContext.restoreGraphicsState()

        if let glyph {
            switch glyph {
            case .bolt:
                if style.showsPercentInside {
                    punchChargeMark(in: metrics.glyphBox, digits: metrics.text.count, color: knockout)
                } else if layer != .charge {
                    drawChargeMark(in: body, fill: neutralFill)
                }
            }
        }
    }

    private static func drawChargeLevel(
        body: NSRect,
        cap: NSRect,
        percent: CGFloat,
        fill: MenuBarResolvedFill,
        neutralFill: MenuBarResolvedFill,
        bodyPath: NSBezierPath,
        backingAlpha: CGFloat,
        terminalAlpha: CGFloat,
        terminalKappa: CGFloat,
        layer: Layer
    ) {
        let clamped = min(1, max(0, percent))
        let capPath = terminalPath(in: cap, kappa: terminalKappa)
        let dim = neutralFill.withAlpha(terminalAlpha)

        if layer != .charge {
            NSGraphicsContext.saveGraphicsState()
            bodyPath.addClip()
            paint(neutralFill.withAlpha(backingAlpha), in: body)
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            capPath.addClip()
            paint(dim, in: cap)
            NSGraphicsContext.restoreGraphicsState()
        }

        if layer != .chrome {
            NSGraphicsContext.saveGraphicsState()
            bodyPath.addClip()
            NSBezierPath(rect: NSRect(
                x: body.minX,
                y: body.minY,
                width: body.width * clamped,
                height: body.height
            )).addClip()
            paint(fill, in: body)
            NSGraphicsContext.restoreGraphicsState()
        }

        // Template rendering blends anti-aliased edges; cut the gap so the terminal stays detached.
        if layer != .charge {
            let gap = NSRect(
                x: body.maxX,
                y: 0,
                width: max(0, cap.minX - body.maxX),
                height: max(body.maxY, cap.maxY) + 2
            )
            if gap.width > 0 {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSColor.black.setFill()
                gap.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    /// Native 23 × 12pt frame, with a separate terminal and a 1pt clear gutter.
    private static func drawOutlinedChargeLevel(
        body: NSRect,
        cap: NSRect,
        percent: CGFloat,
        fill: MenuBarResolvedFill,
        neutralFill: MenuBarResolvedFill,
        layer: Layer
    ) {
        if layer != .chrome, percent > 0 {
            NSGraphicsContext.saveGraphicsState()
            outlinedChargePath(body: body, percent: percent).addClip()
            paint(fill, in: body.insetBy(dx: 2, dy: 2))
            NSGraphicsContext.restoreGraphicsState()
        }
        if layer != .charge {
            paintOutline(in: body, fill: neutralFill)
            paintTemplate(named: "MenuBarBatteryCap", in: cap, fill: neutralFill)
        }
    }

    /// A 1pt inside stroke at half opacity, like the native frame.
    private static func paintOutline(in body: NSRect, fill: MenuBarResolvedFill) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let frame = continuousRoundedRect(body, radius: 3.35)
        NSGraphicsContext.saveGraphicsState()
        frame.addClip()
        context.addPath(frame.cgPath)
        context.setLineWidth(2)
        context.replacePathWithStrokedPath()
        context.clip()
        context.setAlpha(0.5)
        paint(fill, in: body)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func outlinedChargePath(body: NSRect, percent: CGFloat) -> NSBezierPath {
        var charged = body.insetBy(dx: 2, dy: 2)
        charged.size.width *= min(1, max(0, percent))
        return continuousRoundedRect(charged, radius: 1.5)
    }

    /// A rounded rectangle whose corners ease out of the straight edges, like
    /// SwiftUI's `RoundedRectangle(style: .continuous)`.
    private static func continuousRoundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        // Each corner spans 1.52866483 × radius along both edges.
        let span: CGFloat = 1.52866483
        let r = max(0, min(radius, min(rect.width, rect.height) / (2 * span)))
        guard r > 0 else { return NSBezierPath(rect: rect) }
        let curves: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (1.08849323, 0, 0.86840694, 0, 0.63149399, 0.07491139),
            (0.37282383, 0.16905899, 0.16905899, 0.37282383, 0.07491139, 0.63149399),
            (0, 0.86840694, 0, 1.08849323, 0, span),
        ]
        // Corner point, the direction travelled into it, and the direction leaving it.
        let corners: [(NSPoint, CGVector, CGVector)] = [
            (NSPoint(x: rect.maxX, y: rect.minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
            (NSPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0)),
            (NSPoint(x: rect.minX, y: rect.maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
            (NSPoint(x: rect.minX, y: rect.minY), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)),
        ]
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + span * r, y: rect.minY))
        for (corner, incoming, outgoing) in corners {
            func point(_ before: CGFloat, _ after: CGFloat) -> NSPoint {
                NSPoint(
                    x: corner.x - incoming.dx * before * r + outgoing.dx * after * r,
                    y: corner.y - incoming.dy * before * r + outgoing.dy * after * r
                )
            }
            path.line(to: point(span, 0))
            for c in curves {
                path.curve(to: point(c.4, c.5), controlPoint1: point(c.0, c.1), controlPoint2: point(c.2, c.3))
            }
        }
        path.close()
        return path
    }

    private static func paintTemplate(named name: String, in rect: NSRect, fill: MenuBarResolvedFill) {
        guard let image = NSImage(named: name),
              let mask = image.cgImage(forProposedRect: nil, context: .current, hints: nil),
              let context = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        context.clip(to: rect, mask: mask)
        paint(fill, in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawOutlinedText(metrics: Metrics, percent: CGFloat, fill: MenuBarResolvedFill) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        punchCenteredText(metrics.text, font: metrics.font, in: metrics.digitBox)
        NSGraphicsContext.restoreGraphicsState()

        // Invert the digits over the charge, and paint them normally over empty space.
        let empty = NSBezierPath(rect: metrics.body.insetBy(dx: 2, dy: 2))
        if percent > 0 { empty.append(outlinedChargePath(body: metrics.body, percent: percent)) }
        empty.windingRule = .evenOdd
        NSGraphicsContext.saveGraphicsState()
        empty.addClip()
        punchCenteredText(metrics.text, font: metrics.font, in: metrics.digitBox, color: fill.right)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawOutlinedChargeMark(in box: NSRect, compact: Bool, fill: MenuBarResolvedFill) {
        let rect = outlinedChargeMarkRect(in: box, compact: compact)
        NSImage(named: "MenuBarBatteryBoltMask")?.draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1)
        paintTemplate(named: "MenuBarBatteryBolt", in: rect, fill: fill)
    }

    private static func punchOutlinedChargeMark(in box: NSRect, compact: Bool) {
        let rect = outlinedChargeMarkRect(in: box, compact: compact)
        NSImage(named: "MenuBarBatteryBoltMask")?.draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1)
    }

    private static func outlinedChargeMarkRect(in box: NSRect, compact: Bool) -> NSRect {
        let width: CGFloat = compact ? 5.8 : 11
        let height = width * 14 / 11
        return NSRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
    }

    /// A flat inner edge and a narrow, rounded outer edge, detached from the body.
    private static func terminalPath(in rect: NSRect, kappa: CGFloat) -> NSBezierPath {
        let quarterArc = kappa
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.curve(
            to: NSPoint(x: rect.maxX, y: rect.midY),
            controlPoint1: NSPoint(x: rect.minX + rect.width * quarterArc, y: rect.maxY),
            controlPoint2: NSPoint(x: rect.maxX, y: rect.midY + rect.height / 2 * quarterArc)
        )
        path.curve(
            to: NSPoint(x: rect.minX, y: rect.minY),
            controlPoint1: NSPoint(x: rect.maxX, y: rect.midY - rect.height / 2 * quarterArc),
            controlPoint2: NSPoint(x: rect.minX + rect.width * quarterArc, y: rect.minY)
        )
        path.close()
        return path
    }

    private static func paint(_ fill: MenuBarResolvedFill, in rect: NSRect) {
        if samePaint(fill) {
            fill.left.setFill()
            rect.fill()
            return
        }
        NSGradient(starting: fill.left, ending: fill.right)?.draw(in: rect, angle: 0)
    }

    private static func samePaint(_ fill: MenuBarResolvedFill) -> Bool {
        guard
            let left = fill.left.usingColorSpace(.sRGB),
            let right = fill.right.usingColorSpace(.sRGB)
        else {
            return fill.left == fill.right
        }
        return abs(left.redComponent - right.redComponent) < 0.004
            && abs(left.greenComponent - right.greenComponent) < 0.004
            && abs(left.blueComponent - right.blueComponent) < 0.004
            && abs(left.alphaComponent - right.alphaComponent) < 0.004
    }

    private static func punchCenteredText(
        _ text: String,
        font: NSFont,
        in box: NSRect,
        color: NSColor = .black,
        kern: CGFloat = 0,
        snapsBaseline: Bool = false,
        opticalNudgeY: CGFloat = 0
    ) {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color,
                .kern: kern
            ])
        )
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        // Positive nudge moves ink down in AppKit space so "100" sits like the system battery.
        let baseline = box.midY - bounds.midY - opticalNudgeY
        cg.textPosition = CGPoint(
            x: box.midX - bounds.midX,
            // The 2x raster keeps flat digit edges on whole pixels.
            y: snapsBaseline ? (baseline * 2).rounded() / 2 : baseline
        )
        CTLineDraw(line, cg)
        cg.restoreGState()
    }

    /// The large menu-bar bolt crosses the body edges, with a transparent halo
    /// separating its filled silhouette from the battery and the wallpaper.
    private static func drawChargeMark(in body: NSRect, fill: MenuBarResolvedFill) {
        let origin = NSPoint(x: body.midX - 4.75, y: body.midY - 7)
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: origin.x + x, y: origin.y + y)
        }
        let bolt = NSBezierPath()
        bolt.move(to: point(7.2, 13.8))
        bolt.curve(to: point(6.7, 13.8), controlPoint1: point(7.1, 14.1), controlPoint2: point(6.9, 14.1))
        bolt.line(to: point(0.6, 6.8))
        bolt.curve(to: point(1.1, 5.4), controlPoint1: point(-0.1, 6.1), controlPoint2: point(0.1, 5.4))
        bolt.line(to: point(4.4, 5.4))
        bolt.line(to: point(2.3, 0.5))
        bolt.curve(to: point(2.9, 0.1), controlPoint1: point(2.1, 0), controlPoint2: point(2.6, -0.2))
        bolt.line(to: point(9.4, 7.4))
        bolt.curve(to: point(8.9, 8.8), controlPoint1: point(10.1, 8.1), controlPoint2: point(9.9, 8.8))
        bolt.line(to: point(5.6, 8.8))
        bolt.close()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setFill()
        NSColor.black.setStroke()
        bolt.lineWidth = 2.2
        bolt.lineJoinStyle = .round
        bolt.fill()
        bolt.stroke()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        bolt.addClip()
        paint(fill, in: body.insetBy(dx: 0, dy: -2))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Traced from the macOS battery's 2x inside bolt: thin stems whose edges run
    /// straight through the middle bar, blunt tips, symmetric about the centre.
    private static let insideBoltOutline: [NSPoint] = [
        NSPoint(x: 1.13, y: 3.0), NSPoint(x: 0.67, y: 3.0), NSPoint(x: -2.06, y: -0.5), NSPoint(x: -0.21, y: -0.5),
        NSPoint(x: -1.13, y: -3.0), NSPoint(x: -0.67, y: -3.0), NSPoint(x: 2.06, y: 0.5), NSPoint(x: 0.21, y: 0.5),
    ]

    private static func insideBoltInkSize(digits: Int) -> NSSize {
        // The system shrinks the bolt to 12px tall beside three digits, ~15px beside two.
        let height: CGFloat = digits >= 3 ? 6.2 : 7.3
        return NSSize(width: height * 4.12 / 6, height: height)
    }

    private static func punchChargeMark(in box: NSRect, digits: Int, color: NSColor) {
        let scale = insideBoltInkSize(digits: digits).height / 6
        let bolt = NSBezierPath()
        for (i, point) in insideBoltOutline.enumerated() {
            let p = NSPoint(x: box.midX + point.x * scale, y: box.midY + point.y * scale)
            if i == 0 { bolt.move(to: p) } else { bolt.line(to: p) }
        }
        bolt.close()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        color.setFill()
        bolt.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
