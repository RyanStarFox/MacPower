import AppKit
import SwiftUI

/// Renders a `GlyphSlot` for rings, flow nodes, and settings previews.
struct GlyphSlotView: View {
    var slot: GlyphSlot
    var systemPointSize: CGFloat = 17
    /// Layout box for every glyph so SF Symbols, assets, and uploads share one size.
    /// Callers fold user zoom into this; built-in `opticalScale` is applied here.
    var assetSide: CGFloat = 20
    var weight: Font.Weight = .semibold
    /// Flow nodes should match watt-label ink; rings keep hierarchical depth unless asked.
    var prefersMonochrome: Bool = false
    /// Absolute ink for glass overlays. Semantic `.primary` goes vibrant/white on
    /// Liquid Glass, which made SF Symbol batteries white while ChargeMark stayed black.
    var ink: Color? = nil

    var body: some View {
        // Built-in assets (GPUMark) ink more of their canvas than SF Symbols, so
        // draw them slightly smaller inside the shared layout box.
        let drawSide = assetSide * CGFloat(slot.normalizedOpticalScale)
        let tint = ink ?? Color.primary
        Group {
            switch slot.source {
            case .system:
                if prefersMonochrome, ink != nil,
                   let image = Self.rasterizedSystemSymbol(
                    name: slot.name,
                    side: drawSide,
                    pointSize: systemPointSize,
                    weight: weight
                   ) {
                    // Bake SF Symbols to a template bitmap. Live symbols on Liquid
                    // Glass still went white (battery.100percent) even with monochrome
                    // + absolute ink; ChargeMark assets never had that problem.
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(tint)
                        .frame(width: drawSide, height: drawSide)
                } else {
                    Image(systemName: slot.name)
                        .font(.system(size: systemPointSize, weight: weight))
                        .symbolRenderingMode(prefersMonochrome ? .monochrome : .hierarchical)
                        .foregroundStyle(tint)
                }
            case .asset:
                if let image = Self.rasterized(named: slot.name, side: drawSide, template: slot.template) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .renderingMode(slot.template ? .template : .original)
                        .scaledToFit()
                        .foregroundStyle(tint)
                        .frame(width: drawSide, height: drawSide)
                } else {
                    Image(systemName: "questionmark")
                        .font(.system(size: systemPointSize, weight: weight))
                        .foregroundStyle(.secondary)
                }
            case .custom:
                if let source = CustomIconStore.image(id: slot.name),
                   let image = Self.rasterized(source, side: drawSide, template: slot.template) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .renderingMode(slot.template ? .template : .original)
                        .scaledToFit()
                        .foregroundStyle(tint)
                        .frame(width: drawSide, height: drawSide)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: systemPointSize * 0.85, weight: weight))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: assetSide, height: assetSide)
        .clipped()
    }

    /// Bake assets down to `side`×`side` so AppKit Menus cannot promote the PNG's
    /// intrinsic pixel size (GPUMark is 200×200, ChargeMark is 132×214).
    private static func rasterized(named name: String, side: CGFloat, template: Bool) -> NSImage? {
        guard let source = NSImage(named: name) else { return nil }
        return rasterized(source, side: side, template: template)
    }

    private static func rasterizedSystemSymbol(
        name: String,
        side: CGFloat,
        pointSize: CGFloat,
        weight: Font.Weight
    ) -> NSImage? {
        // Monochrome keeps knockout regions (the laptop screen). A one-color
        // palette paints those layers solid, so laptopcomputer loses its display.
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: nsWeight(weight))
        guard let source = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        return rasterized(source, side: side, template: true)
    }

    private static func nsWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .semibold
        }
    }

    private static func rasterized(_ source: NSImage, side: CGFloat, template: Bool) -> NSImage? {
        let pixels = max(1, Int((side * 2).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            let src = source.size
            let scale = min(side / max(src.width, 1), side / max(src.height, 1))
            let draw = NSSize(width: src.width * scale, height: src.height * scale)
            let origin = NSPoint(x: (side - draw.width) / 2, y: (side - draw.height) / 2)
            source.draw(
                in: NSRect(origin: origin, size: draw),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        image.isTemplate = template
        return image
    }
}
