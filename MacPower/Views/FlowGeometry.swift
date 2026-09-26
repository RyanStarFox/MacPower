import SwiftUI

private enum ReadmeGalleryCaptureKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// When true, Liquid Glass is replaced with opaque fills so README bitmaps
    /// keep a readable ribbon (cacheDisplay often samples glass as empty black).
    var readmeGalleryCapture: Bool {
        get { self[ReadmeGalleryCaptureKey.self] }
        set { self[ReadmeGalleryCaptureKey.self] = newValue }
    }
}

enum FlowRibbon {
    /// Diameter of the settings button, and the horizontal slot reserved for end logos.
    static let nodeDiameter: CGFloat = 32

    /// Corner radius of a ribbon end. Thick ribbons stay rounded-rect;
    /// once thickness drops to the node size they degenerate to a semicircle.
    static func capRadius(for width: CGFloat) -> CGFloat {
        min(width / 2, nodeDiameter / 2)
    }

    /// Distance from the visual outer edge to the spine.
    static func endInset(for width: CGFloat) -> CGFloat {
        capRadius(for: width)
    }

    /// Icons sit a bit inward of the rounded end, toward the ribbon middle.
    static let logoInset: CGFloat = 42

    /// Keep rounded caps clear of the diagram’s clip edge.
    static let edgePadding: CGFloat = 16

    /// Shared Liquid Glass tint so the battery bar and energy ribbon match.
    static let glassTintOpacity: Double = 0.42

    /// Split/merge along the spine: keep a short trunk, then long fingers.
    static let forkT: CGFloat = 0.22

    /// 0 = capsule, 1 = static charging Y. Closing is `splitT(open: 1 - open)`.
    static func splitT(open: CGFloat) -> CGFloat {
        let t = min(max(open, 0), 1)
        return 1 - (1 - forkT) * t
    }

    /// 0 = capsule, 1 = static underpowered Y. Closing is `mergeT(open: 1 - open)`.
    static func mergeT(open: CGFloat) -> CGFloat {
        let t = min(max(open, 0), 1)
        return (1 - forkT) * t
    }

    /// Remaining fork length at which the silhouette is already a capsule.
    static func forkSwapLength(trunk: CGFloat) -> CGFloat {
        capRadius(for: trunk) * 2
    }

    /// 0 = full fork opening, 1 = visually a capsule. Reaches 1 at `forkSwapLength`
    /// so swapping to a stadium is the reverse of opening, not a late pop.
    static func forkCollapse(remainingLength: CGFloat, minimum: CGFloat) -> CGFloat {
        let floor = min(minimum, nodeDiameter)
        if remainingLength >= minimum { return 0 }
        if remainingLength <= floor { return 1 }
        return 1 - (remainingLength - floor) / (minimum - floor)
    }

    /// Horizontal centre of the lane. Each branch spans the whole ribbon
    /// (the shared trunk is part of the bar), so the label sits on the mid-span,
    /// not halfway along the separated finger.
    static func wattLabelX(on cubic: FlowCubic) -> CGFloat {
        (cubic.p0.x + cubic.p1.x) / 2
    }

    /// Spine Y at a horizontal position. Cubic parameter `t` is not the same x.
    static func spineY(on cubic: FlowCubic, atX x: CGFloat) -> CGFloat {
        var lo: CGFloat = 0
        var hi: CGFloat = 1
        for _ in 0..<18 {
            let mid = (lo + hi) / 2
            if cubic.point(mid).x < x {
                lo = mid
            } else {
                hi = mid
            }
        }
        return cubic.point((lo + hi) / 2).y
    }

