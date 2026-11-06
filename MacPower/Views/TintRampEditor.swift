import AppKit
import SwiftUI

// The color ramp shared by the menu bar, energy flow and ring color pages: one
// bar from 0% to 100%, a white handle at every split point that drags, and a
// popover per segment for its effect and colors.

extension MenuBarTintBand {
    /// The four colors that describe this band along its own range. A drawn
    /// segment shows the icon's left side on top and its right side below.
    var rampSwatches: (leftLow: MenuBarTintSwatch, leftHigh: MenuBarTintSwatch, rightLow: MenuBarTintSwatch, rightHigh: MenuBarTintSwatch) {
        switch blend {
        case .constant: (highRight, highRight, highRight, highRight)
        case .slide: (lowRight, highRight, lowRight, highRight)
        case .gradient: (highLeft, highLeft, highRight, highRight)
        case .slideGradient: (lowLeft, highLeft, lowRight, highRight)
        }
    }

    var rampIsSplit: Bool {
        let s = rampSwatches
        return s.leftLow != s.rightLow || s.leftHigh != s.rightHigh
    }

    var rampFollowsMenuBar: Bool {
        let s = rampSwatches
        return s.leftLow.followsMenuBar && s.leftHigh.followsMenuBar
            && s.rightLow.followsMenuBar && s.rightHigh.followsMenuBar
    }
}

/// Whether the colors step from one segment to the next or slide within each.
enum TintTransition: String, CaseIterable, Identifiable, Sendable {
    case stepped
    case smooth

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .stepped: "settings.tint.transition.stepped"
        case .smooth: "settings.tint.transition.smooth"
        }
    }
}

/// Band arithmetic the ramp needs, independent of which scheme owns the bands.
enum TintRamp {
    static func sorted(_ bands: [MenuBarTintBand]) -> [MenuBarTintBand] {
        bands.sorted { $0.throughPercent < $1.throughPercent }
    }

    static func lower(at index: Int, in sorted: [MenuBarTintBand]) -> Int {
        index == 0 ? 0 : sorted[index - 1].throughPercent
    }

    /// Where the split point at the top of band `index` may move to.
    static func boundaryRange(at index: Int, in sorted: [MenuBarTintBand]) -> ClosedRange<Int> {
        let low = index == 0 ? 1 : sorted[index - 1].throughPercent + 1
        let high = index + 1 < sorted.count ? sorted[index + 1].throughPercent - 1 : 99
        return low <= high ? low...high : high...high
    }

    static func moving(_ id: UUID, to percent: Int, in bands: [MenuBarTintBand]) -> [MenuBarTintBand] {
        bands.map { band in
            guard band.id == id else { return band }
            var next = band
            next.throughPercent = percent
            return next
        }
    }

    static func replacing(_ band: MenuBarTintBand, in bands: [MenuBarTintBand]) -> [MenuBarTintBand] {
        bands.map { $0.id == band.id ? band : $0 }
    }

    /// Removes a band; the neighbor above takes over its range, or the one below
    /// when it was the top band.
    static func removing(_ id: UUID, from bands: [MenuBarTintBand]) -> [MenuBarTintBand] {
        guard bands.count > 1 else { return bands }
        var ordered = sorted(bands.filter { $0.id != id })
        ordered[ordered.count - 1].throughPercent = 100
        return ordered
    }

    /// Splits the widest segment in half without changing how anything looks.
    static func addingBoundary(to bands: [MenuBarTintBand]) -> (bands: [MenuBarTintBand], newID: UUID)? {
        let ordered = sorted(bands)
        guard ordered.count < 8 else { return nil }
        var widest: Int?
        var widestSpan = 1
        for index in ordered.indices {
            let span = ordered[index].throughPercent - lower(at: index, in: ordered)
            if span > widestSpan {
                widest = index
                widestSpan = span
            }
        }
        guard let index = widest else { return nil }
        let original = ordered[index]
        let middle = lower(at: index, in: ordered) + widestSpan / 2
        var below = original
        below.id = UUID()
        below.throughPercent = middle
        var above = original
        if original.blend.slides {
            let midLeft = MenuBarTintMix.mix(original.lowLeft, original.highLeft, t: 0.5)
            let midRight = MenuBarTintMix.mix(original.lowRight, original.highRight, t: 0.5)
            below.highLeft = midLeft
            below.highRight = midRight
            above.lowLeft = midLeft
            above.lowRight = midRight
        }
        var next = ordered
        next[index] = above
        next.insert(below, at: index)
        return (next, below.id)
    }

