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

        let height: CGFloat = 13
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
        let capWidth: CGFloat = 1.6
        let capHeight: CGFloat = 5.4
        let capGap: CGFloat = 1.22
        let showsText = style.showsPercentInside
        let text = showsText ? "\(percent)" : ""
        let digits = text.count
        let font = percentFont(size: digits >= 3 ? 8.6 : 9.4)
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
            if !showsText { return 21.5 }
            return digits >= 3 ? 24.0 : 22.5
        }()
        let body = NSRect(x: 0.35, y: bodyY, width: bodyWidth, height: bodyHeight)
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
                fill: fill,
                radius: radius
            )
        } else {
            drawChargeLevel(
                body: body,
                cap: metrics.cap,
                percent: percent,
                fill: fill,
                radius: radius
            )
        }

        guard !style.showsPercentBeside || glyph != nil else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setFill()
        NSColor.black.setStroke()

        if style.showsPercentInside, !metrics.text.isEmpty {
            punchCenteredText(metrics.text, font: metrics.font, in: metrics.digitBox)
        }

        if let glyph {
            let target = style.showsPercentInside ? metrics.glyphBox : body
            switch glyph {
            case .bolt: punchChargeMark(in: target)
            }
        }

        NSGraphicsContext.restoreGraphicsState()
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
        let capRadius = min(cap.width, cap.height) / 2
        let capPath = NSBezierPath(roundedRect: cap, xRadius: capRadius, yRadius: capRadius)
        let dim = fill.withAlpha(0.62)

        NSGraphicsContext.saveGraphicsState()
        bodyPath.addClip()
        paint(dim, in: body)
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

        if clamped >= 0.995 {
            NSGraphicsContext.saveGraphicsState()
            capPath.addClip()
            paint(fill, in: cap)
            NSGraphicsContext.restoreGraphicsState()
        }

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

    /// Apple-style outlined battery: hollow body with a stroke, charge fill inset inside.
    private static func drawOutlinedChargeLevel(
        body: NSRect,
        cap: NSRect,
        percent: CGFloat,
        fill: MenuBarResolvedFill,
        radius: CGFloat
    ) {
        let clamped = min(1, max(0, percent))
        let line: CGFloat = 1.15
        let inset = line / 2 + 0.35
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
        let inner = body.insetBy(dx: inset, dy: inset)
        let innerRadius = max(0.6, radius - inset)
        let innerPath = NSBezierPath(roundedRect: inner, xRadius: innerRadius, yRadius: innerRadius)
        let capRadius = min(cap.width, cap.height) / 2
        let capPath = NSBezierPath(roundedRect: cap, xRadius: capRadius, yRadius: capRadius)
        let dim = fill.withAlpha(0.62)

        // Same pad as the borderless body, so knocked-out digits stay readable
        // where the charge has already been used.
        NSGraphicsContext.saveGraphicsState()
        innerPath.addClip()
        paint(dim, in: inner)
        NSGraphicsContext.restoreGraphicsState()

        if clamped > 0.004 {
            NSGraphicsContext.saveGraphicsState()
            innerPath.addClip()
            NSBezierPath(rect: NSRect(
                x: inner.minX,
                y: inner.minY,
                width: inner.width * clamped,
                height: inner.height
            )).addClip()
            paint(fill, in: inner)
            NSGraphicsContext.restoreGraphicsState()
        }

        fill.right.setStroke()
        bodyPath.lineWidth = line
        bodyPath.lineJoinStyle = .round
        bodyPath.stroke()

        NSGraphicsContext.saveGraphicsState()
        capPath.addClip()
        paint(fill, in: cap)
        NSGraphicsContext.restoreGraphicsState()

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

    private static func punchCenteredText(_ text: String, font: NSFont, in box: NSRect) {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: NSColor.black
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