    /// Vertical centre of `path` at `x` near `hintY`. Restricting the scan
    /// keeps forked ribbons from averaging both fingers into one mid-line.
    static func centerY(
        of path: Path,
        atX x: CGFloat,
        hintY: CGFloat,
        searchRadius: CGFloat
    ) -> CGFloat {
        let bounds = path.boundingRect
        guard bounds.width > 0, bounds.height > 0 else { return hintY }
        let clampedX = min(max(x, bounds.minX), bounds.maxX)
        let yMin = max(bounds.minY, hintY - searchRadius)
        let yMax = min(bounds.maxY, hintY + searchRadius)
        guard yMax > yMin else { return hintY }
        var runs: [(CGFloat, CGFloat)] = []
        var runStart: CGFloat?
        var runEnd: CGFloat?
        var y = yMin
        let step = max(0.35, (yMax - yMin) / 80)
        while y <= yMax {
            if path.contains(CGPoint(x: clampedX, y: y), eoFill: false) {
                if runStart == nil { runStart = y }
                runEnd = y
            } else if let start = runStart, let end = runEnd {
                runs.append((start, end))
                runStart = nil
                runEnd = nil
            }
            y += step
        }
        if let start = runStart, let end = runEnd {
            runs.append((start, end))
        }
        guard let run = runs.min(by: { distance($0, hintY) < distance($1, hintY) }) else {
            return hintY
        }
        return (run.0 + run.1) / 2
    }

    private static func distance(_ run: (CGFloat, CGFloat), _ y: CGFloat) -> CGFloat {
        if y < run.0 { return run.0 - y }
        if y > run.1 { return y - run.1 }
        return 0
    }

    /// Full-capsule sheen. Linear in watts, independent of filament speed.
    /// Floor is high enough that ~10 W still crosses in a few seconds.
    static func sheenSpeed(watts: Double) -> Double {
        let w = max(watts, 1)
        return 0.48 + min(w / 80.0, 0.36)
    }

    /// Horizontal filaments. Faster than the old shared sqrt curve.
    static func filamentSpeed(watts: Double) -> Double {
        let w = max(watts, 1)
        return 0.55 + min(pow(w / 10.0, 0.5), 3.1)
    }

    /// Grains per lane. Capped so the 15 fps canvas stays cheap.
    static func particleCount(laneWidth: CGFloat) -> Int {
        min(72, max(28, Int(laneWidth * 0.7)))
    }

    /// Horizontal filaments per lane. Kept small so the canvas stays cheap.
    static func filamentCount(laneWidth: CGFloat) -> Int {
        min(14, max(6, Int(laneWidth / 10)))
    }

    /// Visual thickness of the energy-flow trunk/capsule.
    /// Triple the node diameter so logos sit inside the ribbon.
    static func trunkWidth(totalWatts _: Double) -> CGFloat {
        nodeDiameter * 3
    }

    static func splitWidths(first: Double, second: Double, trunk: CGFloat) -> (CGFloat, CGFloat) {
        let a = max(first, 0.01)
        let b = max(second, 0.01)
        let sum = a + b
        var firstW = trunk * CGFloat(a / sum)
        var secondW = trunk * CGFloat(b / sum)
        let minW = min(FlowRibbon.nodeDiameter, trunk * 0.33)
        if firstW < minW {
            firstW = minW
            secondW = trunk - minW
        } else if secondW < minW {
            secondW = minW
            firstW = trunk - minW
        }
        return (firstW, secondW)
    }
}

/// Watt labels and particle/filament fields stay on a finished topology.
/// Interpolating them across a Y↔capsule morph makes values and seeds jump
/// when the construction lanes collapse into one capsule lane.
enum FlowRibbonOverlay {
    static let outgoingEnd = 0.26
    static let incomingStart = 0.62