    static func transition(of bands: [MenuBarTintBand]) -> TintTransition? {
        if bands.allSatisfy({ !$0.blend.slides }) { return .stepped }
        if bands.allSatisfy({ $0.blend.slides }) { return .smooth }
        return nil
    }

    /// Stepped drops the slide from every segment. Smooth makes each segment
    /// start from where the one below it ends, so the colors run on without jumps.
    static func applying(_ transition: TintTransition, to bands: [MenuBarTintBand]) -> [MenuBarTintBand] {
        let ordered = sorted(bands)
        return ordered.enumerated().map { index, band in
            var next = band
            switch transition {
            case .stepped:
                switch band.blend {
                case .slide: next.blend = .constant
                case .slideGradient: next.blend = .gradient
                case .constant, .gradient: break
                }
                if next.blend == .constant {
                    next = filled(next, with: next.highRight)
                }
            case .smooth:
                guard !band.blend.slides else { break }
                let previous = index > 0 ? ordered[index - 1] : nil
                if band.blend == .gradient {
                    next.blend = .slideGradient
                    next.lowLeft = previous?.highLeft ?? band.highLeft
                    next.lowRight = previous?.highRight ?? band.highRight
                } else {
                    next.blend = .slide
                    next.lowRight = previous?.highRight ?? band.highRight
                    next.lowLeft = next.lowRight
                    next.highLeft = next.highRight
                }
            }
            return next
        }
    }

    /// Switches one band's effect, carrying its colors over so the change is gentle.
    static func settingBlend(_ blend: MenuBarTintBlend, of band: MenuBarTintBand, previous: MenuBarTintBand?) -> MenuBarTintBand {
        var next = band
        let wasBlend = band.blend
        next.blend = blend
        switch blend {
        case .constant:
            next = filled(next, with: band.highRight)
        case .slide:
            if !wasBlend.slides {
                next.lowRight = previous?.highRight ?? band.highRight
            }
            next.lowLeft = next.lowRight
            next.highLeft = next.highRight
        case .gradient:
            if wasBlend == .slide {
                next.highLeft = band.lowRight
            } else if wasBlend != .slideGradient && wasBlend != .gradient {
                next.highLeft = band.highRight
            }
            next.lowLeft = next.highLeft
            next.lowRight = next.highRight
        case .slideGradient:
            switch wasBlend {
            case .slide:
                next.lowLeft = band.lowRight
                next.highLeft = band.highRight
            case .gradient:
                next.lowLeft = previous?.highLeft ?? band.highLeft
                next.lowRight = previous?.highRight ?? band.highRight
            case .constant:
                next.lowLeft = previous?.highRight ?? band.highRight
                next.lowRight = next.lowLeft
            case .slideGradient:
                break
            }
        }
        return next
    }

    static func filled(_ band: MenuBarTintBand, with swatch: MenuBarTintSwatch) -> MenuBarTintBand {
        var next = band
        next.highRight = swatch
        next.highLeft = swatch
        next.lowRight = swatch
        next.lowLeft = swatch
        return next
    }

    /// Sets one of a band's colors, keeping the colors its effect does not show in step.
    static func setting(
        _ keyPath: WritableKeyPath<MenuBarTintBand, MenuBarTintSwatch>,
        to swatch: MenuBarTintSwatch,
        in band: MenuBarTintBand
    ) -> MenuBarTintBand {
        var next = band
        next[keyPath: keyPath] = swatch
        switch next.blend {
        case .constant:
            next = filled(next, with: swatch)
        case .slide:
            next.lowLeft = next.lowRight
            next.highLeft = next.highRight
        case .gradient:
            next.lowLeft = next.highLeft
            next.lowRight = next.highRight
        case .slideGradient:
            break
        }
        return next
    }
}

/// One band drawn across its own width: low end on the left, high end on the right.
struct TintBandFill: View {
    var band: MenuBarTintBand

    var body: some View {
        let s = band.rampSwatches
        if band.rampIsSplit {
            VStack(spacing: 0) {
                strip(s.leftLow, s.leftHigh)
                strip(s.rightLow, s.rightHigh)
            }
        } else {
            strip(s.rightLow, s.rightHigh)
        }
    }

    private func strip(_ low: MenuBarTintSwatch, _ high: MenuBarTintSwatch) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [low.color, high.color], startPoint: .leading, endPoint: .trailing))
    }
}

