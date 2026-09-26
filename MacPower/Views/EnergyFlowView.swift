import SwiftUI

struct EnergyFlowView<Trailing: View>: View {
    var snapshot: PowerSnapshot
    var theme: AppTheme
    var flowTint: FlowTintSettings
    var flowIcons: FlowIconSettings = .classic
    var isAnimating: Bool
    var motion: EnergyMotionStyle
    var motionFrameRate: EnergyMotionFrameRate = .hz60
    var pulseFlowIcons: Bool
    var flowIconScale: Double = 1
    var language: AppLanguage
    var showsFooter: Bool = true
    @ViewBuilder var trailingAccessory: () -> Trailing

    @State private var outgoingSnapshot: PowerSnapshot?
    @State private var transitionStartedAt: Date?
    @State private var cleanupTask: Task<Void, Never>?

    /// This is deliberately long enough for the fork to read as a physical
    /// split/merge, rather than a replacement of one static diagram by another.
    private let transitionDuration: TimeInterval = RibbonMorph.duration

    init(
        snapshot: PowerSnapshot,
        theme: AppTheme,
        flowTint: FlowTintSettings,
        flowIcons: FlowIconSettings = .classic,
        isAnimating: Bool,
        motion: EnergyMotionStyle,
        motionFrameRate: EnergyMotionFrameRate = .hz60,
        pulseFlowIcons: Bool,
        flowIconScale: Double = 1,
        language: AppLanguage,
        showsFooter: Bool = true,
        @ViewBuilder trailingAccessory: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.snapshot = snapshot
        self.theme = theme
        self.flowTint = flowTint
        self.flowIcons = flowIcons
        self.isAnimating = isAnimating
        self.motion = motion
        self.motionFrameRate = motionFrameRate
        self.pulseFlowIcons = pulseFlowIcons
        self.flowIconScale = flowIconScale
        self.language = language
        self.showsFooter = showsFooter
        self.trailingAccessory = trailingAccessory
    }

    var body: some View {
        // Keep one TimelineView mounted for the whole popover lifetime of a
        // transition. Swapping it in and out reset the inner motion clock, which
        // made particles and filaments jump at the first and last frame.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: outgoingSnapshot == nil)) { timeline in
            diagram(for: snapshot, morph: currentMorph(tick: timeline.date))
        }
        .onChange(of: snapshot) { previous, current in
            guard previous.flowMode != current.flowMode else { return }
            applyFlowModeChange(previous: previous, next: current)
        }
        .onDisappear {
            cleanupTask?.cancel()
        }
    }

    private func diagram(for snapshot: PowerSnapshot, morph: FlowMorph? = nil) -> some View {
        EnergyFlowDiagram(
            snapshot: snapshot,
            theme: theme,
            flowTint: flowTint,
            flowIcons: flowIcons,
            isAnimating: isAnimating,
            motion: motion,
            motionFrameRate: motionFrameRate,
            pulseFlowIcons: pulseFlowIcons,
            flowIconScale: flowIconScale,
            language: language,
            showsFooter: showsFooter,
            morph: morph,
            trailingAccessory: trailingAccessory
        )
    }

    private func currentMorph(tick: Date) -> FlowMorph? {
        guard let outgoingSnapshot, let transitionStartedAt else { return nil }
        // Wall clock owns the morph. TimelineView.date can jump when the
        // animation schedule unpauses, which skipped the Y merge.
        let elapsed = Date().timeIntervalSince(transitionStartedAt)
        _ = tick
        return FlowMorph(
            from: outgoingSnapshot,
            progress: RibbonMorph.easedProgress(elapsed: elapsed, duration: transitionDuration)
        )
    }

    private func applyFlowModeChange(previous: PowerSnapshot, next: PowerSnapshot) {
        let now = Date()
        switch RibbonMorph.decide(
            from: outgoingSnapshot,
            startedAt: transitionStartedAt,
            duration: transitionDuration,
            previous: previous,
            nextMode: next.flowMode,
            now: now
        ) {
        case .keepGoing:
            return
        case .start(let from):
            beginTransition(from: from, at: now)
        case .reverse(let from, let elapsed):
            beginTransition(from: from, at: now.addingTimeInterval(-(transitionDuration - elapsed)))
        }
    }

    private func beginTransition(from previous: PowerSnapshot, at startedAt: Date) {
        cleanupTask?.cancel()
        outgoingSnapshot = previous
        transitionStartedAt = startedAt
        let remaining = max(transitionDuration - nowElapsed(since: startedAt), 0)
        cleanupTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int((remaining + 0.08) * 1_000)))
            guard !Task.isCancelled, transitionStartedAt == startedAt else { return }
            outgoingSnapshot = nil
            transitionStartedAt = nil
        }
    }

    private func nowElapsed(since startedAt: Date) -> TimeInterval {
        Date().timeIntervalSince(startedAt)
    }
}

private struct FlowMorph {
    var from: PowerSnapshot
    var progress: Double
}

private struct EnergyFlowDiagram<Trailing: View>: View {
    var snapshot: PowerSnapshot
    var theme: AppTheme
    var flowTint: FlowTintSettings
    var flowIcons: FlowIconSettings
    var isAnimating: Bool
    var motion: EnergyMotionStyle
    var motionFrameRate: EnergyMotionFrameRate = .hz60
    var pulseFlowIcons: Bool
    var flowIconScale: Double = 1
    var language: AppLanguage
    var showsFooter: Bool = true
    /// During a mode change, the ribbon geometry and pigment interpolate from
    /// the old telemetry reading to the new one.
    var morph: FlowMorph?
    @ViewBuilder var trailingAccessory: () -> Trailing
    @Environment(\.colorScheme) private var colorScheme