    static func opacities(progress: Double) -> (outgoing: Double, incoming: Double) {
        let p = min(max(progress, 0), 1)
        if p <= 0 { return (1, 0) }
        if p >= 1 { return (0, 1) }
        if p < outgoingEnd {
            return (1 - smoothstep(p / outgoingEnd), 0)
        }
        if p > incomingStart {
            return (0, smoothstep((p - incomingStart) / (1 - incomingStart)))
        }
        return (0, 0)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

struct FlowRibbonShape: Shape {
    var path: Path

    func path(in rect: CGRect) -> Path {
        path
    }
}

struct FlowCubic {
    var p0: CGPoint
    var c1: CGPoint
    var c2: CGPoint
    var p1: CGPoint

    func point(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let x = u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p1.x
        let y = u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p1.y
        return CGPoint(x: x, y: y)
    }

    func derivative(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let x = 3 * u * u * (c1.x - p0.x) + 6 * u * t * (c2.x - c1.x) + 3 * t * t * (p1.x - c2.x)
        let y = 3 * u * u * (c1.y - p0.y) + 6 * u * t * (c2.y - c1.y) + 3 * t * t * (p1.y - c2.y)
        return CGPoint(x: x, y: y)
    }

    func normal(_ t: CGFloat) -> CGPoint {
        let d = derivative(t)
        let len = max(0.001, hypot(d.x, d.y))
        return CGPoint(x: -d.y / len, y: d.x / len)
    }

    func offsetPoint(_ t: CGFloat, distance: CGFloat) -> CGPoint {
        let p = point(t)
        let n = normal(t)
        return CGPoint(x: p.x + n.x * distance, y: p.y + n.y * distance)
    }
}

enum ForkOutline {
    enum Cap {
        case round
        case butt
    }

    /// Hairline overlap at a butt join so antialiasing does not leave a seam.
    /// Kept far smaller than a round cap so it cannot refill the crotch.
    private static let seam: CGFloat = 0.8

    static func stackedLane(
        from start: CGPoint,
        to end: CGPoint,
        startY: CGFloat,
        endY: CGFloat,
        holdT: CGFloat
    ) -> FlowCubic {
        let dx = end.x - start.x
        let hold = min(max(holdT, 0.05), 0.95)
        let turn = min(hold + 0.16, 0.95)
        return FlowCubic(
            p0: CGPoint(x: start.x, y: startY),
            c1: CGPoint(x: start.x + dx * hold, y: startY),
            c2: CGPoint(x: start.x + dx * turn, y: endY),
            p1: CGPoint(x: end.x, y: endY)
        )
    }

    static func splitPath(
        left: CGPoint,
        top: CGPoint,
        bot: CGPoint,
        topW: CGFloat,
        botW: CGFloat,
        splitT: CGFloat = FlowRibbon.forkT,
        collapse: CGFloat = 0
    ) -> Path {
        let trunk = topW + botW
        let t = min(max(collapse, 0), 1)
        let splitX = left.x + (top.x - left.x) * min(max(splitT, 0), 1)
        let remaining = top.x - splitX
        if t >= 1 || remaining <= FlowRibbon.forkSwapLength(trunk: trunk) {
            return capsule(from: left, to: CGPoint(x: top.x, y: left.y), width: trunk)
        }

        let topY = left.y - trunk / 2 + topW / 2
        let botY = left.y + trunk / 2 - botW / 2
        let endTop = top.y + (topY - top.y) * t
        let endBot = bot.y + (botY - bot.y) * t
        var path = Path()
        path.addPath(capsule(
            from: left,
            to: CGPoint(x: splitX + seam, y: left.y),
            width: trunk,
            startCap: .round,
            endCap: .butt
        ))
        path.addPath(cubicCapsule(
            stackedLane(
                from: CGPoint(x: splitX - seam, y: topY),
                to: CGPoint(x: top.x, y: endTop),
                startY: topY,
                endY: endTop,
                holdT: 0.5
            ),
            width: topW,
            startCap: .butt,
            endCap: .round
        ))
        path.addPath(cubicCapsule(
            stackedLane(
                from: CGPoint(x: splitX - seam, y: botY),
                to: CGPoint(x: top.x, y: endBot),
                startY: botY,
                endY: endBot,
                holdT: 0.5
            ),
            width: botW,
            startCap: .butt,
            endCap: .round
        ))
        return path.normalizedSilhouette()
    }

    static func mergePath(
        top: CGPoint,
        bot: CGPoint,
        right: CGPoint,
        topW: CGFloat,
        botW: CGFloat,
        mergeT: CGFloat = 1 - FlowRibbon.forkT,
        collapse: CGFloat = 0
    ) -> Path {
        let trunk = topW + botW
        let t = min(max(collapse, 0), 1)
        let mergeX = top.x + (right.x - top.x) * min(max(mergeT, 0), 1)
        let remaining = mergeX - top.x
        if t >= 1 || remaining <= FlowRibbon.forkSwapLength(trunk: trunk) {
            return capsule(from: CGPoint(x: top.x, y: right.y), to: right, width: trunk)
        }

        let topY = right.y - trunk / 2 + topW / 2
        let botY = right.y + trunk / 2 - botW / 2
        let startTop = top.y + (topY - top.y) * t
        let startBot = bot.y + (botY - bot.y) * t
        var path = Path()
        path.addPath(cubicCapsule(
            stackedLane(
                from: CGPoint(x: top.x, y: startTop),
                to: CGPoint(x: mergeX + seam, y: topY),
                startY: startTop,
                endY: topY,
                holdT: 0.5
            ),
            width: topW,
            startCap: .round,
            endCap: .butt
        ))
        path.addPath(cubicCapsule(
            stackedLane(
                from: CGPoint(x: bot.x, y: startBot),
                to: CGPoint(x: mergeX + seam, y: botY),
                startY: startBot,
                endY: botY,
                holdT: 0.5
            ),
            width: botW,
            startCap: .round,
            endCap: .butt
        ))
        path.addPath(capsule(
            from: CGPoint(x: mergeX - seam, y: right.y),
            to: right,
            width: trunk,
            startCap: .butt,
            endCap: .round
        ))
        return path.normalizedSilhouette()
    }

    static func capsule(from start: CGPoint, to end: CGPoint, width: CGFloat) -> Path {
        capsule(from: start, to: end, width: width, startCap: .round, endCap: .round)
    }

    static func capsule(
        from start: CGPoint,
        to end: CGPoint,
        width: CGFloat,
        startCap: Cap,
        endCap: Cap
    ) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let c1 = CGPoint(x: start.x + dx * 0.42, y: start.y + dy * 0.08)
        let c2 = CGPoint(x: start.x + dx * 0.58, y: start.y + dy * 0.92)
        return cubicCapsule(
            FlowCubic(p0: start, c1: c1, c2: c2, p1: end),
            width: width,
            startCap: startCap,
            endCap: endCap
        )
    }

    /// Builds a ribbon around an explicit bezier centre-line. This is also used
    /// by the transition renderer so animated paths keep the exact same 16pt
    /// rounded-rectangle caps as the static paths (instead of SwiftUI's much
    /// larger semicircular stroke caps).
    static func cubicCapsule(
        _ cubic: FlowCubic,
        width: CGFloat,
        startCap: Cap = .round,
        endCap: Cap = .round
    ) -> Path {
        if startCap == .round,
           endCap == .round,
           abs(cubic.p1.y - cubic.p0.y) < 0.5,
           abs(cubic.c1.y - cubic.p0.y) < 0.5,
           abs(cubic.c2.y - cubic.p1.y) < 0.5 {
            return continuousStadium(from: cubic.p0, to: cubic.p1, width: width)
        }
        var spine = Path()
        spine.move(to: cubic.p0)
        spine.addCurve(to: cubic.p1, control1: cubic.c1, control2: cubic.c2)
        var path = spine.strokedPath(StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round))
        if startCap == .round {
            addRoundedEndCap(
                &path,
                at: cubic.p0,
                outward: CGPoint(x: cubic.p0.x - cubic.c1.x, y: cubic.p0.y - cubic.c1.y),
                width: width
            )
        }
        if endCap == .round {
            addRoundedEndCap(
                &path,
                at: cubic.p1,
                outward: CGPoint(x: cubic.p1.x - cubic.c2.x, y: cubic.p1.y - cubic.c2.y),
                width: width
            )
        }
        return path.normalizedSilhouette()
    }

