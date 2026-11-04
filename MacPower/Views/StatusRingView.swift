import AppKit
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

    static let diameter: CGFloat = 58
    static let lineWidth: CGFloat = 7
    static let glyphPointSize: CGFloat = 17
    static let glyphAssetSide: CGFloat = 20

    private var diameter: CGFloat { Self.diameter }
    private var lineWidth: CGFloat { Self.lineWidth }

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
                    systemPointSize: Self.glyphPointSize * scale,
                    assetSide: Self.glyphAssetSide * scale,
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
        .onAppear { armProgressAnimation($animateProgress) }
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

            VStack(spacing: 1) {
                Text("↓ \(downloadCaption)").autoFittingCaption(minimumScale: 0.7)
                Text("↑ \(uploadCaption)").autoFittingCaption(minimumScale: 0.7)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.primary)
            // Two lines. A flexible text measurement can report one line, and the
            // second line then draws over the time estimate under the rings.
            .frame(height: 24, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear { armProgressAnimation($animateProgress) }
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

/// Two halves, each with its own icon and color, matching the upload/download ring.
struct PairRingView: View {
    var leftProgress: Double
    var rightProgress: Double
    var leftColor: Color
    var rightColor: Color
    var leftGlyph: GlyphSlot
    var rightGlyph: GlyphSlot
    var leftCaption: String
    var rightCaption: String
    var accessibilityValue: String
    @Environment(\.readmeGalleryCapture) private var readmeGalleryCapture
    @State private var animateProgress = false

    private let diameter: CGFloat = StatusRingView.diameter
    private let lineWidth: CGFloat = StatusRingView.lineWidth

    var body: some View {
        let left = min(1, max(0, leftProgress))
        let right = min(1, max(0, rightProgress))
        VStack(spacing: 6) {
            ZStack {
                halfTrack(from: 0.5, to: 1)
                halfTrack(from: 0, to: 0.5)
                halfFill(from: 1 - 0.5 * left, to: 1, color: leftColor)
                    .animation(animateProgress ? .smooth(duration: 0.85) : nil, value: left)
                halfFill(from: 0, to: 0.5 * right, color: rightColor)
                    .animation(animateProgress ? .smooth(duration: 0.85) : nil, value: right)
                HStack(spacing: 0) {
                    GlyphSlotView(
                        slot: leftGlyph,
                        systemPointSize: 13,
                        assetSide: 15,
                        prefersMonochrome: true,
                        ink: leftColor
                    )
                    .frame(maxWidth: .infinity)
                    GlyphSlotView(
                        slot: rightGlyph,
                        systemPointSize: 13,
                        assetSide: 15,
                        prefersMonochrome: true,
                        ink: rightColor
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(width: diameter - lineWidth * 2 - 4)
            }
            .frame(width: diameter, height: diameter)

            VStack(spacing: 1) {
                Text(leftCaption).autoFittingCaption(minimumScale: 0.7)
                Text(rightCaption).autoFittingCaption(minimumScale: 0.7)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.primary)
            .frame(height: 24, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear { armProgressAnimation($animateProgress) }
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

/// Three equal arcs. Each one grows from its own center toward both ends.
struct MeterRingView: View {
    var segments: [MeterSegment]
    var glyph: GlyphSlot
    var glyphTint: Color?
    var accessibilityValue: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.readmeGalleryCapture) private var readmeGalleryCapture
    @State private var animateProgress = false

    struct MeterSegment: Equatable {
        var progress: Double
        var color: Color
        var caption: String
    }

    private let diameter: CGFloat = StatusRingView.diameter
    private let lineWidth: CGFloat = StatusRingView.lineWidth
    /// Clockwise from the top, matching the rotated ring trim.
    private let centers = [60.0, 180.0, 300.0]

    private var glyphInk: Color {
        glyphTint ?? (colorScheme == .dark ? Color(white: 0.92) : Color(white: 0.14))
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ForEach(segments.indices, id: \.self) { index in
                    arcTrack(index: index)
                    arcFill(index: index, segment: segments[index])
                }
                GlyphSlotView(
                    slot: glyph,
                    systemPointSize: StatusRingView.glyphPointSize * CGFloat(glyph.normalizedScale),
                    assetSide: StatusRingView.glyphAssetSide * CGFloat(glyph.normalizedScale),
                    prefersMonochrome: true,
                    ink: glyphInk
                )
            }
            .frame(width: diameter, height: diameter)

            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    Text(segments.count > 2 ? segments[2].caption : "")
                        .autoFittingCaption(minimumScale: 0.65)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(segments.first?.caption ?? "")
                        .autoFittingCaption(minimumScale: 0.65)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(segments.count > 1 ? segments[1].caption : "")
                    .autoFittingCaption(minimumScale: 0.65)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.primary)
            .frame(height: 24, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear { armProgressAnimation($animateProgress) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityValue))
    }

    /// Half of one arc. The three arcs meet, so the track is one ring.
    private var halfSpan: Double {
        1.0 / 6.0
    }

    private func centerTrim(index: Int) -> Double {
        centers[index % centers.count] / 360
    }

    @ViewBuilder
    private func arcFill(index: Int, segment: MeterSegment) -> some View {
        let amount = min(1, max(0, segment.progress))
        let reach = halfSpan * amount
        let center = centerTrim(index: index)
        Circle()
            .trim(from: center - reach, to: center + max(reach, 0.001))
            .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: diameter - lineWidth, height: diameter - lineWidth)
            .opacity(amount > 0.001 ? 1 : 0)
            .animation(animateProgress ? .smooth(duration: 0.85) : nil, value: amount)
    }

    @ViewBuilder
    private func arcTrack(index: Int) -> some View {
        let center = centerTrim(index: index)
        let arc = Circle()
            .trim(from: center - halfSpan, to: center + halfSpan)
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
                .trim(from: center - halfSpan, to: center + halfSpan)
                .stroke(.ultraThinMaterial, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .frame(width: diameter - lineWidth, height: diameter - lineWidth)
        }
    }
}

extension RingIconRGB {
    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    init(color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB)
        self.init(
            red: Double(converted?.redComponent ?? 0),
            green: Double(converted?.greenComponent ?? 0),
            blue: Double(converted?.blueComponent ?? 0)
        )
    }
}

private func armProgressAnimation(_ flag: Binding<Bool>) {
    // One turn is not enough: the popover's second layout still moves the
    // ring after the first appear. Arming .smooth on that frame eases the
    // whole ring up into its slot. Wait until that placement has committed.
    DispatchQueue.main.async {
        DispatchQueue.main.async {
            flag.wrappedValue = true
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