/// A whole scheme as a thin bar, for preset thumbnails.
struct TintRampBar: View {
    var bands: [MenuBarTintBand]
    var cornerRadius: CGFloat = 3

    var body: some View {
        let ordered = TintRamp.sorted(bands)
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, band in
                    let span = Double(band.throughPercent - TintRamp.lower(at: index, in: ordered))
                    TintBandFill(band: band)
                        .frame(width: max(0, geo.size.width * span / 100))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// The draggable ramp. Handles move split points; clicking a segment opens its editor.
struct TintRampEditor<SegmentEditor: View>: View {
    var bands: [MenuBarTintBand]
    var followLabel: LocalizedStringKey
    var language: AppLanguage
    @Binding var editingID: UUID?
    var onChange: ([MenuBarTintBand]) -> Void
    @ViewBuilder var segmentEditor: (_ band: MenuBarTintBand, _ lower: Int) -> SegmentEditor

    @State private var drag: Drag?

    private struct Drag: Equatable {
        var id: UUID
        var percent: Int
    }

    private let barHeight: CGFloat = 26
    private let handleHeight: CGFloat = 34

    private var committed: [MenuBarTintBand] { TintRamp.sorted(bands) }

    private var displayed: [MenuBarTintBand] {
        guard let drag else { return committed }
        return TintRamp.sorted(TintRamp.moving(drag.id, to: drag.percent, in: committed))
    }

    var body: some View {
        let ordered = displayed
        VStack(spacing: 3) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { index, band in
                            let lower = TintRamp.lower(at: index, in: ordered)
                            segment(band, lower: lower, width: width * Double(band.throughPercent - lower) / 100)
                        }
                    }
                    .frame(width: width, height: barHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                    }
                    .offset(y: (handleHeight - barHeight) / 2)

                    ForEach(Array(ordered.dropLast().enumerated()), id: \.element.id) { _, band in
                        handle(band, width: width)
                    }
                }
                .overlay {
                    RampMouseSurface(
                        handles: ordered.dropLast().map { width * Double($0.throughPercent) / 100 },
                        onDrag: { index, x in
                            if let target = boundaryTarget(index, x: x, width: width) {
                                drag = Drag(id: target.id, percent: target.percent)
                            }
                        },
                        onEnd: { index, x in
                            if let target = boundaryTarget(index, x: x, width: width),
                               let band = committed.first(where: { $0.id == target.id }),
                               band.throughPercent != target.percent {
                                onChange(TintRamp.moving(target.id, to: target.percent, in: committed))
                            }
                            drag = nil
                        },
                        onClick: { x in
                            guard width > 0 else { return }
                            let percent = x / width * 100
                            editingID = committed.first { Double($0.throughPercent) >= percent }?.id ?? committed.last?.id
                        }
                    )
                }
            }
            .frame(height: handleHeight)