    /// Fuses touching lanes into one silhouette before the glass material is
    /// sampled. This keeps a two-lane trunk visually identical to its eventual
    /// single-lane form at the end of a merge.
    static func combinedSilhouette(_ paths: [Path]) -> Path {
        var silhouette = Path()
        for path in paths {
            silhouette.addPath(path)
        }
        return silhouette.normalizedSilhouette()
    }

    /// One closed rounded-rect. Avoids stroke+cap subpaths whose corner vertices
    /// become two static Liquid Glass speculars on the left end.
    private static func continuousStadium(from start: CGPoint, to end: CGPoint, width: CGFloat) -> Path {
        let radius = FlowRibbon.capRadius(for: width)
        let half = width / 2
        let rect = CGRect(
            x: min(start.x, end.x) - radius,
            y: min(start.y, end.y) - half,
            width: abs(end.x - start.x) + radius * 2,
            height: width
        )
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }

    /// Rounded-rect cap on a butt end. Degenerates to a semicircle when the
    /// ribbon is no thicker than the node diameter.
    private static func addRoundedEndCap(
        _ path: inout Path,
        at center: CGPoint,
        outward: CGPoint,
        width: CGFloat
    ) {
        let len = max(0.001, hypot(outward.x, outward.y))
        let ux = outward.x / len
        let uy = outward.y / len
        let nx = -uy
        let ny = ux
        let radius = FlowRibbon.capRadius(for: width)
        let half = width / 2
        let leading = CGPoint(x: center.x + nx * half, y: center.y + ny * half)
        let trailing = CGPoint(x: center.x - nx * half, y: center.y - ny * half)
        let cA = CGPoint(x: center.x + nx * (half - radius), y: center.y + ny * (half - radius))
        let cB = CGPoint(x: center.x - nx * (half - radius), y: center.y - ny * (half - radius))
        let outerA = CGPoint(x: cA.x + ux * radius, y: cA.y + uy * radius)
        let outerB = CGPoint(x: cB.x + ux * radius, y: cB.y + uy * radius)
        let throughA = CGPoint(x: cA.x + (nx + ux) * radius, y: cA.y + (ny + uy) * radius)
        let throughB = CGPoint(x: cB.x + (ux - nx) * radius, y: cB.y + (uy - ny) * radius)

        path.move(to: leading)
        addShortArc(&path, center: cA, radius: radius, from: leading, to: outerA, through: throughA)
        path.addLine(to: outerB)
        addShortArc(&path, center: cB, radius: radius, from: outerB, to: trailing, through: throughB)
        path.closeSubpath()
    }

