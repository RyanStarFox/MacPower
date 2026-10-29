import SwiftUI

struct StatusRingView: View {
    var percent: Double
    var fillLeft: Color
    var fillRight: Color
    var caption: String
    var accessibilityName: String
    var glyph: GlyphSlot
    var glyphTint: Color? = nil
    var accessibilityValue: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.readmeGalleryCapture) private var readmeGalleryCapture
    /// The first layout often corrects the ring's position. Animating progress
    /// on that frame drags the whole ring into place.
    @State private var animateProgress = false

    private let diameter: CGFloat = 58
    private let lineWidth: CGFloat = 7

    /// Match caption ink; hierarchical SF battery fills go white on glass.
    private var glyphInk: Color {
        glyphTint ?? (colorScheme == .dark ? Color(white: 0.92) : Color(white: 0.14))
    }

    var body: some View {
        let clamped = min(100, max(0, percent))
        let progress = clamped / 100
        let scale = CGFloat(glyph.normalizedScale)
        VStack(spacing: 6) {
            ZStack {
                glassTrack

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        ringStroke(progress: progress),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter - lineWidth, height: diameter - lineWidth)
                    .animation(animateProgress ? .smooth(duration: 0.85) : nil, value: progress)
                    .animation(animateProgress ? .smooth(duration: 0.85) : nil, value: fillLeft)
                    .animation(animateProgress ? .smooth(duration: 0.85) : nil, value: fillRight)

                GlyphSlotView(
                    slot: glyph,
                    systemPointSize: 17 * scale,
                    assetSide: 20 * scale,
                    prefersMonochrome: true,
                    ink: glyphInk
                )
            }
            .frame(width: diameter, height: diameter)

            Text(caption)
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .autoFittingCaption()
        }
        .frame(maxWidth: .infinity)
        .onAppear { DispatchQueue.main.async { animateProgress = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityValue ?? "\(accessibilityName) \(Int(clamped.rounded()))%"))
    }

    private func ringStroke(progress: Double) -> AnyShapeStyle {
        if fillLeft == fillRight {
            return AnyShapeStyle(fillLeft)
        }
        let sweep = max(progress, 0.002)
        return AnyShapeStyle(
            AngularGradient(
                colors: [fillLeft, fillRight],
                center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(360 * sweep)
            )
        )
    }

    @ViewBuilder
    private var glassTrack: some View {
        let track = Circle()
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .frame(width: diameter - lineWidth, height: diameter - lineWidth)
        if readmeGalleryCapture {
            // Bitmap capture cannot sample Liquid Glass; keep a light track.
            Color(white: 0.88)
                .frame(width: diameter, height: diameter)
                .mask { track }
        } else if #available(macOS 26.0, *) {
            // Real glass + stroke mask (unchanged from the macOS 26+ design).
            Color.clear
                .frame(width: diameter, height: diameter)
                .macPowerGlassEffect(.regular, in: Circle())
                .mask { track }
        } else {
            // Material-in-background + mask often goes fully transparent on 14/15;
            // stroke the material directly as a visible track.
            Circle()
                .stroke(.ultraThinMaterial, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .frame(width: diameter - lineWidth, height: diameter - lineWidth)
        }
    }
}

/// Left half is download, right half is upload. Each half grows from the top.
struct SpeedPairRingView: View {
    var downloadProgress: Double
    var uploadProgress: Double
    var downloadCaption: String
    var uploadCaption: String
    var accessibilityValue: String
    var downloadColor: Color
    var uploadColor: Color
    @Environment(\.readmeGalleryCapture) private var readmeGalleryCapture
    @State private var animateProgress = false

    private let diameter: CGFloat = 58
    private let lineWidth: CGFloat = 7

    var body: some View {
        let down = min(1, max(0, downloadProgress))
        let up = min(1, max(0, uploadProgress))
        VStack(spacing: 6) {
            ZStack {
                halfTrack(from: 0.5, to: 1)
                halfTrack(from: 0, to: 0.5)
                halfFill(from: 1 - 0.5 * down, to: 1, color: downloadColor)
                    .animation(animateProgress ? .smooth(duration: 0.85) : nil, value: down)
                halfFill(from: 0, to: 0.5 * up, color: uploadColor)
                    .animation(animateProgress ? .smooth(duration: 0.85) : nil, value: up)
                HStack(spacing: 0) {
                    Image(systemName: "arrow.down")
                        .foregroundStyle(downloadColor)
                        .frame(maxWidth: .infinity)
                    Image(systemName: "arrow.up")
                        .foregroundStyle(uploadColor)
                        .frame(maxWidth: .infinity)
                }
                .font(.system(size: 11, weight: .bold))
                .frame(width: diameter - lineWidth * 2 - 6)
            }
            .frame(width: diameter, height: diameter)

            VStack(spacing: 0) {
                Text("↓ \(downloadCaption)").autoFittingCaption(minimumScale: 0.7)
                Text("↑ \(uploadCaption)").autoFittingCaption(minimumScale: 0.7)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .onAppear { DispatchQueue.main.async { animateProgress = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityValue))
    }

    private func halfFill(from: Double, to: Double, color: Color) -> some View {
        Circle()
            .trim(from: from, to: max(from, to))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: diameter - lineWidth, height: diameter - lineWidth)
    }

    @ViewBuilder
    private func halfTrack(from: Double, to: Double) -> some View {
        let arc = Circle()
            .trim(from: from, to: to)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .rotationEffect(.degrees(-90))
            .frame(width: diameter - lineWidth, height: diameter - lineWidth)
        if readmeGalleryCapture {
            Color(white: 0.88)
                .frame(width: diameter, height: diameter)
                .mask { arc }
        } else if #available(macOS 26.0, *) {
            Color.clear
                .frame(width: diameter, height: diameter)
                .macPowerGlassEffect(.regular, in: Circle())
                .mask { arc }
        } else {
            Circle()
                .trim(from: from, to: to)
                .stroke(.ultraThinMaterial, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .frame(width: diameter - lineWidth, height: diameter - lineWidth)
        }
    }
}

extension View {
    func autoFittingCaption(minimumScale: CGFloat = 0.6) -> some View {
        self
            .lineLimit(1)
            .minimumScaleFactor(minimumScale)
            .allowsTightening(true)
    }
}
