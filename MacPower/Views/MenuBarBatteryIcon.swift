import CoreText
import AppKit

enum MenuBarBatteryRenderer {
    static func image(
        snapshot: PowerSnapshot,
        style: MenuBarIconStyle,
        fill: MenuBarResolvedFill,
        appearance: NSAppearance,
        showChargeGlyphs: Bool
    ) -> NSImage {
        let percent = Int(snapshot.percent.rounded(.towardZero))
        let charging = snapshot.flowMode == .charging
        let plugged = snapshot.flowMode == .adapterHold || snapshot.flowMode == .underpowered
        let glyph: MenuBarGlyph? = {
            guard showChargeGlyphs else { return nil }
            if charging || plugged { return .bolt }
            return nil
        }()

        let height: CGFloat = 16
        let metrics = layout(percent: percent, style: style, glyph: glyph, height: height)
        let size = NSSize(width: metrics.totalWidth, height: height)
        let image = rasterImage(size: size, appearance: appearance) { rect in
            drawBattery(
                in: rect,
                metrics: metrics,
                percent: snapshot.percent / 100,
                style: style,
                fill: fill,
                glyph: glyph
            )
        }
        image.isTemplate = fill.isTemplate
        return image
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
        var glyphBox: NSRect
    }

    private static func percentFont(size: CGFloat) -> NSFont {
        if let pingfang = NSFont(name: "PingFangSC-Medium", size: size) {
            return pingfang
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
        let capWidth: CGFloat = style.isOutlined ? 2 : 1.5
        let capHeight: CGFloat = style.isOutlined ? bodyHeight : 4
        let capGap: CGFloat = style.isOutlined ? 1 : 1.22
        let showsText = style.showsPercentInside
        let text = showsText ? "\(percent)" : ""
        let digits = text.count
        let fontSize: CGFloat = {
            // The outlined body keeps a 2pt gutter, so the shared size fills the interior.
            if style.isOutlined, showsText { return digits >= 3 ? 7.2 : 8.0 }
            return digits >= 3 ? 8.6 : 9.4
        }()
        let font = percentFont(size: fontSize)
        let textSize = text.isEmpty
            ? NSSize.zero
            : (text as NSString).size(withAttributes: [.font: font])
        let glyphAdvance: CGFloat
        switch glyph {
        case .bolt: glyphAdvance = showsText ? 5.8 : 8.8
        case nil: glyphAdvance = 0
        }
        let gap: CGFloat = (showsText && glyph != nil) ? 0.45 : 0
        let groupWidth = (showsText ? textSize.width : 0) + gap + glyphAdvance
        let bodyWidth: CGFloat = {
            if !showsText { return 23 }
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
            glyphBox: glyphBox
        )
    }

    private static func drawBattery(
        in rect: NSRect,
        metrics: Metrics,
        percent: CGFloat,
        style: MenuBarIconStyle,
        fill: MenuBarResolvedFill,
        glyph: MenuBarGlyph?
    ) {
        let body = metrics.body
        let radius: CGFloat = 3.8
        if style.isOutlined {
            drawOutlinedChargeLevel(
                body: body,
                cap: metrics.cap,
                percent: percent,
                fill: fill
            )
            if style.showsPercentInside {
                drawOutlinedText(metrics: metrics, percent: percent, fill: fill)
            }
            if glyph != nil {
                let target = style.showsPercentInside ? metrics.glyphBox : body
                drawOutlinedChargeMark(in: target, compact: style.showsPercentInside, fill: fill)
            }
            return
        }
        drawChargeLevel(body: body, cap: metrics.cap, percent: percent, fill: fill, radius: radius)

        guard !style.showsPercentBeside || glyph != nil else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setFill()
        NSColor.black.setStroke()

        if style.showsPercentInside, !metrics.text.isEmpty {
            punchCenteredText(metrics.text, font: metrics.font, in: metrics.digitBox)
        }

        NSGraphicsContext.restoreGraphicsState()

        if let glyph {
            switch glyph {
            case .bolt:
                if style.showsPercentInside {
                    punchChargeMark(in: metrics.glyphBox)
                } else {
                    drawChargeMark(in: body, fill: fill)
                }
            }
        }
    }

    private static func drawChargeLevel(
        body: NSRect,
        cap: NSRect,
        percent: CGFloat,
        fill: MenuBarResolvedFill,
        radius: CGFloat
    ) {
        let clamped = min(1, max(0, percent))
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
        let capPath = terminalPath(in: cap)
        let dim = fill.withAlpha(0.62)

        NSGraphicsContext.saveGraphicsState()
        bodyPath.addClip()
        paint(fill.withAlpha(0.52), in: body)
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        capPath.addClip()
        paint(dim, in: cap)
        NSGraphicsContext.restoreGraphicsState()

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

        // Template rendering blends anti-aliased edges; cut the gap so the terminal stays detached.
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

    /// Native 23 × 12pt frame, with a separate terminal and a 1pt clear gutter.
    private static func drawOutlinedChargeLevel(
        body: NSRect,
        cap: NSRect,
        percent: CGFloat,
        fill: MenuBarResolvedFill
    ) {
        if percent > 0 {
            NSGraphicsContext.saveGraphicsState()
            outlinedChargePath(body: body, percent: percent).addClip()
            paint(fill, in: body.insetBy(dx: 2, dy: 2))
            NSGraphicsContext.restoreGraphicsState()
        }
        paintTemplate(named: "MenuBarBatteryOutline", in: body, fill: fill)
        paintTemplate(named: "MenuBarBatteryCap", in: cap, fill: fill)
    }

    private static func outlinedChargePath(body: NSRect, percent: CGFloat) -> NSBezierPath {
        var charged = body.insetBy(dx: 2, dy: 2)
        charged.size.width *= min(1, max(0, percent))
        return NSBezierPath(roundedRect: charged, xRadius: 1.5, yRadius: 1.5)
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
        let width: CGFloat = compact ? 5.8 : 11
        let height = width * 14 / 11
        let rect = NSRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
        NSImage(named: "MenuBarBatteryBoltMask")?.draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1)
        paintTemplate(named: "MenuBarBatteryBolt", in: rect, fill: fill)
    }

    /// A flat inner edge and a narrow, rounded outer edge, detached from the body.
    private static func terminalPath(in rect: NSRect) -> NSBezierPath {
        let quarterArc: CGFloat = 0.55228475
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

    private static func punchCenteredText(_ text: String, font: NSFont, in box: NSRect, color: NSColor = .black) {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color
            ])
        )
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        cg.textPosition = CGPoint(
            x: box.midX - bounds.midX,
            y: box.midY - bounds.midY
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

    private static func punchChargeMark(in box: NSRect) {
        guard let named = NSImage(named: "ChargeMark") else { return }
        let maxH = min(9.6, box.height - 1.2)
        let maxW = min(box.width - 0.4, 7.4)
        let aspect = named.size.width / max(named.size.height, 1)
        var height = maxH
        var width = height * aspect
        if width > maxW {
            width = maxW
            height = width / aspect
        }
        let rect = NSRect(
            x: box.midX - width / 2,
            y: box.midY - height / 2,
            width: width,
            height: height
        )
        named.draw(
            in: rect,
            from: .zero,
            operation: .destinationOut,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}