    private static func addShortArc(
        _ path: inout Path,
        center: CGPoint,
        radius: CGFloat,
        from start: CGPoint,
        to end: CGPoint,
        through mid: CGPoint
    ) {
        let startAngle = Angle(radians: atan2(start.y - center.y, start.x - center.x))
        let endAngle = Angle(radians: atan2(end.y - center.y, end.x - center.x))
        let midAngle = atan2(mid.y - center.y, mid.x - center.x)
        var delta = endAngle.radians - startAngle.radians
        while delta <= 0 { delta += 2 * .pi }
        var midDelta = midAngle - startAngle.radians
        while midDelta < 0 { midDelta += 2 * .pi }
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: midDelta > delta
        )
    }
}

private extension Path {
    /// Merge overlapping stroke/cap subpaths so glass lighting sees one outline,
    /// not extra vertices at the rounded-end joins.
    func normalizedSilhouette() -> Path {
        Path(cgPath.normalized(using: .winding))
    }
}

/// Capsule ↔ Y morphs are 1.65s long. Unplug/plugin often lands as two IOKit
/// mode changes in a row (charging → adapterHold → discharging). Restarting
/// the clock on the second sample replaces a live Y merge with capsule→capsule
/// and reads as a jump. Keep the original fork source until that close finishes,
/// and reverse elapsed time when the mode flaps back.
enum RibbonMorph {
    static let duration: TimeInterval = 1.65

    enum Decision: Equatable {
        case start(from: PowerSnapshot)
        case keepGoing
        case reverse(from: PowerSnapshot, elapsed: TimeInterval)
    }

    enum Silhouette: Equatable {
        case chargingFork
        case underpoweredFork
        case capsule

        init(_ mode: EnergyFlowMode) {
            switch mode {
            case .charging: self = .chargingFork
            case .underpowered: self = .underpoweredFork
            case .adapterHold, .discharging: self = .capsule
            }
        }
    }

    static func easedProgress(elapsed: TimeInterval, duration: TimeInterval = duration) -> Double {
        let raw = min(max(elapsed / duration, 0), 1)
        return raw * raw * (3 - 2 * raw)
    }

    static func decide(
        from: PowerSnapshot?,
        startedAt: Date?,
        duration: TimeInterval,
        previous: PowerSnapshot,
        nextMode: EnergyFlowMode,
        now: Date
    ) -> Decision {
        guard let from, let startedAt else {
            return .start(from: previous)
        }

        let elapsed = now.timeIntervalSince(startedAt)
        if elapsed >= duration {
            return .start(from: previous)
        }

        let origin = Silhouette(from.flowMode)
        let heading = Silhouette(previous.flowMode)
        let next = Silhouette(nextMode)

        if next == origin {
            return .reverse(from: previous, elapsed: elapsed)
        }

        if next == heading {
            return .keepGoing
        }

        return .start(from: previous)
    }
}