            labels(ordered)
                .frame(height: 14)
        }
    }

    private func segment(_ band: MenuBarTintBand, lower: Int, width: CGFloat) -> some View {
        let selected = editingID == band.id
        let title = Localization.string("settings.tint.segment.range %lld %lld", language: language, lower, band.throughPercent)
        return TintBandFill(band: band)
            .frame(width: max(0, width))
            .overlay {
                if band.rampFollowsMenuBar, width > 96 {
                    Text(followLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
            }
            .overlay {
                if selected {
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .popover(
                isPresented: Binding(
                    get: { editingID == band.id },
                    set: { shown in
                        if !shown, editingID == band.id { editingID = nil }
                    }
                ),
                arrowEdge: .bottom
            ) {
                segmentEditor(band, lower)
            }
            .help(title)
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { editingID = band.id }
    }

    /// Where the split point at `index` lands for a pointer at `x`, kept between its neighbors.
    private func boundaryTarget(_ index: Int, x: CGFloat, width: CGFloat) -> (id: UUID, percent: Int)? {
        let ordered = committed
        guard width > 0, ordered.indices.contains(index), index < ordered.count - 1 else { return nil }
        let range = TintRamp.boundaryRange(at: index, in: ordered)
        let raw = Int((x / width * 100).rounded())
        return (ordered[index].id, min(range.upperBound, max(range.lowerBound, raw)))
    }

    private func handle(_ band: MenuBarTintBand, width: CGFloat) -> some View {
        let index = committed.firstIndex { $0.id == band.id } ?? 0
        let range = TintRamp.boundaryRange(at: index, in: committed)
        let percent = drag?.id == band.id ? drag?.percent ?? band.throughPercent : band.throughPercent
        return ZStack {
            Capsule()
                .fill(Color.white)
                .frame(width: 9, height: handleHeight - 2)
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                .overlay {
                    Capsule().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
                }
        }
        .frame(width: 22, height: handleHeight)
        .position(x: width * Double(percent) / 100, y: handleHeight / 2)
        .accessibilityRepresentation {
            // To VoiceOver each split point is an ordinary slider over the range it can move in.
            Slider(
                value: Binding(
                    get: { Double(band.throughPercent) },
                    set: { value in
                        let next = min(range.upperBound, max(range.lowerBound, Int(value.rounded())))
                        if next != band.throughPercent {
                            onChange(TintRamp.moving(band.id, to: next, in: committed))
                        }
                    }
                ),
                in: Double(range.lowerBound)...Double(max(range.lowerBound, range.upperBound)),
                step: 1
            ) {
                Text(verbatim: Localization.string("settings.tint.boundary", language: language))
            }
            .accessibilityValue(Text(verbatim: "\(percent)%"))
        }
    }

    private func labels(_ ordered: [MenuBarTintBand]) -> some View {
        let stops = ordered.dropLast().map(\.throughPercent)
        let showsZero = (stops.first ?? 100) >= 9
        let showsHundred = (stops.last ?? 0) <= 91
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if showsZero {
                    label(0, active: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if showsHundred {
                    label(100, active: false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                ForEach(Array(ordered.dropLast()), id: \.id) { band in
                    label(band.throughPercent, active: drag?.id == band.id)
                        .fixedSize()
                        .position(x: geo.size.width * Double(band.throughPercent) / 100, y: 7)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func label(_ percent: Int, active: Bool) -> some View {
        Text("\(percent)%")
            .font(.system(size: 10, weight: active ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(active ? Color.primary : Color.secondary)
    }
}

/// The popover for one segment: its range, which effect it uses, and its colors.
struct TintSegmentEditor<Preview: View>: View {
    var band: MenuBarTintBand
    var lower: Int
    var previous: MenuBarTintBand?
    var language: AppLanguage
    /// "settings.tint.segment.range %lld %lld" for battery charge, or the value variant.
    var rangeKey: String
    var captionKey: LocalizedStringKey
    /// "settings.tint.color.at %lld" for battery charge, or the value variant.
    var atKey: String
    var followName: LocalizedStringKey
    var followNote: LocalizedStringKey?
    var canDelete: Bool
    /// Where this segment's top may move, or nil for the top segment, which always ends at 100%.
    var upperRange: ClosedRange<Int>?
    var onSetUpper: (Int) -> Void
    var onChange: (MenuBarTintBand) -> Void
    var onDelete: () -> Void
    @ViewBuilder var preview: Preview

    private static var palette: [MenuBarTintSwatch] {
        [.menuBar, .systemRed, .systemOrange, .systemYellow, .systemGreen]
    }

    private struct ColorRow: Identifiable {
        var id: String { title }
        var title: String
        var keyPath: WritableKeyPath<MenuBarTintBand, MenuBarTintSwatch>
    }

    private var colorRows: [ColorRow] {
        let single = Localization.string("settings.tint.color.single", language: language)
        let left = Localization.string("settings.tint.color.left", language: language)
        let right = Localization.string("settings.tint.color.right", language: language)
        let atLow = Localization.string(atKey, language: language, lower)
        let atHigh = Localization.string(atKey, language: language, band.throughPercent)
        switch band.blend {
        case .constant:
            return [ColorRow(title: single, keyPath: \.highRight)]
        case .slide:
            return [
                ColorRow(title: atLow, keyPath: \.lowRight),
                ColorRow(title: atHigh, keyPath: \.highRight),
            ]
        case .gradient:
            return [
                ColorRow(title: left, keyPath: \.highLeft),
                ColorRow(title: right, keyPath: \.highRight),
            ]
        case .slideGradient:
            return [
                ColorRow(title: "\(atLow) · \(left)", keyPath: \.lowLeft),
                ColorRow(title: "\(atLow) · \(right)", keyPath: \.lowRight),
                ColorRow(title: "\(atHigh) · \(left)", keyPath: \.highLeft),
                ColorRow(title: "\(atHigh) · \(right)", keyPath: \.highRight),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                preview
                VStack(alignment: .leading, spacing: 2) {
                    Text(Localization.string(rangeKey, language: language, lower, band.throughPercent))
                        .font(.system(size: 13, weight: .semibold))
                    Text(captionKey)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Text("settings.tint.segment.delete")
                    }
                    .controlSize(.small)
                }
            }

            if let upperRange, upperRange.lowerBound < upperRange.upperBound {
                HStack(spacing: 8) {
                    Text("settings.tint.segment.endsAt")
                        .font(.system(size: 12))
                    Spacer(minLength: 8)
                    Text(verbatim: "\(band.throughPercent)%")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Stepper(
                        Localization.string("settings.tint.segment.endsAt", language: language),
                        value: Binding(get: { band.throughPercent }, set: onSetUpper),
                        in: upperRange
                    )
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("settings.tint.effect")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(MenuBarTintBlend.allCases) { blend in
                        effectCard(blend)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("settings.color.header")
                VStack(spacing: 0) {
                    ForEach(Array(colorRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().padding(.leading, 10)
                        }
                        colorRow(row)
                    }
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                if let followNote {
                    Text(followNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(width: 400)
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func effectCard(_ blend: MenuBarTintBlend) -> some View {
        let selected = band.blend == blend
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button {
            guard !selected else { return }
            onChange(TintRamp.settingBlend(blend, of: band, previous: previous))
        } label: {
            HStack(spacing: 8) {
                TintEffectThumbnail(blend: blend)
                    .frame(width: 60, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(LocalizedStringKey(Self.effectTitleKey(blend)))
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    Text(LocalizedStringKey(Self.effectCaptionKey(blend)))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(shape.fill(Color.primary.opacity(0.04)))
            .overlay {
                shape.strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 0.5)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func effectTitleKey(_ blend: MenuBarTintBlend) -> String {
        switch blend {
        case .constant: "settings.tint.effect.constant"
        case .slide: "settings.tint.effect.slide"
        case .gradient: "settings.tint.effect.gradient"
        case .slideGradient: "settings.tint.effect.both"
        }
    }

    static func effectCaptionKey(_ blend: MenuBarTintBlend) -> String {
        Self.effectTitleKey(blend) + ".caption"
    }

    private func colorRow(_ row: ColorRow) -> some View {
        let current = band[keyPath: row.keyPath]
        let isCustom: Bool = {
            if case .custom = current { return true }
            return false
        }()
        return HStack(spacing: 6) {
            Text(row.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            ForEach(Self.palette, id: \.self) { swatch in
                swatchButton(swatch, selected: current == swatch) {
                    onChange(TintRamp.setting(row.keyPath, to: swatch, in: band))
                }
            }
            ColorPicker(
                Localization.string("settings.tint.otherColor", language: language),
                selection: Binding(
                    get: { current.color },
                    set: { onChange(TintRamp.setting(row.keyPath, to: .from(color: $0), in: band)) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .fixedSize()
            .overlay {
                if isCustom {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(-2)
                        .allowsHitTesting(false)
                }
            }
            .help(Localization.string("settings.tint.otherColor", language: language))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func swatchButton(_ swatch: MenuBarTintSwatch, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if swatch.followsMenuBar {
                    Circle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0.5),
                                    .init(color: .white, location: 0.5),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    Circle().fill(swatch.color)
                }
                Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
            }
            .frame(width: 16, height: 16)
            .padding(2)
            .overlay {
                if selected {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(swatch.followsMenuBar ? Text(followName) : Text(LocalizedStringKey(Self.swatchNameKey(swatch))))
        .accessibilityLabel(swatch.followsMenuBar ? Text(followName) : Text(LocalizedStringKey(Self.swatchNameKey(swatch))))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func swatchNameKey(_ swatch: MenuBarTintSwatch) -> String {
        switch swatch {
        case .menuBar: "settings.tint.menuBarDefault"
        case .systemRed: "settings.tint.swatch.red"
        case .systemOrange: "settings.tint.swatch.orange"
        case .systemYellow: "settings.tint.swatch.yellow"
        case .systemGreen: "settings.tint.swatch.green"
        case .custom: "settings.tint.otherColor"
        }
    }
}

/// A small picture of each effect: one battery for a fixed look, three for a
/// look that changes as the charge goes up.
struct TintEffectThumbnail: View {
    var blend: MenuBarTintBlend

    var body: some View {
        switch blend {
        case .constant:
            MiniBattery(level: 0.7, left: .green, right: .green)
                .frame(width: 30, height: 14)
        case .slide:
            HStack(spacing: 3) {
                MiniBattery(level: 0.3, left: .red, right: .red)
                MiniBattery(level: 0.6, left: .orange, right: .orange)
                MiniBattery(level: 0.9, left: .yellow, right: .yellow)
            }
        case .gradient:
            MiniBattery(level: 0.85, left: .red, right: .yellow)
                .frame(width: 30, height: 14)
        case .slideGradient:
            HStack(spacing: 3) {
                MiniBattery(level: 0.3, left: .red, right: .orange)
                MiniBattery(level: 0.6, left: .orange, right: .yellow)
                MiniBattery(level: 0.9, left: .yellow, right: .green)
            }
        }
    }

    private struct MiniBattery: View {
        var level: Double
        var left: Color
        var right: Color

        var body: some View {
            GeometryReader { geo in
                let nub = max(1.5, geo.size.width * 0.08)
                let bodyWidth = geo.size.width - nub - 0.5
                let radius = geo.size.height * 0.3
                HStack(spacing: 0.5) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)
                        RoundedRectangle(cornerRadius: max(0.5, radius - 1.5), style: .continuous)
                            .fill(LinearGradient(colors: [left, right], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(1, (bodyWidth - 4) * level))
                            .padding(2)
                    }
                    .frame(width: bodyWidth)
                    RoundedRectangle(cornerRadius: nub / 2, style: .continuous)
                        .fill(Color.primary.opacity(0.45))
                        .frame(width: nub, height: geo.size.height * 0.4)
                }
            }
            .aspectRatio(2.1, contentMode: .fit)
        }
    }
}

/// A preset in a gallery: a picture of its colors over its name.
struct TintPresetChip<Thumbnail: View>: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    @ViewBuilder var thumbnail: Thumbnail

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            VStack(spacing: 6) {
                thumbnail
                    .frame(height: 10)
                Text(title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 7)
            .padding(.top, 9)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .background(shape.fill(Color.primary.opacity(0.04)))
            .overlay {
                shape.strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 0.5)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Takes the mouse over the ramp in AppKit. Inside a grouped Form the list under
/// the row claimed drags before a SwiftUI drag gesture could start, so the
/// handles never moved. A click away from a handle selects the segment under it.
private struct RampMouseSurface: NSViewRepresentable {
    var handles: [CGFloat]
    var onDrag: (Int, CGFloat) -> Void
    var onEnd: (Int, CGFloat) -> Void
    var onClick: (CGFloat) -> Void

    func makeNSView(context: Context) -> RampMouseView {
        RampMouseView()
    }

    func updateNSView(_ view: RampMouseView, context: Context) {
        view.handles = handles
        view.onDrag = onDrag
        view.onEnd = onEnd
        view.onClick = onClick
        view.window?.invalidateCursorRects(for: view)
    }
}

private final class RampMouseView: NSView {
    var handles: [CGFloat] = []
    var onDrag: ((Int, CGFloat) -> Void)?
    var onEnd: ((Int, CGFloat) -> Void)?
    var onClick: ((CGFloat) -> Void)?
    private var active: Int?
    private var moved = false

    /// How far from a handle's center a press still grabs it.
    private static let grabDistance: CGFloat = 9

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { false }

    private func pointerX(_ event: NSEvent) -> CGFloat {
        convert(event.locationInWindow, from: nil).x
    }

    private func handle(near x: CGFloat) -> Int? {
        guard let nearest = handles.enumerated().min(by: { abs($0.element - x) < abs($1.element - x) }),
              abs(nearest.element - x) <= Self.grabDistance else { return nil }
        return nearest.offset
    }

    override func mouseDown(with event: NSEvent) {
        active = handle(near: pointerX(event))
        moved = false
        if active != nil { NSCursor.closedHand.set() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let active else { return }
        moved = true
        onDrag?(active, pointerX(event))
    }

    override func mouseUp(with event: NSEvent) {
        let x = pointerX(event)
        if let active {
            if moved { onEnd?(active, x) }
        } else {
            onClick?(x)
        }
        active = nil
        moved = false
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        for x in handles {
            addCursorRect(
                NSRect(x: x - Self.grabDistance, y: 0, width: Self.grabDistance * 2, height: bounds.height),
                cursor: .resizeLeftRight
            )
        }
    }
}