    /// Non-vibrant ink so SF Symbols match Canvas watt labels on Liquid Glass.
    private var ribbonInk: Color {
        colorScheme == .dark ? Color(white: 0.92) : Color(white: 0.14)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                diagram
                    .frame(maxWidth: .infinity)
                trailingAccessory()
            }
            if showsFooter {
                footer
            }
        }
    }

    private var diagram: some View {
        GeometryReader { geo in
            let layout = layout(in: geo.size, morph: morph)
            // Glass is Equatable and only depends on shape/tint. Motion lives in an
            // overlay rasterized with drawingGroup so 60 fps Canvas ticks do not
            // resample glassEffect.
            RibbonGlassSlot(
                size: geo.size,
                fillLeft: layout.fillLeft,
                fillRight: layout.fillRight,
                bodyPath: layout.body,
                maskSignature: maskSignature(layout.body)
            )
            .equatable()
            .overlay {
                ZStack {
                    motionOverlay(layout: layout)
                    wattLabels(layout: layout)
                    iconLayer(layout: layout, size: geo.size)
                }
            }
        }
        .frame(height: diagramHeight)
    }

    @ViewBuilder
    private func motionOverlay(layout: Layout) -> some View {
        if isAnimating, motion.usesCanvasTimeline {
            TimelineView(.periodic(from: .now, by: 1.0 / motionFrameRate.framesPerSecond)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate / 4.6
                Canvas { context, _ in
                    context.clip(to: layout.body, style: FillStyle(eoFill: false, antialiased: true))
                    drawMotion(
                        context: &context,
                        body: layout.body,
                        lanes: layout.outgoingLanes,
                        fill: layout.fillLeft,
                        opacity: layout.outgoingOverlayOpacity,
                        phase: phase
                    )
                    drawMotion(
                        context: &context,
                        body: layout.body,
                        lanes: layout.incomingLanes,
                        fill: layout.fillLeft,
                        opacity: layout.incomingOverlayOpacity,
                        phase: phase
                    )
                }
                .drawingGroup(opaque: false)
            }
            .allowsHitTesting(false)
        }
    }

    private func drawMotion(
        context: inout GraphicsContext,
        body: Path,
        lanes: [Lane],
        fill: Color,
        opacity: Double,
        phase: Double
    ) {
        guard opacity > 0.01, !lanes.isEmpty else { return }
        let previous = context.opacity
        context.opacity *= opacity
        let motionBase = flowTint.motionColor?.color ?? fill
        let pigment: FlowMotionPigment = {
            if flowTint.motionColor != nil {
                // Custom motion color overrides gradient/solid/white pigment path.
                return motion.pigment == .white ? .white : .solid
            }
            return motion.pigment ?? .gradient
        }()
        switch motion {
        case .sheen:
            drawSheen(context: &context, body: body, lanes: lanes, fill: fill, phase: phase)
        case .filaments, .filamentsSolid, .filamentsWhite:
            for lane in lanes {
                drawFilaments(
                    context: &context,
                    lane: lane,
                    phase: phase,
                    pigment: pigment,
                    baseColor: motionBase
                )
            }
        case .particles, .particlesSolid, .particlesWhite:
            for lane in lanes {
                drawPowder(
                    context: &context,
                    lane: lane,
                    phase: phase,
                    pigment: pigment,
                    baseColor: motionBase
                )
            }
        case .off:
            break
        }
        context.opacity = previous
    }

    private func wattLabels(layout: Layout) -> some View {
        Canvas { context, _ in
            drawWattLabels(
                context: &context,
                body: layout.body,
                lanes: layout.outgoingLanes,
                opacity: layout.outgoingOverlayOpacity
            )
            drawWattLabels(
                context: &context,
                body: layout.body,
                lanes: layout.incomingLanes,
                opacity: layout.incomingOverlayOpacity
            )
        }
        .allowsHitTesting(false)
    }

    private func drawWattLabels(
        context: inout GraphicsContext,
        body: Path,
        lanes: [Lane],
        opacity: Double
    ) {
        guard opacity > 0.01 else { return }
        let previous = context.opacity
        context.opacity *= opacity
        for lane in lanes {
            drawWattLabel(context: &context, body: body, lane: lane)
        }
        context.opacity = previous
    }

    @ViewBuilder
    private func iconLayer(layout: Layout, size: CGSize) -> some View {
        if isAnimating, pulseFlowIcons {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                let breath = iconBreath(at: timeline.date)
                ZStack {
                    bubbleStack(layout.bubbles, breath: breath)
                }
                .opacity(layout.bubbleOpacity)
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        } else {
            ZStack {
                bubbleStack(layout.bubbles, breath: 0)
            }
            .opacity(layout.bubbleOpacity)
            .allowsHitTesting(false)
        }
    }

    private func bubbleStack(_ bubbles: [Bubble], breath: CGFloat) -> some View {
        ForEach(bubbles) { bubble in
            flowNode(bubble, breath: breath)
                .position(bubble.point)
        }
    }

    /// Occupancy of the glass mask, so a Y-notch filling in is visible while a
    /// last-frame swap from a union-capsule to a stadium-capsule is not.
    private func maskSignature(_ path: Path) -> Int {
        var hasher = Hasher()
        let bounds = path.boundingRect
        hasher.combine(Int((bounds.minX * 4).rounded()))
        hasher.combine(Int((bounds.maxX * 4).rounded()))
        hasher.combine(Int((bounds.minY * 4).rounded()))
        hasher.combine(Int((bounds.maxY * 4).rounded()))
        let xs: [CGFloat] = [0.22, 0.4, 0.55, 0.7, 0.82, 0.9, 0.96]
        let ys: [CGFloat] = [0.18, 0.38, 0.5, 0.62, 0.82]
        for x in xs {
            for y in ys {
                hasher.combine(
                    path.contains(
                        CGPoint(
                            x: bounds.minX + bounds.width * x,
                            y: bounds.minY + bounds.height * y
                        )
                    )
                )
            }
        }
        return hasher.finalize()
    }

    /// Liquid Glass for the ribbon. Equality ignores animation phase so SwiftUI
    /// can skip resampling when only the particle overlay ticks.
    private struct RibbonGlassSlot: View, @MainActor Equatable {
        var size: CGSize
        var fillLeft: Color
        var fillRight: Color
        var bodyPath: Path
        var maskSignature: Int
        @Environment(\.readmeGalleryCapture) private var readmeGalleryCapture

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.size == rhs.size
                && lhs.fillLeft == rhs.fillLeft
                && lhs.fillRight == rhs.fillRight
                && lhs.maskSignature == rhs.maskSignature
        }

        var body: some View {
            let stadium = RoundedRectangle(
                cornerRadius: FlowRibbon.capRadius(for: FlowRibbon.trunkWidth(totalWatts: 1)),
                style: .continuous
            )
            // Tint glass with a mid mix so neither end of a gradient disappears.
            let glassTint = fillLeft.mixed(with: fillRight, by: 0.5).opacity(FlowRibbon.glassTintOpacity)
            ZStack {
                FlowRibbonShape(path: bodyPath)
                    .fill(ribbonFill)
                if readmeGalleryCapture {
                    // Offscreen bitmaps do not sample Liquid Glass; keep the
                    // opaque pigment so gradient / smooth presets stay visible.
                    EmptyView()
                } else if #available(macOS 26.0, *) {
                    let sampled = Color.clear
                        .frame(width: size.width, height: size.height)
                        .macPowerGlassEffect(.regularTint(glassTint), in: stadium)
                    sampled.mask { FlowRibbonShape(path: bodyPath) }
                } else {
                    // Avoid clear + material-background + path mask (often invisible
                    // on 14/15). Fill the ribbon silhouette directly.
                    FlowRibbonShape(path: bodyPath)
                        .fill(.ultraThinMaterial)
                    FlowRibbonShape(path: bodyPath)
                        .fill(glassTint)
                }
            }
        }

        private var ribbonFill: AnyShapeStyle {
            if fillLeft == fillRight {
                return AnyShapeStyle(fillLeft.opacity(0.78))
            }
            // Bias the right stop later and stronger so charging forks keep a
            // readable tip color under Liquid Glass.
            return AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: fillLeft.opacity(0.82), location: 0),
                        .init(color: fillLeft.opacity(0.70), location: 0.38),
                        .init(color: fillRight.opacity(0.72), location: 0.62),
                        .init(color: fillRight.opacity(0.92), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }

    private var diagramHeight: CGFloat {
        let trunk = FlowRibbon.trunkWidth(totalWatts: 1)
        // Reserve fork headroom in every power state so connecting, charging,
        // and unplugging never resize the surrounding popover. A typed icon
        // size above the ribbon can still grow the row so the glyph is not clipped.
        let glyph = max(
            flowIcons.supply.renderScale,
            flowIcons.battery.renderScale,
            flowIcons.batteryCharging.renderScale,
            flowIcons.mac.renderScale
        )
        let iconSide = 16 * glyph * flowIconScale * 1.16
        return max(trunk + 24, iconSide + 8)
    }

    @ViewBuilder
    private func flowNode(_ bubble: Bubble, breath: CGFloat) -> some View {
        let scale = CGFloat(bubble.glyph.renderScale) * CGFloat(flowIconScale)
        let side = 16 * scale
        GlyphSlotView(
            slot: bubble.glyph,
            systemPointSize: side,
            assetSide: side,
            prefersMonochrome: true,
            ink: ribbonInk
        )
            .frame(width: side, height: side)
            .scaleEffect(1 + 0.16 * breath)
            .opacity(1 - 0.32 * breath)
    }

    private func iconBreath(at date: Date) -> CGFloat {
        let period = 2.1
        let turns = date.timeIntervalSinceReferenceDate / period
        return CGFloat(0.5 - 0.5 * cos(turns * 2 * .pi))
    }

    private struct Bubble: Identifiable {
        var id: String
        var glyph: GlyphSlot
        var point: CGPoint
    }

    private func bubble(_ id: String, at point: CGPoint, charging: Bool = false) -> Bubble {
        Bubble(id: id, glyph: flowIcons.slot(forBubbleID: id, charging: charging), point: point)
    }

    private struct Lane {
        var id: String
        var cubic: FlowCubic
        var width: CGFloat
        var watts: Double
        var color: Color
    }

    private struct Layout {
        var body: Path
        var fillLeft: Color
        var fillRight: Color
        var lanes: [Lane]
        var bubbles: [Bubble]
        var isMorphing = false
        var outgoingLanes: [Lane] = []
        var incomingLanes: [Lane] = []
        var outgoingOverlayOpacity = 1.0
        var incomingOverlayOpacity = 0.0
        var bubbleOpacity = 1.0
    }

    private func tintColors(for mode: EnergyFlowMode, percent: Double) -> (left: Color, right: Color) {
        flowTint.scheme(for: mode).colors(percent: percent)
    }

    private func layout(in size: CGSize, morph: FlowMorph?) -> Layout {
        guard let morph else {
            return layout(in: size, snapshot: snapshot)
        }

        let progress = min(max(morph.progress, 0), 1)
        let from = layout(in: size, snapshot: morph.from)
        let to = layout(in: size, snapshot: snapshot)
        guard progress > 0.001, progress < 1 else {
            return progress <= 0.001 ? from : to
        }

        let lanes: [Lane]
        if from.lanes.count == 2, to.lanes.count == 2 {
            let bridge = bridgeLanes(from: from.lanes, to: to.lanes, in: size)
            if progress < 0.5 {
                lanes = interpolateLanes(from.lanes, bridge, progress: progress * 2)
            } else {
                lanes = interpolateLanes(bridge, to.lanes, progress: (progress - 0.5) * 2)
            }
        } else {
            lanes = interpolateLanes(from.lanes, to.lanes, progress: progress)
        }
        // Labels are information attached to finished branches, not decorations
        // for the temporary trunk. Fading them away before the channels meet
        // prevents the two watt values from colliding in the middle.
        let overlay = FlowRibbonOverlay.opacities(progress: progress)
        let bubblePresentation = bubbles(for: progress, from: from.bubbles, to: to.bubbles)
        return Layout(
            body: movingTopologyBody(in: size, from: morph.from, to: snapshot, progress: progress)
                ?? bodyPath(for: lanes),
            fillLeft: from.fillLeft.mixed(with: to.fillLeft, by: progress),
            fillRight: from.fillRight.mixed(with: to.fillRight, by: progress),
            lanes: lanes,
            bubbles: bubblePresentation.bubbles,
            isMorphing: true,
            outgoingLanes: from.lanes,
            incomingLanes: to.lanes,
            outgoingOverlayOpacity: overlay.outgoing,
            incomingOverlayOpacity: overlay.incoming,
            bubbleOpacity: bubblePresentation.opacity
        )
    }

    /// Node positions never interpolate. The outgoing set dissolves before the
    /// topology changes; the incoming set appears only after its new branch has
    /// gained enough body to hold it. This avoids icons stranded half in glass
    /// and half in empty popover space.
    private func bubbles(for progress: Double, from: [Bubble], to: [Bubble]) -> (bubbles: [Bubble], opacity: Double) {
        if progress < 0.26 {
            return (from, 1 - smoothstep(progress / 0.26))
        }
        if progress > 0.62 {
            return (to, smoothstep((progress - 0.62) / 0.38))
        }
        return ([], 0)
    }

    private func layout(in size: CGSize, snapshot: PowerSnapshot) -> Layout {
        let trunk = FlowRibbon.trunkWidth(totalWatts: 1)
        let midY = size.height / 2
        // Keep rounded end caps clear of the GeometryReader clip edge.
        let inset = FlowRibbon.capRadius(for: trunk) + FlowRibbon.edgePadding
        let logo = max(FlowRibbon.logoInset, inset + 10)
        let left = CGPoint(x: inset, y: midY)
        let right = CGPoint(x: size.width - inset, y: midY)
        let leftLogo = CGPoint(x: logo, y: midY)
        let rightLogo = CGPoint(x: size.width - logo, y: midY)

        switch snapshot.flowMode {
        case .charging:
            let charge = max(snapshot.chargeWatts, 0.01)
            let load = max(snapshot.systemLoadWatts, 0.01)
            let widths = FlowRibbon.splitWidths(first: charge, second: load, trunk: trunk)
            let top = CGPoint(x: size.width - inset, y: widths.0 / 2)
            let bot = CGPoint(x: size.width - inset, y: size.height - widths.1 / 2)
            let topLane = ForkOutline.stackedLane(
                from: left,
                to: top,
                startY: left.y - trunk / 2 + widths.0 / 2,
                endY: top.y,
                holdT: FlowRibbon.forkT
            )
            let botLane = ForkOutline.stackedLane(
                from: left,
                to: bot,
                startY: left.y + trunk / 2 - widths.1 / 2,
                endY: bot.y,
                holdT: FlowRibbon.forkT
            )
            let colors = tintColors(for: .charging, percent: snapshot.percent)
            return settle(
                Layout(
                body: ForkOutline.splitPath(left: left, top: top, bot: bot, topW: widths.0, botW: widths.1),
                fillLeft: colors.left,
                fillRight: colors.right,
                lanes: [
                    Lane(id: "to-battery", cubic: topLane, width: widths.0, watts: snapshot.chargeWatts, color: colors.left),
                    Lane(id: "to-system", cubic: botLane, width: widths.1, watts: snapshot.systemLoadWatts, color: colors.right)
                ],
                bubbles: [
                    bubble("supply", at: leftLogo),
                    bubble("battery", at: CGPoint(x: size.width - logo, y: top.y), charging: true),
                    bubble("mac", at: CGPoint(x: size.width - logo, y: bot.y))
                ]
                )
            )
        case .adapterHold:
            let watts = max(snapshot.systemLoadWatts, snapshot.adapterInWatts)
            let colors = tintColors(for: .adapterHold, percent: snapshot.percent)
            return settle(
                Layout(
                body: ForkOutline.capsule(from: left, to: right, width: trunk),
                fillLeft: colors.left,
                fillRight: colors.right,
                lanes: [
                    Lane(
                        id: "adapter-system",
                        cubic: straightCubic(from: left, to: right),
                        width: trunk,
                        watts: watts,
                        color: colors.left
                    )
                ],
                bubbles: [
                    bubble("supply", at: leftLogo),
                    bubble("mac", at: rightLogo)
                ]
                )
            )
        case .discharging:
            let watts = max(snapshot.dischargeWatts, snapshot.systemLoadWatts)
            let colors = tintColors(for: .discharging, percent: snapshot.percent)
            return settle(
                Layout(
                body: ForkOutline.capsule(from: left, to: right, width: trunk),
                fillLeft: colors.left,
                fillRight: colors.right,
                lanes: [
                    Lane(
                        id: "battery-system",
                        cubic: straightCubic(from: left, to: right),
                        width: trunk,
                        watts: watts,
                        color: colors.left
                    )
                ],
                bubbles: [
                    bubble("battery", at: leftLogo),
                    bubble("mac", at: rightLogo)
                ]
                )
            )
        case .underpowered:
            let adapter = max(snapshot.adapterInWatts, 0.01)
            let battery = max(snapshot.dischargeWatts, 0.01)
            let widths = FlowRibbon.splitWidths(first: adapter, second: battery, trunk: trunk)
            let leftTop = CGPoint(x: inset, y: widths.0 / 2)
            let leftBot = CGPoint(x: inset, y: size.height - widths.1 / 2)
            let topLane = ForkOutline.stackedLane(
                from: leftTop,
                to: right,
                startY: leftTop.y,
                endY: right.y - trunk / 2 + widths.0 / 2,
                holdT: 1 - FlowRibbon.forkT
            )
            let botLane = ForkOutline.stackedLane(
                from: leftBot,
                to: right,
                startY: leftBot.y,
                endY: right.y + trunk / 2 - widths.1 / 2,
                holdT: 1 - FlowRibbon.forkT
            )
            let colors = tintColors(for: .underpowered, percent: snapshot.percent)
            let discharge = tintColors(for: .discharging, percent: snapshot.percent)
            return settle(
                Layout(
                body: ForkOutline.mergePath(top: leftTop, bot: leftBot, right: right, topW: widths.0, botW: widths.1),
                fillLeft: colors.left,
                fillRight: colors.right,
                lanes: [
                    Lane(id: "adapter-system", cubic: topLane, width: widths.0, watts: snapshot.adapterInWatts, color: colors.left),
                    Lane(id: "battery-system", cubic: botLane, width: widths.1, watts: snapshot.dischargeWatts, color: discharge.left)
                ],
                bubbles: [
                    bubble("supply", at: CGPoint(x: logo, y: leftTop.y)),
                    bubble("battery", at: CGPoint(x: logo, y: leftBot.y)),
                    bubble("mac", at: rightLogo)
                ]
                )
            )
        }
    }

    private func settle(_ layout: Layout) -> Layout {
        var layout = layout
        layout.outgoingLanes = layout.lanes
        layout.outgoingOverlayOpacity = 1
        layout.incomingLanes = []
        layout.incomingOverlayOpacity = 0
        return layout
    }

    private func interpolateLanes(_ from: [Lane], _ to: [Lane], progress: Double) -> [Lane] {
        let start = expandedLanes(from, pairedWith: to)
        let end = expandedLanes(to, pairedWith: from)
        return zip(start, end).enumerated().map { index, pair in
            let (a, b) = pair
            return Lane(
                id: "morph-\(index)",
                cubic: interpolate(a.cubic, b.cubic, progress: progress),
                width: interpolate(a.width, b.width, progress: progress),
                watts: interpolate(a.watts, b.watts, progress: progress),
                color: a.color.mixed(with: b.color, by: progress)
            )
        }
    }

    /// The neutral trunk is the real midpoint when a right-hand fork needs to
    /// become a left-hand fork (or vice versa). Both channels coincide here,
    /// then peel apart from the opposite end.
    private func bridgeLanes(from: [Lane], to: [Lane], in size: CGSize) -> [Lane] {
        let trunk = FlowRibbon.trunkWidth(totalWatts: 1)
        let endInset = FlowRibbon.capRadius(for: trunk) + FlowRibbon.edgePadding
        let left = CGPoint(x: endInset, y: size.height / 2)
        let right = CGPoint(x: size.width - endInset, y: size.height / 2)
        let watts = max(
            max(from.reduce(0) { $0 + $1.watts }, to.reduce(0) { $0 + $1.watts }),
            0.01
        )
        let lane = Lane(
            id: "morph-trunk",
            cubic: straightCubic(from: left, to: right),
            width: trunk,
            watts: watts,
            color: tintColors(for: snapshot.flowMode, percent: snapshot.percent).left
        )
        return [lane, lane]
    }

    /// Every state is expressed as two channels while morphing. A single path
    /// becomes two stacked sublanes whose combined thickness remains equal to
    /// the trunk, so a merge cannot swell before its final frame.
    private func expandedLanes(_ lanes: [Lane], pairedWith other: [Lane]) -> [Lane] {
        guard let first = lanes.first else { return [] }
        guard lanes.count == 1, other.count >= 2 else {
            return Array(lanes.prefix(2))
        }
        let pair = Array(other.prefix(2))
        let total = max(pair.reduce(0) { $0 + $1.width }, 0.01)
        var offset = -first.width / 2
        return pair.enumerated().map { index, lane in
            let width = first.width * lane.width / total
            let centerOffset = offset + width / 2
            offset += width
            return Lane(
                id: "trunk-sublane-\(index)",
                cubic: verticallyOffset(first.cubic, by: centerOffset),
                width: width,
                watts: first.watts * Double(width / first.width),
                color: first.color
            )
        }
    }

    private func verticallyOffset(_ cubic: FlowCubic, by offset: CGFloat) -> FlowCubic {
        FlowCubic(
            p0: CGPoint(x: cubic.p0.x, y: cubic.p0.y + offset),
            c1: CGPoint(x: cubic.c1.x, y: cubic.c1.y + offset),
            c2: CGPoint(x: cubic.c2.x, y: cubic.c2.y + offset),
            p1: CGPoint(x: cubic.p1.x, y: cubic.p1.y + offset)
        )
    }

    private func interpolate(_ from: FlowCubic, _ to: FlowCubic, progress: Double) -> FlowCubic {
        FlowCubic(
            p0: interpolate(from.p0, to.p0, progress: progress),
            c1: interpolate(from.c1, to.c1, progress: progress),
            c2: interpolate(from.c2, to.c2, progress: progress),
            p1: interpolate(from.p1, to.p1, progress: progress)
        )
    }

    private func interpolate(_ from: CGPoint, _ to: CGPoint, progress: Double) -> CGPoint {
        CGPoint(
            x: interpolate(from.x, to.x, progress: progress),
            y: interpolate(from.y, to.y, progress: progress)
        )
    }

    private func interpolate(_ from: CGFloat, _ to: CGFloat, progress: Double) -> CGFloat {
        from + (to - from) * CGFloat(progress)
    }

    private func interpolate(_ from: Double, _ to: Double, progress: Double) -> Double {
        from + (to - from) * progress
    }

    private func smoothstep(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Capsule ↔ Y share one opening parameter. Closing is opening played
    /// backwards, so the late Y→capsule swap is the same silhouette as the
    /// early capsule→Y hold, not a different construction.
    private func movingTopologyBody(
        in size: CGSize,
        from source: PowerSnapshot,
        to destination: PowerSnapshot,
        progress: Double
    ) -> Path? {
        let open = CGFloat(min(max(progress, 0), 1))

        switch (source.flowMode, destination.flowMode) {
        case (.underpowered, .charging):
            if open < 0.5 {
                return underpoweredBody(in: size, snapshot: source, mergeT: FlowRibbon.mergeT(open: 1 - open * 2))
            }
            return chargingBody(in: size, snapshot: destination, splitT: FlowRibbon.splitT(open: (open - 0.5) * 2))

        case (.charging, .underpowered):
            if open < 0.5 {
                return chargingBody(in: size, snapshot: source, splitT: FlowRibbon.splitT(open: 1 - open * 2))
            }
            return underpoweredBody(in: size, snapshot: destination, mergeT: FlowRibbon.mergeT(open: (open - 0.5) * 2))

        case (.charging, .adapterHold), (.charging, .discharging):
            return chargingBody(in: size, snapshot: source, splitT: FlowRibbon.splitT(open: 1 - open))

        case (.adapterHold, .charging), (.discharging, .charging):
            return chargingBody(in: size, snapshot: destination, splitT: FlowRibbon.splitT(open: open))

        case (.underpowered, .adapterHold), (.underpowered, .discharging):
            return underpoweredBody(in: size, snapshot: source, mergeT: FlowRibbon.mergeT(open: 1 - open))

        case (.adapterHold, .underpowered), (.discharging, .underpowered):
            return underpoweredBody(in: size, snapshot: destination, mergeT: FlowRibbon.mergeT(open: open))

        case (.adapterHold, .discharging), (.discharging, .adapterHold):
            return singleBody(in: size)

        default:
            return nil
        }
    }

    private func chargingBody(in size: CGSize, snapshot: PowerSnapshot, splitT: CGFloat) -> Path {
        let trunk = FlowRibbon.trunkWidth(totalWatts: 1)
        let inset = FlowRibbon.capRadius(for: trunk) + FlowRibbon.edgePadding
        let remaining = (size.width - inset * 2) * (1 - min(max(splitT, 0), 1))
        let collapse = FlowRibbon.forkCollapse(
            remainingLength: remaining,
            minimum: minimumForkLength(trunk: trunk)
        )
        let charge = max(snapshot.chargeWatts, 0.01)
        let load = max(snapshot.systemLoadWatts, 0.01)
        let widths = FlowRibbon.splitWidths(first: charge, second: load, trunk: trunk)
        let left = CGPoint(x: inset, y: size.height / 2)
        let top = CGPoint(x: size.width - inset, y: widths.0 / 2)
        let bottom = CGPoint(x: size.width - inset, y: size.height - widths.1 / 2)
        return ForkOutline.splitPath(
            left: left,
            top: top,
            bot: bottom,
            topW: widths.0,
            botW: widths.1,
            splitT: splitT,
            collapse: collapse
        )
    }

    private func underpoweredBody(in size: CGSize, snapshot: PowerSnapshot, mergeT: CGFloat) -> Path {
        let trunk = FlowRibbon.trunkWidth(totalWatts: 1)
        let inset = FlowRibbon.capRadius(for: trunk) + FlowRibbon.edgePadding
        let remaining = (size.width - inset * 2) * min(max(mergeT, 0), 1)
        let collapse = FlowRibbon.forkCollapse(
            remainingLength: remaining,
            minimum: minimumForkLength(trunk: trunk)
        )
        let adapter = max(snapshot.adapterInWatts, 0.01)
        let battery = max(snapshot.dischargeWatts, 0.01)
        let widths = FlowRibbon.splitWidths(first: adapter, second: battery, trunk: trunk)
        let top = CGPoint(x: inset, y: widths.0 / 2)
        let bottom = CGPoint(x: inset, y: size.height - widths.1 / 2)
        let right = CGPoint(x: size.width - inset, y: size.height / 2)
        return ForkOutline.mergePath(
            top: top,
            bot: bottom,
            right: right,
            topW: widths.0,
            botW: widths.1,
            mergeT: mergeT,
            collapse: collapse
        )
    }

    private func singleBody(in size: CGSize) -> Path {
        let trunk = FlowRibbon.trunkWidth(totalWatts: 1)
        let inset = FlowRibbon.capRadius(for: trunk) + FlowRibbon.edgePadding
        return ForkOutline.capsule(
            from: CGPoint(x: inset, y: size.height / 2),
            to: CGPoint(x: size.width - inset, y: size.height / 2),
            width: trunk
        )
    }

    /// Below this remaining branch length, pinch the two fork ports together
    /// instead of swapping to a capsule in one frame.
    private func minimumForkLength(trunk: CGFloat) -> CGFloat {
        max(trunk, FlowRibbon.nodeDiameter * 2)
    }

    private func bodyPath(for lanes: [Lane]) -> Path {
        ForkOutline.combinedSilhouette(
            lanes.map { ForkOutline.cubicCapsule($0.cubic, width: $0.width) }
        )
    }

    private func straightCubic(from start: CGPoint, to end: CGPoint) -> FlowCubic {
        let dx = end.x - start.x
        return FlowCubic(
            p0: start,
            c1: CGPoint(x: start.x + dx * 0.45, y: start.y),
            c2: CGPoint(x: start.x + dx * 0.55, y: end.y),
            p1: end
        )
    }

    /// Full-height wash across the capsule; a soft peak travels left → right.
    private func drawSheen(
        context: inout GraphicsContext,
        body: Path,
        lanes: [Lane],
        fill: Color,
        phase: Double
    ) {
        let watts = lanes.map(\.watts).max() ?? 1
        let speed = FlowRibbon.sheenSpeed(watts: watts)
        var t = (phase * speed).truncatingRemainder(dividingBy: 1)
        if t < 0 { t += 1 }

        let bounds = body.boundingRect
        guard bounds.width > 1, bounds.height > 1 else { return }

        let color = fill
        let halo = Color.white.mixed(with: color, by: 0.42)
        let core = Color.white.mixed(with: color, by: 0.08)
        // Peak covers about a third of the capsule so it reads as a band, not a speck.
        let stops = sheenStops(peak: t, half: 0.18, halo: halo, core: core)

        context.fill(
            Path(bounds),
            with: .linearGradient(
                Gradient(stops: stops),
                startPoint: CGPoint(x: bounds.minX, y: bounds.midY),
                endPoint: CGPoint(x: bounds.maxX, y: bounds.midY)
            )
        )
    }

    private func sheenStops(peak: Double, half: Double, halo: Color, core: Color) -> [Gradient.Stop] {
        var raw: [(CGFloat, Color)] = [(0, .clear), (1, .clear)]
        func add(_ location: Double, _ color: Color) {
            raw.append((CGFloat(min(1, max(0, location))), color))
        }
        add(peak - half, .clear)
        add(peak - half * 0.55, halo.opacity(0.28))
        add(peak - half * 0.18, core.opacity(0.52))
        add(peak, core.opacity(0.70))
        add(peak + half * 0.18, core.opacity(0.52))
        add(peak + half * 0.55, halo.opacity(0.28))
        add(peak + half, .clear)

        let merged = Dictionary(raw, uniquingKeysWith: { _, last in last })
            .sorted { $0.key < $1.key }
        var stops: [Gradient.Stop] = []
        for (location, color) in merged {
            if let last = stops.last, last.location == location { continue }
            stops.append(.init(color: color, location: location))
        }
        return stops
    }

    private func drawFilaments(
        context: inout GraphicsContext,
        lane: Lane,
        phase: Double,
        pigment: FlowMotionPigment,
        baseColor: Color
    ) {
        let seed = fnv(lane.id)
        let count = FlowRibbon.filamentCount(laneWidth: lane.width)
        for index in 0..<count {
            var rng = SplitMix64(seed: seed &+ UInt64(index) &* 0x9E3779B97F4A7C15)
            let offset = rng.unit()
            let speed = FlowRibbon.filamentSpeed(watts: lane.watts) * (0.72 + rng.unit() * 0.40)
            let length = 0.18 + rng.unit() * 0.22
            let thickness = rng.cg(0.8, 1.4)
            let maxOff = max(0.6, lane.width * 0.42)
            let lateral = rng.cg(-maxOff, maxOff)
            var t = (phase * speed + offset).truncatingRemainder(dividingBy: 1)
            if t < 0 { t += 1 }
            for (from, to) in wrappedRanges(center: t + length / 2, span: length) where to - from > 0.02 {
                fillFilament(
                    context: &context,
                    lane: lane,
                    from: from,
                    to: to,
                    lateral: lateral,
                    thickness: thickness,
                    pigment: pigment,
                    baseColor: baseColor
                )
            }
        }
    }

    /// Spindle fill, not a constant-width stroke: sides converge to a needle at both tips
    /// so the bright mid-span cannot read as two parallel edges.
    private func fillFilament(
        context: inout GraphicsContext,
        lane: Lane,
        from: Double,
        to: Double,
        lateral: CGFloat,
        thickness: CGFloat,
        pigment: FlowMotionPigment,
        baseColor: Color
    ) {
        let start = lane.cubic.offsetPoint(CGFloat(from), distance: lateral)
        let end = lane.cubic.offsetPoint(CGFloat(to), distance: lateral)
        let body = filamentSpindle(lane: lane, from: from, to: to, lateral: lateral, thickness: thickness)
        switch pigment {
        case .gradient:
            let head = travelingColor(base: baseColor, t: from)
            let mid = travelingColor(base: baseColor, t: (from + to) / 2)
            let tail = travelingColor(base: baseColor, t: to)
            context.fill(
                body,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: head.opacity(0), location: 0),
                        .init(color: head.opacity(0.88), location: 0.16),
                        .init(color: mid.opacity(0.96), location: 0.5),
                        .init(color: tail.opacity(0.88), location: 0.84),
                        .init(color: tail.opacity(0), location: 1)
                    ]),
                    startPoint: start,
                    endPoint: end
                )
            )
            context.fill(
                filamentSpindle(lane: lane, from: from, to: to, lateral: lateral, thickness: thickness * 0.36),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.white.opacity(0.55), location: 0.28),
                        .init(color: Color.white.opacity(0.88), location: 0.5),
                        .init(color: Color.white.opacity(0.55), location: 0.72),
                        .init(color: .clear, location: 1)
                    ]),
                    startPoint: start,
                    endPoint: end
                )
            )
        case .solid, .white:
            let color: Color = pigment == .white ? .white : baseColor.mixed(with: .black, by: 0.42)
            context.fill(
                body,
                with: .linearGradient(tipFade(color), startPoint: start, endPoint: end)
            )
        }
    }

    private func tipFade(_ color: Color) -> Gradient {
        Gradient(stops: [
            .init(color: color.opacity(0), location: 0),
            .init(color: color.opacity(0.82), location: 0.16),
            .init(color: color.opacity(0.96), location: 0.5),
            .init(color: color.opacity(0.82), location: 0.84),
            .init(color: color.opacity(0), location: 1)
        ])
    }

    private func filamentSpindle(
        lane: Lane,
        from: Double,
        to: Double,
        lateral: CGFloat,
        thickness: CGFloat
    ) -> Path {
        let steps = max(8, Int(((to - from) * 36).rounded(.up)))
        var upper: [CGPoint] = []
        var lower: [CGPoint] = []
        upper.reserveCapacity(steps + 1)
        lower.reserveCapacity(steps + 1)
        for index in 0...steps {
            let frac = Double(index) / Double(steps)
            let u = from + (to - from) * frac
            let half = thickness * 0.5 * filamentEnvelope(frac)
            let point = lane.cubic.offsetPoint(CGFloat(u), distance: lateral)
            let normal = lane.cubic.normal(CGFloat(u))
            upper.append(CGPoint(x: point.x + normal.x * half, y: point.y + normal.y * half))
            lower.append(CGPoint(x: point.x - normal.x * half, y: point.y - normal.y * half))
        }
        var path = Path()
        path.move(to: upper[0])
        for point in upper.dropFirst() { path.addLine(to: point) }
        for point in lower.reversed() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    /// 0 at both tips, 1 at mid-span. No plateau, so sides never run parallel.
    private func filamentEnvelope(_ fraction: Double) -> CGFloat {
        let tip = min(max(min(fraction, 1 - fraction) * 2, 0), 1)
        return CGFloat(pow(tip, 1.35))
    }

    private func wrappedRanges(center: Double, span: Double) -> [(Double, Double)] {
        var start = center - span / 2
        start = start.truncatingRemainder(dividingBy: 1)
        if start < 0 { start += 1 }
        let end = start + span
        if end <= 1 {
            return [(start, end)]
        }
        return [(start, 1), (0, end - 1)]
    }

    private func drawPowder(
        context: inout GraphicsContext,
        lane: Lane,
        phase: Double,
        pigment: FlowMotionPigment,
        baseColor: Color
    ) {
        let seed = fnv(lane.id)
        let count = FlowRibbon.particleCount(laneWidth: lane.width)
        for index in 0..<count {
            drawGrain(
                context: &context,
                index: index,
                seed: seed,
                lane: lane,
                phase: phase,
                pigment: pigment,
                baseColor: baseColor
            )
        }
    }

    private func drawGrain(
        context: inout GraphicsContext,
        index: Int,
        seed: UInt64,
        lane: Lane,
        phase: Double,
        pigment: FlowMotionPigment,
        baseColor: Color
    ) {
        var rng = SplitMix64(seed: seed &+ UInt64(index) &* 0xD1B54A32D192ED03)
        let offset = rng.unit()
        let speed = FlowRibbon.filamentSpeed(watts: lane.watts) * 0.42 * (0.82 + rng.unit() * 0.36)
        let radius = rng.cg(0.7, 1.55)
        let maxOff = max(0.4, lane.width * 0.5 - radius - 0.6)
        let lateral = min(max(CGFloat(gaussian(rng.unit(), rng.unit())) * (maxOff * 0.82), -maxOff), maxOff)
        let brightness = 0.62 + rng.unit() * 0.38

        var t = (phase * speed + offset).truncatingRemainder(dividingBy: 1)
        if t < 0 { t += 1 }
        let fade = pow(sin(t * .pi), 0.65)
        guard fade > 0.04 else { return }

        let pointOnCurve = lane.cubic.point(CGFloat(t))
        let normal = lane.cubic.normal(CGFloat(t))
        let x = pointOnCurve.x + normal.x * lateral
        let y = pointOnCurve.y + normal.y * lateral
        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
        let alpha = fade * brightness
        switch pigment {
        case .gradient:
            let traveling = travelingColor(base: baseColor, t: t)
            context.fill(Path(ellipseIn: rect), with: .color(traveling.opacity(alpha)))
            let spark = t < 0.28 ? 0.92 : 0.55
            context.fill(
                Path(ellipseIn: rect.insetBy(dx: radius * 0.32, dy: radius * 0.32)),
                with: .color(Color.white.opacity(alpha * spark))
            )
        case .solid:
            let color = baseColor.mixed(with: .black, by: 0.42)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
        case .white:
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)))
        }
    }

    private func travelingColor(base: Color, t: Double) -> Color {
        let head = Color.white.mixed(with: base, by: 0.06)
        let tail = base.mixed(with: .black, by: 0.18)
        if t < 0.22 {
            return Color.white.mixed(with: head, by: t / 0.22)
        }
        if t < 0.48 {
            return head.mixed(with: base, by: (t - 0.22) / 0.26)
        }
        return base.mixed(with: tail, by: (t - 0.48) / 0.52)
    }

    private func drawWattLabel(context: inout GraphicsContext, body: Path, lane: Lane) {
        let x = FlowRibbon.wattLabelX(on: lane.cubic)
        let hintY = FlowRibbon.spineY(on: lane.cubic, atX: x)
        let point = CGPoint(
            x: x,
            y: FlowRibbon.centerY(
                of: body,
                atX: x,
                hintY: hintY,
                searchRadius: lane.width * 0.5 + 8
            )
        )
        let text = Text(String(format: "%.1f W", lane.watts))
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(ribbonInk)
        context.draw(text, at: point, anchor: .center)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            labeled(Localization.string("energy.supplyPower", language: language), value: supplyText)
            // Always reserve this row: plugging in a charger should reveal its
            // rating, not make the whole popover grow by one text line.
            labeled(
                Localization.string("energy.chargerRating", language: language),
                value: String(format: "%.0f W", snapshot.adapterCeilingWatts)
            )
            .opacity(showsChargerRating ? 1 : 0)
            .accessibilityHidden(!showsChargerRating)
            .animation(.easeInOut(duration: 0.24), value: showsChargerRating)
        }
        .font(.caption)
    }

    private var showsChargerRating: Bool {
        snapshot.adapterCeilingWatts > 0 && snapshot.externalConnected
    }

    private var supplyText: String {
        switch snapshot.flowMode {
        case .charging, .adapterHold:
            return String(format: "%.1f W", snapshot.adapterInWatts)
        case .discharging:
            return String(format: "%.1f W", max(snapshot.dischargeWatts, snapshot.systemLoadWatts))
        case .underpowered:
            return String(format: "%.1f W", snapshot.adapterInWatts + snapshot.dischargeWatts)
        }
    }

    private func labeled(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
                .autoFittingCaption(minimumScale: 0.7)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .autoFittingCaption(minimumScale: 0.7)
                .layoutPriority(1)
        }
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func cg(_ min: CGFloat, _ max: CGFloat) -> CGFloat {
        min + CGFloat(unit()) * (max - min)
    }
}

private func gaussian(_ u1: Double, _ u2: Double) -> Double {
    let a = max(u1, 1e-9)
    return sqrt(-2 * log(a)) * cos(2 * .pi * u2)
}

private func fnv(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return hash
}
