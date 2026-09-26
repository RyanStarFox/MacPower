import SwiftUI
import XCTest
@testable import MacPower

final class EnergyFlowModeTests: XCTestCase {
    func testUnpluggedIsDischarging() {
        let mode = EnergyFlowMode.derive(
            hasBattery: true,
            externalConnected: false,
            isCharging: false,
            instantAmperageMilli: -1800,
            batteryWatts: -18
        )
        XCTAssertEqual(mode, .discharging)
    }

    func testChargingWhenPluggedAndCurrentPositive() {
        let mode = EnergyFlowMode.derive(
            hasBattery: true,
            externalConnected: true,
            isCharging: true,
            instantAmperageMilli: 3200,
            batteryWatts: 40
        )
        XCTAssertEqual(mode, .charging)
    }

    func testAdapterHoldWhenPluggedNotCharging() {
        let mode = EnergyFlowMode.derive(
            hasBattery: true,
            externalConnected: true,
            isCharging: false,
            instantAmperageMilli: 0,
            batteryWatts: 0.1
        )
        XCTAssertEqual(mode, .adapterHold)
    }

    func testUnderpoweredWhenPluggedAndCurrentNegative() {
        let mode = EnergyFlowMode.derive(
            hasBattery: true,
            externalConnected: true,
            isCharging: false,
            instantAmperageMilli: -2100,
            batteryWatts: -25
        )
        XCTAssertEqual(mode, .underpowered)
    }
}

final class HeldLoadWattsTests: XCTestCase {
    func testUnplugDropoutKeepsLastRealLoad() {
        XCTAssertEqual(HeldLoadWatts.hold(current: 0, previous: 18.4), 18.4)
        XCTAssertEqual(HeldLoadWatts.hold(current: 0.1, previous: 9), 9)
    }

    func testRealSampleReplacesHeldLoad() {
        XCTAssertEqual(HeldLoadWatts.hold(current: 12.2, previous: 18.4), 12.2)
        XCTAssertEqual(HeldLoadWatts.hold(current: 0.5, previous: 9), 0.5)
    }

    func testMissingHistoryDoesNotInventLoad() {
        XCTAssertEqual(HeldLoadWatts.hold(current: 0, previous: nil), 0)
        XCTAssertEqual(HeldLoadWatts.hold(current: 0.2, previous: 0.1), 0.2)
    }
}

final class FlowRibbonTests: XCTestCase {
    func testTrunkWidthIsTripleNodeDiameter() {
        XCTAssertEqual(FlowRibbon.nodeDiameter, 32)
        XCTAssertEqual(FlowRibbon.trunkWidth(totalWatts: 9.1), FlowRibbon.nodeDiameter * 3)
        XCTAssertEqual(FlowRibbon.trunkWidth(totalWatts: 4), FlowRibbon.nodeDiameter * 3)
        XCTAssertEqual(FlowRibbon.trunkWidth(totalWatts: 100), FlowRibbon.nodeDiameter * 3)
    }

    func testCapRadiusIsRoundedRectUntilThinnerThanNode() {
        XCTAssertEqual(FlowRibbon.capRadius(for: 20), 10)
        XCTAssertEqual(FlowRibbon.capRadius(for: 32), 16)
        XCTAssertEqual(FlowRibbon.capRadius(for: 96), 16)
        XCTAssertEqual(FlowRibbon.endInset(for: 96), 16)
    }

    func testSplitWidthsPreserveRatioAndSum() {
        let trunk: CGFloat = 40
        let widths = FlowRibbon.splitWidths(first: 15.52, second: 20.16, trunk: trunk)
        XCTAssertEqual(widths.0 + widths.1, trunk, accuracy: 0.001)
        XCTAssertEqual(Double(widths.0 / widths.1), 15.52 / 20.16, accuracy: 0.001)
    }

    func testSheenSpeedIncreasesWithWatts() {
        let slow = FlowRibbon.sheenSpeed(watts: 8)
        let mid = FlowRibbon.sheenSpeed(watts: 22)
        let fast = FlowRibbon.sheenSpeed(watts: 70)
        XCTAssertGreaterThan(mid, slow)
        XCTAssertGreaterThan(fast, mid)
        XCTAssertGreaterThan(slow, 0)
    }

    func testFilamentSpeedIncreasesWithWattsAndIsFasterThanSheen() {
        let slow = FlowRibbon.filamentSpeed(watts: 8)
        let mid = FlowRibbon.filamentSpeed(watts: 22)
        let fast = FlowRibbon.filamentSpeed(watts: 70)
        XCTAssertGreaterThan(mid, slow)
        XCTAssertGreaterThan(fast, mid)
        XCTAssertGreaterThan(FlowRibbon.filamentSpeed(watts: 22), FlowRibbon.sheenSpeed(watts: 22))
    }

    func testParticleCountIsCapped() {
        XCTAssertEqual(FlowRibbon.particleCount(laneWidth: 96), 67)
        XCTAssertEqual(FlowRibbon.particleCount(laneWidth: 10), 28)
        XCTAssertEqual(FlowRibbon.particleCount(laneWidth: 400), 72)
    }

    func testFilamentCountIsSmall() {
        XCTAssertEqual(FlowRibbon.filamentCount(laneWidth: 96), 9)
        XCTAssertEqual(FlowRibbon.filamentCount(laneWidth: 10), 6)
        XCTAssertEqual(FlowRibbon.filamentCount(laneWidth: 400), 14)
    }

    func testZeroWattsDoesNotNaN() {
        let widths = FlowRibbon.splitWidths(first: 0, second: 0, trunk: 20)
        XCTAssertEqual(widths.0 + widths.1, 20, accuracy: 0.001)
        XCTAssertGreaterThan(widths.0, 0)
        XCTAssertGreaterThan(widths.1, 0)
    }

    func testStraightCapsuleIsSingleSubpath() {
        let path = ForkOutline.capsule(
            from: CGPoint(x: 16, y: 48),
            to: CGPoint(x: 400, y: 48),
            width: 96
        )
        XCTAssertEqual(path.subpathCount, 1)
        XCTAssertEqual(path.boundingRect, CGRect(x: 0, y: 0, width: 416, height: 96), accuracy: 0.01)
    }

    func testForkCapsNormalizeToSingleSilhouette() {
        let path = ForkOutline.splitPath(
            left: CGPoint(x: 16, y: 60),
            top: CGPoint(x: 400, y: 16),
            bot: CGPoint(x: 400, y: 104),
            topW: 32,
            botW: 64
        )
        XCTAssertEqual(path.subpathCount, 1)
    }

    func testWattLabelSitsInTheMidBody() {
        let straight = FlowCubic(
            p0: CGPoint(x: 24, y: 40),
            c1: CGPoint(x: 24 + 336 * 0.45, y: 40),
            c2: CGPoint(x: 24 + 336 * 0.55, y: 40),
            p1: CGPoint(x: 360, y: 40)
        )
        XCTAssertEqual(FlowRibbon.wattLabelX(on: straight), 192, accuracy: 0.5)

        // Forked lanes use the same mid-span: the trunk is part of each bar.
        let mergeLane = ForkOutline.stackedLane(
            from: CGPoint(x: 24, y: 20),
            to: CGPoint(x: 360, y: 60),
            startY: 20,
            endY: 52,
            holdT: 1 - FlowRibbon.forkT
        )
        XCTAssertEqual(FlowRibbon.wattLabelX(on: mergeLane), 192, accuracy: 0.5)
    }

    func testWattLabelUsesLocalRibbonCenterNotTipY() {
        let left = CGPoint(x: 16, y: 60)
        let top = CGPoint(x: 344, y: 20)
        let bot = CGPoint(x: 344, y: 100)
        let topW: CGFloat = 40
        let botW: CGFloat = 56
        let body = ForkOutline.splitPath(left: left, top: top, bot: bot, topW: topW, botW: botW)
        let topLane = ForkOutline.stackedLane(
            from: left,
            to: top,
            startY: left.y - (topW + botW) / 2 + topW / 2,
            endY: top.y,
            holdT: FlowRibbon.forkT
        )
        let span = top.x - left.x
        let splitX = left.x + span * FlowRibbon.forkT
        let x = FlowRibbon.wattLabelX(on: topLane)
        XCTAssertEqual(x, (left.x + top.x) / 2, accuracy: 0.5)
        XCTAssertGreaterThan(x, splitX)
        let hintY = FlowRibbon.spineY(on: topLane, atX: x)
        let centered = FlowRibbon.centerY(
            of: body,
            atX: x,
            hintY: hintY,
            searchRadius: topW * 0.5 + 8
        )
        XCTAssertEqual(centered, hintY, accuracy: topW * 0.35)
        XCTAssertTrue(body.contains(CGPoint(x: x, y: centered)))
    }

    func testCollapseDoesNotDeflateCapsuleCorners() {
        let trunk: CGFloat = 96
        let topW: CGFloat = 40
        let botW: CGFloat = 56
        let top = CGPoint(x: 16, y: 20)
        let bot = CGPoint(x: 16, y: 100)
        let right = CGPoint(x: 344, y: 60)
        let remaining: CGFloat = 40
        let mergeT = remaining / (right.x - top.x)
        let path = ForkOutline.mergePath(
            top: top,
            bot: bot,
            right: right,
            topW: topW,
            botW: botW,
            mergeT: mergeT,
            collapse: FlowRibbon.forkCollapse(remainingLength: remaining, minimum: trunk)
        )
        let destination = ForkOutline.capsule(
            from: CGPoint(x: top.x, y: right.y),
            to: right,
            width: trunk
        )
        let inset: CGFloat = 6
        XCTAssertTrue(
            path.contains(CGPoint(x: top.x + 20, y: destination.boundingRect.minY + inset)),
            "top-left capsule corner caved in during collapse"
        )
        XCTAssertTrue(
            path.contains(CGPoint(x: top.x + 20, y: destination.boundingRect.maxY - inset)),
            "bottom-left capsule corner caved in during collapse"
        )
    }

    func testCollapseDoesNotPunchAHoleThroughTheRibbon() {
        let left = CGPoint(x: 16, y: 60)
        let top = CGPoint(x: 344, y: 20)
        let bot = CGPoint(x: 344, y: 100)
        let minimum: CGFloat = 96
        for step in 0...12 {
            let phase = CGFloat(step) / 12
            let splitT = FlowRibbon.forkT + (1 - FlowRibbon.forkT) * phase
            let remaining = (top.x - left.x) * (1 - splitT)
            let path = ForkOutline.splitPath(
                left: left,
                top: top,
                bot: bot,
                topW: 40,
                botW: 56,
                splitT: splitT,
                collapse: FlowRibbon.forkCollapse(remainingLength: remaining, minimum: minimum)
            )
            XCTAssertTrue(
                path.contains(CGPoint(x: left.x + 24, y: left.y)),
                "trunk holed at phase \(phase)"
            )
            let splitX = left.x + (top.x - left.x) * splitT
            if splitX - left.x > 20 {
                XCTAssertTrue(
                    path.contains(CGPoint(x: splitX - 10, y: left.y)),
                    "crotch holed at phase \(phase)"
                )
            }
        }
    }

    func testForkCollapsePinchesShortBranchesInsteadOfSnapping() {
        XCTAssertEqual(FlowRibbon.forkCollapse(remainingLength: 80, minimum: 64), 0)
        XCTAssertEqual(FlowRibbon.forkCollapse(remainingLength: 0, minimum: 64), 1)
        XCTAssertEqual(FlowRibbon.forkCollapse(remainingLength: 32, minimum: 64), 1)
        XCTAssertEqual(FlowRibbon.forkCollapse(remainingLength: 48, minimum: 64), 0.5, accuracy: 0.001)
        XCTAssertEqual(FlowRibbon.forkCollapse(remainingLength: -4, minimum: 64), 1)
    }

    func testYCapsuleCloseIsOpeningPlayedBackwards() {
        XCTAssertEqual(FlowRibbon.splitT(open: 0), 1)
        XCTAssertEqual(FlowRibbon.splitT(open: 1), FlowRibbon.forkT, accuracy: 0.0001)
        XCTAssertEqual(
            FlowRibbon.splitT(open: 0.3),
            1 - (1 - FlowRibbon.forkT) * 0.3,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(FlowRibbon.splitT(open: 0.2), FlowRibbon.splitT(open: 0.8))
        XCTAssertEqual(FlowRibbon.mergeT(open: 0), 0)
        XCTAssertEqual(FlowRibbon.mergeT(open: 1), 1 - FlowRibbon.forkT)
        XCTAssertEqual(FlowRibbon.mergeT(open: 0.4), (1 - FlowRibbon.forkT) * 0.4, accuracy: 0.0001)
        XCTAssertLessThan(FlowRibbon.mergeT(open: 0.2), FlowRibbon.mergeT(open: 0.8))
    }

    func testCollapsedForkMatchesCapsuleBounds() {
        let collapsed = ForkOutline.splitPath(
            left: CGPoint(x: 16, y: 60),
            top: CGPoint(x: 400, y: 16),
            bot: CGPoint(x: 400, y: 104),
            topW: 32,
            botW: 64,
            splitT: 0.9,
            collapse: 1
        )
        let capsule = ForkOutline.capsule(
            from: CGPoint(x: 16, y: 60),
            to: CGPoint(x: 400, y: 60),
            width: 96
        )
        XCTAssertEqual(collapsed.boundingRect, capsule.boundingRect, accuracy: 0.01)
        XCTAssertEqual(collapsed.subpathCount, 1)
    }

    func testCollapseDoesNotBridgeForksWithATrunkBar() {
        let size = CGSize(width: 360, height: 120)
        let trunk = FlowRibbon.trunkWidth(totalWatts: 1)
        let inset = FlowRibbon.capRadius(for: trunk)
        let topW: CGFloat = 40
        let botW: CGFloat = 56
        let left = CGPoint(x: inset, y: size.height / 2)
        let top = CGPoint(x: size.width - inset, y: topW / 2)
        let bot = CGPoint(x: size.width - inset, y: size.height - botW / 2)
        let gap = CGPoint(x: size.width - inset - 8, y: size.height / 2 - 8)

        let open = ForkOutline.splitPath(
            left: left, top: top, bot: bot, topW: topW, botW: botW, splitT: FlowRibbon.forkT, collapse: 0
        )
        XCTAssertFalse(open.contains(gap), "the charging Y must keep a gap between the two end ports")

        let early = ForkOutline.splitPath(
            left: left, top: top, bot: bot, topW: topW, botW: botW, splitT: 0.55, collapse: 0.08
        )
        XCTAssertFalse(
            early.contains(gap),
            "collapse must pinch the two ports together, not drop in a trunk-height bar that fills the gap"
        )

        let closed = ForkOutline.splitPath(
            left: left, top: top, bot: bot, topW: topW, botW: botW, splitT: 1, collapse: 1
        )
        XCTAssertTrue(closed.contains(CGPoint(x: size.width / 2, y: size.height / 2)))
    }

    func testChargingMergeKeepsRightEdgeUntilCapsule() {
        let size = CGSize(width: 360, height: 96)
        let trunk = FlowRibbon.trunkWidth(totalWatts: 1)
        let inset = FlowRibbon.capRadius(for: trunk)
        let topW: CGFloat = 40
        let botW: CGFloat = 56
        let left = CGPoint(x: inset, y: size.height / 2)
        let top = CGPoint(x: size.width - inset, y: topW / 2)
        let bot = CGPoint(x: size.width - inset, y: size.height - botW / 2)
        let destination = ForkOutline.capsule(
            from: left,
            to: CGPoint(x: top.x, y: left.y),
            width: trunk
        )
        let expectedMaxX = destination.boundingRect.maxX
        let minimum = max(trunk, FlowRibbon.nodeDiameter * 2)

        var previousMaxX: CGFloat?
        var worstJump: CGFloat = 0
        for step in 0...120 {
            let phase = CGFloat(step) / 120
            let splitT = FlowRibbon.forkT + (1 - FlowRibbon.forkT) * phase
            let remaining = (size.width - inset * 2) * (1 - splitT)
            let path = ForkOutline.splitPath(
                left: left,
                top: top,
                bot: bot,
                topW: 40,
                botW: 56,
                splitT: splitT,
                collapse: FlowRibbon.forkCollapse(remainingLength: remaining, minimum: minimum)
            )
            let maxX = path.boundingRect.maxX
            XCTAssertEqual(maxX, expectedMaxX, accuracy: 1.2, "right edge receded at phase \(phase)")
            if let previousMaxX {
                worstJump = max(worstJump, abs(maxX - previousMaxX))
            }
            previousMaxX = maxX
        }
        XCTAssertLessThan(worstJump, 1.2, "right edge jumped \(worstJump) during Y merge")
    }

    func testRibbonOverlayHidesWattMotionBeforeIncomingAppears() {
        let start = FlowRibbonOverlay.opacities(progress: 0)
        XCTAssertEqual(start.outgoing, 1, accuracy: 0.001)
        XCTAssertEqual(start.incoming, 0, accuracy: 0.001)

        let mid = FlowRibbonOverlay.opacities(progress: 0.5)
        XCTAssertEqual(mid.outgoing, 0, accuracy: 0.001)
        XCTAssertEqual(mid.incoming, 0, accuracy: 0.001)

        let end = FlowRibbonOverlay.opacities(progress: 1)
        XCTAssertEqual(end.outgoing, 0, accuracy: 0.001)
        XCTAssertEqual(end.incoming, 1, accuracy: 0.001)
    }

    func testRibbonOverlayDoesNotCrossfadeWattMotion() {
        XCTAssertEqual(FlowRibbonOverlay.opacities(progress: 0.26).outgoing, 0, accuracy: 0.001)
        XCTAssertEqual(FlowRibbonOverlay.opacities(progress: 0.26).incoming, 0, accuracy: 0.001)
        XCTAssertEqual(FlowRibbonOverlay.opacities(progress: 0.62).outgoing, 0, accuracy: 0.001)
        XCTAssertEqual(FlowRibbonOverlay.opacities(progress: 0.62).incoming, 0, accuracy: 0.001)
        XCTAssertGreaterThan(FlowRibbonOverlay.opacities(progress: 0.8).incoming, 0.2)
        XCTAssertEqual(FlowRibbonOverlay.opacities(progress: 0.8).outgoing, 0, accuracy: 0.001)
    }
}

private extension Path {
    var subpathCount: Int {
        var count = 0
        cgPath.applyWithBlock { element in
            if element.pointee.type == .moveToPoint {
                count += 1
            }
        }
        return count
    }
}

private func XCTAssertEqual(_ rect: CGRect, _ expected: CGRect, accuracy: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(rect.origin.x, expected.origin.x, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(rect.origin.y, expected.origin.y, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(rect.width, expected.width, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(rect.height, expected.height, accuracy: accuracy, file: file, line: line)
}

final class EnergyMotionStyleTests: XCTestCase {
    func testMotionOptionsAndDefault() {
        XCTAssertEqual(EnergyMotionStyle.allCases, [
            .sheen,
            .filaments, .filamentsSolid, .filamentsWhite,
            .particles, .particlesSolid, .particlesWhite,
            .off
        ])
        XCTAssertTrue(EnergyMotionStyle.sheen.needsAnimation)
        XCTAssertTrue(EnergyMotionStyle.filaments.needsAnimation)
        XCTAssertTrue(EnergyMotionStyle.particlesSolid.needsAnimation)
        XCTAssertFalse(EnergyMotionStyle.off.needsAnimation)
        XCTAssertTrue(EnergyMotionStyle.sheen.usesCanvasTimeline)
        XCTAssertTrue(EnergyMotionStyle.filamentsWhite.usesCanvasTimeline)
        XCTAssertFalse(EnergyMotionStyle.off.usesCanvasTimeline)
        XCTAssertEqual(EnergyMotionStyle.filaments.pigment, .gradient)
        XCTAssertEqual(EnergyMotionStyle.particlesSolid.pigment, .solid)
        XCTAssertEqual(EnergyMotionStyle.filamentsWhite.pigment, .white)
    }

    func testMotionStylePersists() {
        let defaults = UserDefaults(suiteName: "MacPower.MotionStyleTests")!
        defaults.removePersistentDomain(forName: "MacPower.MotionStyleTests")
        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.motionStyle, .filaments)
        first.motionStyle = .particlesSolid
        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.motionStyle, .particlesSolid)
        defaults.removePersistentDomain(forName: "MacPower.MotionStyleTests")
    }

    func testLegacyBandAndCometMapToSheen() {
        let suite = "MacPower.MotionMigrateTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("band", forKey: "motionStyle")
        XCTAssertEqual(AppSettings(defaults: defaults).motionStyle, .sheen)
        defaults.set("comet", forKey: "motionStyle")
        XCTAssertEqual(AppSettings(defaults: defaults).motionStyle, .sheen)
        defaults.set("filaments", forKey: "motionStyle")
        XCTAssertEqual(AppSettings(defaults: defaults).motionStyle, .filaments)
        XCTAssertEqual(EnergyMotionStyle.resolved(stored: nil), .filaments)
        XCTAssertEqual(EnergyMotionStyle.resolved(stored: "unknown"), .filaments)
        defaults.removePersistentDomain(forName: suite)
    }

    func testLegacyEnergyMotionKeyMigrates() {
        let suite = "MacPower.MotionLegacyKeyTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("particles", forKey: "energyMotion")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.motionStyle, .particles)
        XCTAssertEqual(defaults.string(forKey: "motionStyle"), "particles")
        XCTAssertNil(defaults.string(forKey: "energyMotion"))
        defaults.removePersistentDomain(forName: suite)
    }

    func testDecodeNeverCrashesOnLegacyCases() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(EnergyMotionStyle.self, from: Data("\"band\"".utf8)), .sheen)
        XCTAssertEqual(try decoder.decode(EnergyMotionStyle.self, from: Data("\"comet\"".utf8)), .sheen)
        XCTAssertEqual(try decoder.decode(EnergyMotionStyle.self, from: Data("\"spark\"".utf8)), .sheen)
        XCTAssertEqual(try decoder.decode(EnergyMotionStyle.self, from: Data("\"powder\"".utf8)), .particles)
        XCTAssertEqual(try decoder.decode(EnergyMotionStyle.self, from: Data("\"unknown\"".utf8)), .filaments)
        XCTAssertEqual(try decoder.decode(EnergyMotionStyle.self, from: Data("\"sheen\"".utf8)), .sheen)
        XCTAssertEqual(try decoder.decode(EnergyMotionStyle.self, from: Data("\"filamentsSolid\"".utf8)), .filamentsSolid)
        let encoded = try JSONEncoder().encode(EnergyMotionStyle.filaments)
        XCTAssertEqual(try decoder.decode(EnergyMotionStyle.self, from: encoded), .filaments)
    }

    func testMotionFrameRateDefaultsTo60AndPersists() {
        let suite = "MacPower.MotionFrameRateTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.motionFrameRate, .hz60)
        XCTAssertEqual(EnergyMotionFrameRate.allCases.map(\.rawValue), [15, 24, 30, 45, 60, 75, 90, 120])
        first.motionFrameRate = .hz30
        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.motionFrameRate, .hz30)
        XCTAssertEqual(EnergyMotionFrameRate.resolved(stored: 24), .hz24)
        XCTAssertEqual(EnergyMotionFrameRate.resolved(stored: 7), .hz60)
        XCTAssertEqual(EnergyMotionFrameRate.resolved(stored: nil), .hz60)
        defaults.removePersistentDomain(forName: suite)
    }

    func testPulseFlowIconsDefaultsOnAndPersists() {
        let suite = "MacPower.PulseFlowIconsTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        XCTAssertTrue(first.pulseFlowIcons)
        first.pulseFlowIcons = false
        let second = AppSettings(defaults: defaults)
        XCTAssertFalse(second.pulseFlowIcons)
        defaults.removePersistentDomain(forName: suite)
    }

    func testShowPopoverArrowDefaultsOnAndPersists() {
        let suite = "MacPower.PopoverArrowTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        XCTAssertTrue(first.showPopoverArrow)
        first.showPopoverArrow = false
        let second = AppSettings(defaults: defaults)
        XCTAssertFalse(second.showPopoverArrow)
        defaults.removePersistentDomain(forName: suite)
    }

    func testMenuBarRightClickDefaultsToStatusMenuAndPersists() {
        let suite = "MacPower.RightClickActionTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.menuBarRightClickAction, .statusMenu)
        first.menuBarRightClickAction = .openPanel
        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.menuBarRightClickAction, .openPanel)
        defaults.removePersistentDomain(forName: suite)
    }

    func testShowRingsAndFlowDefaultsOnAndPersists() {
        let suite = "MacPower.PopoverSections.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        XCTAssertTrue(first.showStatusRings)
        XCTAssertTrue(first.showEnergyFlow)
        first.showStatusRings = false
        first.showEnergyFlow = false
        let second = AppSettings(defaults: defaults)
        XCTAssertFalse(second.showStatusRings)
        XCTAssertFalse(second.showEnergyFlow)
        defaults.removePersistentDomain(forName: suite)
    }

    func testLanguageDefaultsToSystemAndPersists() {
        let suite = "MacPower.LanguageTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.language, .system)
        first.language = .simplifiedChinese
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "zh-Hans")
        XCTAssertNil(defaults.persistentDomain(forName: suite)?["AppleLanguages"])
        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.language, .simplifiedChinese)
        first.language = .system
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "system")
        XCTAssertEqual(AppSettings(defaults: defaults).language, .system)
        defaults.removePersistentDomain(forName: suite)
    }

    func testClearsLegacyAppleLanguages() {
        let suite = "MacPower.LanguageAppleLanguagesTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(["ja"], forKey: "AppleLanguages")
        defaults.set("en", forKey: "appLanguage")
        _ = AppSettings(defaults: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: suite)?["AppleLanguages"])
        defaults.removePersistentDomain(forName: suite)
    }

    func testUnknownLanguageFallsBackToSystem() {
        XCTAssertEqual(AppLanguage.resolved(stored: nil), .system)
        XCTAssertEqual(AppLanguage.resolved(stored: ""), .system)
        XCTAssertEqual(AppLanguage.resolved(stored: "nope"), .system)
        XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), [
            "system", "zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es", "pt-BR", "it", "ru"
        ])
    }
}

final class LocalizationTests: XCTestCase {
    func testExplicitLanguagesReadMatchingLproj() {
        XCTAssertEqual(Localization.string("settings.title", language: .english), "Settings")
        XCTAssertEqual(Localization.string("settings.title", language: .simplifiedChinese), "设置")
        XCTAssertEqual(Localization.string("settings.title", language: .traditionalChinese), "設定")
        XCTAssertEqual(Localization.string("settings.title", language: .japanese), "設定")
        XCTAssertEqual(Localization.string("energy.supplyPower", language: .japanese), "使用中の電力")
        XCTAssertEqual(
            Localization.string("ring.caption.battery %lld", language: .simplifiedChinese, Int64(87)),
            "电量：87%"
        )
        XCTAssertEqual(
            Localization.string("ring.caption.battery %lld", language: .japanese, Int64(87)),
            "バッテリー: 87%"
        )
        XCTAssertEqual(
            Localization.bundle(for: .brazilianPortuguese).bundlePath.hasSuffix("pt-BR.lproj"),
            true
        )
        XCTAssertEqual(
            Localization.string("settings.updates.automatic", language: .simplifiedChinese),
            "自动检查更新"
        )
        XCTAssertEqual(
            Localization.string("settings.about.version %@", language: .english, "1.2.4"),
            "Version 1.2.4"
        )
        XCTAssertEqual(Localization.string("settings.tab.rings", language: .simplifiedChinese), "圆环")
        XCTAssertEqual(Localization.string("settings.tab.flow", language: .simplifiedChinese), "能量流")
        XCTAssertEqual(Localization.string("settings.tab.rings", language: .english), "Rings")
        XCTAssertEqual(Localization.string("settings.tab.flow", language: .english), "Energy Flow")
        XCTAssertEqual(Localization.string("settings.section.general", language: .simplifiedChinese), "通用")
        XCTAssertEqual(Localization.string("settings.section.icon", language: .simplifiedChinese), "菜单栏")
        XCTAssertEqual(Localization.string("settings.icon.border", language: .simplifiedChinese), "边框")
        XCTAssertEqual(Localization.string("settings.icon.digits.inside", language: .simplifiedChinese), "电池内")
        XCTAssertEqual(Localization.string("settings.icon.tint.default", language: .simplifiedChinese), "默认")
        XCTAssertEqual(Localization.string("settings.icon.tint.defaultSlide", language: .simplifiedChinese), "默认·无极")
        XCTAssertEqual(Localization.string("settings.icon.tint.defaultGradient", language: .simplifiedChinese), "默认·渐变")
        XCTAssertEqual(Localization.string("settings.icon.tint.defaultSlideGradient", language: .simplifiedChinese), "默认·渐变无极")
        XCTAssertEqual(Localization.string("settings.icon.tint.sunset", language: .simplifiedChinese), "日落")
        XCTAssertEqual(Localization.string("settings.icon.tint.ocean", language: .simplifiedChinese), "海洋")
        XCTAssertEqual(Localization.string("settings.icon.tint.smooth", language: .simplifiedChinese), "无极电量")
        XCTAssertEqual(Localization.string("settings.icon.tint.lava", language: .simplifiedChinese), "熔岩")
        XCTAssertEqual(Localization.string("settings.icon.tint.dawn", language: .simplifiedChinese), "晨曦")
        XCTAssertEqual(Localization.string("settings.icon.tint.neon", language: .simplifiedChinese), "霓虹")
        XCTAssertEqual(Localization.string("settings.icon.tint.blend.slide", language: .simplifiedChinese), "随电量滑动")
        XCTAssertEqual(Localization.string("settings.icon.tint.blend.both", language: .english), "Gradient + slide")
    }
}

final class TimeEstimateTests: XCTestCase {
    func testSentinelIsUnknown() {
        XCTAssertNil(TimeEstimateService.sanitizedSystemMinutes(65535))
        XCTAssertNil(TimeEstimateService.sanitizedSystemMinutes(0))
        XCTAssertEqual(TimeEstimateService.sanitizedSystemMinutes(64), 64)
    }

    func testFullTimeUsesChargeRateWhenSystemMissing() {
        let minutes = TimeEstimateService.timeToFullMinutes(
            isCharging: true,
            systemMinutes: nil,
            missingCapacityWh: 20,
            chargeWatts: 40
        )
        XCTAssertEqual(minutes, 30)
    }

    func testFullTimeNilWhenNotCharging() {
        XCTAssertNil(
            TimeEstimateService.timeToFullMinutes(
                isCharging: false,
                systemMinutes: 40,
                missingCapacityWh: 20,
                chargeWatts: 40
            )
        )
    }

    func testEmptyTimeNilNearZeroWatts() {
        XCTAssertNil(
            TimeEstimateService.minutesFromEnergy(wattHours: 40, watts: 0.1)
        )
    }

    func testEmptyTimeFromEnergy() {
        XCTAssertEqual(
            TimeEstimateService.minutesFromEnergy(wattHours: 40, watts: 20),
            120
        )
    }

    func testPrefersSystemMinutesWhenOnBattery() {
        let minutes = TimeEstimateService.timeToEmptyMinutes(
            isOnBattery: true,
            systemMinutes: 90,
            remainingCapacityWh: 40,
            averageLoadWatts: 10
        )
        XCTAssertEqual(minutes, 90)
    }

    func testComputedRuntimeWhenPluggedUsesAverageLoad() {
        let minutes = TimeEstimateService.timeToEmptyMinutes(
            isOnBattery: false,
            systemMinutes: 90,
            remainingCapacityWh: 40,
            averageLoadWatts: 10
        )
        XCTAssertEqual(minutes, 240)
    }

    func testNominalVoltageWhileCharging() {
        let charging = TimeEstimateService.wattHours(milliAmpHours: 2000, voltageMilli: 13000, preferNominal: true)
        let discharging = TimeEstimateService.wattHours(milliAmpHours: 2000, voltageMilli: 11550, preferNominal: false)
        XCTAssertEqual(charging, 2 * 11.55, accuracy: 0.01)
        XCTAssertEqual(discharging, 2 * 11.55, accuracy: 0.01)
    }
}

final class SystemSnapshotTests: XCTestCase {
    func testCPUUsageIgnoresIdleDelta() {
        let previous = CPUTickSample.Ticks(user: 0, system: 0, idle: 0, nice: 0)
        let current = CPUTickSample.Ticks(user: 20, system: 10, idle: 70, nice: 0)
        XCTAssertEqual(CPUTickSample.usagePercent(previous: previous, current: current), 30, accuracy: 0.01)
    }

    func testCPUUsageZeroWhenNoDelta() {
        let ticks = CPUTickSample.Ticks(user: 4, system: 2, idle: 10, nice: 0)
        XCTAssertEqual(CPUTickSample.usagePercent(previous: ticks, current: ticks), 0)
    }

    func testResolvedPercentKeepsLastWhenTicksUnchanged() throws {
        let ticks = CPUTickSample.Ticks(user: 4, system: 2, idle: 10, nice: 0)
        let resolved = CPUTickSample.resolvedPercent(previous: ticks, current: ticks, lastPublished: 37)
        XCTAssertEqual(try XCTUnwrap(resolved), 37)
    }

    func testResolvedPercentUsesDeltaWhenTicksAdvance() throws {
        let previous = CPUTickSample.Ticks(user: 0, system: 0, idle: 0, nice: 0)
        let current = CPUTickSample.Ticks(user: 20, system: 10, idle: 70, nice: 0)
        let resolved = CPUTickSample.resolvedPercent(previous: previous, current: current, lastPublished: 8)
        XCTAssertEqual(try XCTUnwrap(resolved), 30, accuracy: 0.01)
    }

    func testResolvedPercentIsNilWithoutDeltaOrLastValue() {
        let ticks = CPUTickSample.Ticks(user: 1, system: 1, idle: 1, nice: 0)
        XCTAssertNil(CPUTickSample.resolvedPercent(previous: ticks, current: ticks, lastPublished: nil))
        XCTAssertNil(CPUTickSample.resolvedPercent(previous: nil, current: ticks, lastPublished: nil))
    }

    func testResolvedPercentKeepsLastWhenSampleMissing() throws {
        let ticks = CPUTickSample.Ticks(user: 1, system: 1, idle: 1, nice: 0)
        XCTAssertEqual(try XCTUnwrap(CPUTickSample.resolvedPercent(previous: ticks, current: nil, lastPublished: 22)), 22)
        XCTAssertEqual(try XCTUnwrap(CPUTickSample.resolvedPercent(previous: nil, current: ticks, lastPublished: 22)), 22)
    }

    func testMemoryOccupancy() {
        XCTAssertEqual(MemoryOccupancy.usagePercent(usedBytes: 8, totalBytes: 32), 25)
        XCTAssertEqual(MemoryOccupancy.usagePercent(usedBytes: 10, totalBytes: 0), 0)
        XCTAssertEqual(MemoryOccupancy.usagePercent(usedBytes: 50, totalBytes: 40), 100)
    }
}

final class MenuBarIconStyleTests: XCTestCase {
    func testSplitControlsRebuildTheLegacyStyles() {
        XCTAssertEqual(MenuBarIconStyle.from(outlined: false, digits: .none), .systemFill)
        XCTAssertEqual(MenuBarIconStyle.from(outlined: false, digits: .inside), .systemPercentInside)
        XCTAssertEqual(MenuBarIconStyle.from(outlined: false, digits: .beside), .classicBeside)
        XCTAssertEqual(MenuBarIconStyle.from(outlined: true, digits: .none), .outlineFill)
        XCTAssertEqual(MenuBarIconStyle.from(outlined: true, digits: .inside), .outlinePercentInside)
        XCTAssertEqual(MenuBarIconStyle.from(outlined: true, digits: .beside), .outlineClassicBeside)
    }

    func testLegacyStylesExposeBorderAndDigitPlacement() {
        XCTAssertFalse(MenuBarIconStyle.systemPercentInside.isOutlined)
        XCTAssertEqual(MenuBarIconStyle.systemPercentInside.digits, .inside)
        XCTAssertTrue(MenuBarIconStyle.outlineClassicBeside.isOutlined)
        XCTAssertEqual(MenuBarIconStyle.outlineClassicBeside.digits, .beside)
        XCTAssertTrue(MenuBarIconStyle.systemPercentInside.showsPercentInside)
        XCTAssertTrue(MenuBarIconStyle.classicBeside.showsPercentBeside)
        XCTAssertFalse(MenuBarIconStyle.systemFill.showsPercentInside)
        XCTAssertFalse(MenuBarIconStyle.outlineFill.showsPercentBeside)
    }
}

final class MenuBarTintTests: XCTestCase {
    func testDefaultPresetMatchesPreviousLowBatteryTint() {
        let scheme = MenuBarTintScheme.systemDefault
        XCTAssertEqual(scheme.swatch(percent: 50, flowMode: .charging), .menuBar)
        XCTAssertEqual(scheme.swatch(percent: 50, flowMode: .adapterHold), .menuBar)
        XCTAssertEqual(scheme.swatch(percent: 5, flowMode: .discharging), .systemRed)
        XCTAssertEqual(scheme.swatch(percent: 10, flowMode: .discharging), .systemRed)
        XCTAssertEqual(scheme.swatch(percent: 15, flowMode: .underpowered), .systemYellow)
        XCTAssertEqual(scheme.swatch(percent: 20, flowMode: .discharging), .systemYellow)
        XCTAssertEqual(scheme.swatch(percent: 21, flowMode: .discharging), .menuBar)
    }

    func testOffPresetNeverTints() {
        let scheme = MenuBarTintScheme.off
        XCTAssertEqual(scheme.swatch(percent: 5, flowMode: .discharging), .menuBar)
        XCTAssertEqual(scheme.swatch(percent: 100, flowMode: .charging), .menuBar)
    }

    func testBatteryLevelPresetColorsWhileCharging() {
        let scheme = MenuBarTintScheme.batteryLevel
        XCTAssertEqual(scheme.swatch(percent: 5, flowMode: .charging), .systemRed)
        XCTAssertEqual(scheme.swatch(percent: 25, flowMode: .charging), .systemOrange)
        XCTAssertEqual(scheme.swatch(percent: 40, flowMode: .adapterHold), .systemYellow)
        XCTAssertEqual(scheme.swatch(percent: 80, flowMode: .charging), .systemGreen)
    }

    func testPalettePresetsUseDifferentHighChargeColors() {
        let charging = EnergyFlowMode.charging
        XCTAssertNotEqual(
            MenuBarTintScheme.sunset.swatch(percent: 90, flowMode: charging),
            MenuBarTintScheme.ocean.swatch(percent: 90, flowMode: charging)
        )
        XCTAssertNotEqual(
            MenuBarTintScheme.aurora.swatch(percent: 90, flowMode: charging),
            MenuBarTintScheme.berry.swatch(percent: 90, flowMode: charging)
        )
        XCTAssertEqual(
            MenuBarTintScheme.sunset.swatch(percent: 90, flowMode: charging),
            MenuBarTintSwatch.rgb(0.98, 0.80, 0.52)
        )
    }

    func testChoosingCustomKeepsTheCurrentPresetBands() {
        let defaults = UserDefaults(suiteName: "MacPower.TintCustom.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.applyTintPreset(.ocean)
        settings.applyTintPreset(.custom)
        XCTAssertEqual(settings.menuBarTint.preset, .custom)
        XCTAssertEqual(settings.menuBarTint.bands.map(\.throughPercent), MenuBarTintScheme.ocean.bands.map(\.throughPercent))
    }

    func testEditingAPresetForksToCustomKeepingBands() {
        let defaults = UserDefaults(suiteName: "MacPower.TintFork.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.applyTintPreset(.defaultSlide)
        XCTAssertEqual(settings.menuBarTint.preset, .defaultSlide)
        let first = settings.menuBarTint.sortedBands[0]
        settings.menuBarTint = settings.menuBarTint.replacingBand(id: first.id, throughPercent: 12)
        XCTAssertEqual(settings.menuBarTint.preset, .custom)
        XCTAssertEqual(settings.menuBarTint.sortedBands.map(\.throughPercent), [12, 20, 100])
        XCTAssertEqual(settings.menuBarTint.sortedBands.map(\.blend), [.slide, .slide, .slide])
    }

    func testPercentTypingClampsAndIgnoresJunk() {
        let range = 11...19
        XCTAssertEqual(MenuBarTintPercentInput.commit("15", range: range, fallback: 12), 15)
        XCTAssertEqual(MenuBarTintPercentInput.commit("  18% ", range: range, fallback: 12), 18)
        XCTAssertEqual(MenuBarTintPercentInput.commit("≤16", range: range, fallback: 12), 16)
        XCTAssertEqual(MenuBarTintPercentInput.commit("９９", range: range, fallback: 12), 19)
        XCTAssertEqual(MenuBarTintPercentInput.commit("-3", range: range, fallback: 12), 11)
        XCTAssertEqual(MenuBarTintPercentInput.commit("abc", range: range, fallback: 12), 12)
        XCTAssertEqual(MenuBarTintPercentInput.commit("", range: range, fallback: 12), 12)
        XCTAssertEqual(MenuBarTintPercentInput.commit("10.9", range: range, fallback: 12), 11)
    }

    func testAddingABandInsertsAStopBeforeTheTop() {
        let added = MenuBarTintScheme.systemDefault.addingBand()
        XCTAssertEqual(added.preset, .custom)
        XCTAssertEqual(added.sortedBands.map(\.throughPercent), [10, 20, 60, 100])
        XCTAssertEqual(added.sortedBands[2].swatch, .systemGreen)
    }

    func testLegacyIconAndTintMigrate() {
        let defaults = UserDefaults(suiteName: "MacPower.MenuBarMigration.\(UUID().uuidString)")!
        defaults.set("outlineClassicBeside", forKey: "iconStyle")
        defaults.set(false, forKey: "lowBatteryTintEnabled")
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.iconOutlined)
        XCTAssertEqual(settings.digitPlacement, .beside)
        XCTAssertEqual(settings.iconStyle, .outlineClassicBeside)
        XCTAssertEqual(settings.menuBarTint.preset, .off)
        XCTAssertFalse(settings.lowBatteryTintEnabled)
    }

    func testSlideLerpsInsideABand() {
        let scheme = MenuBarTintScheme(
            preset: .custom,
            mode: .always,
            bands: [
                MenuBarTintBand(
                    throughPercent: 20,
                    swatch: .rgb(0, 1, 0),
                    blend: .slide,
                    lowRight: .rgb(1, 0, 0)
                ),
                MenuBarTintBand(throughPercent: 100, swatch: .rgb(0, 0, 1))
            ]
        )
        XCTAssertEqual(scheme.fillSwatches(percent: 0, flowMode: .charging).right, .rgb(1, 0, 0))
        XCTAssertEqual(scheme.fillSwatches(percent: 20, flowMode: .charging).right, .rgb(0, 1, 0))
        let mid = scheme.fillSwatches(percent: 10, flowMode: .charging)
        XCTAssertEqual(mid.left, mid.right)
        guard case .custom(let red, let green, let blue) = mid.right else {
            return XCTFail("expected mixed custom color")
        }
        XCTAssertEqual(red, 0.5, accuracy: 0.001)
        XCTAssertEqual(green, 0.5, accuracy: 0.001)
        XCTAssertEqual(blue, 0, accuracy: 0.001)
    }

    func testGradientKeepsLeftAndRightRegardlessOfPercent() {
        let pair = MenuBarTintScheme.lava.fillSwatches(percent: 50, flowMode: .charging)
        XCTAssertEqual(pair.left, .rgb(0.55, 0.06, 0.04))
        XCTAssertEqual(pair.right, .rgb(0.98, 0.62, 0.12))
        XCTAssertEqual(
            MenuBarTintScheme.lava.fillSwatches(percent: 8, flowMode: .charging).left,
            pair.left
        )
        XCTAssertNotEqual(pair.left, pair.right)
    }

    func testSlideGradientUsesFourColors() {
        let pairLow = MenuBarTintScheme.dawn.fillSwatches(percent: 0, flowMode: .charging)
        let pairHigh = MenuBarTintScheme.dawn.fillSwatches(percent: 45, flowMode: .charging)
        XCTAssertEqual(pairLow.left, .rgb(0.28, 0.08, 0.42))
        XCTAssertEqual(pairLow.right, .rgb(0.55, 0.12, 0.48))
        XCTAssertEqual(pairHigh.left, .rgb(0.92, 0.28, 0.38))
        XCTAssertEqual(pairHigh.right, .rgb(0.96, 0.58, 0.22))
        XCTAssertNotEqual(pairLow.left, pairHigh.left)
        XCTAssertNotEqual(pairLow.right, pairHigh.right)
    }

    func testLegacyBandSwatchKeyStillDecodes() throws {
        let json = Data(#"""
        {"preset":"systemDefault","mode":"onBattery","bands":[{"throughPercent":10,"swatch":{"systemRed":{}}},{"throughPercent":20,"swatch":{"systemYellow":{}}},{"throughPercent":100,"swatch":{"menuBar":{}}}]}
        """#.utf8)
        let scheme = try JSONDecoder().decode(MenuBarTintScheme.self, from: json)
        XCTAssertEqual(scheme.bands[0].highRight, .systemRed)
        XCTAssertEqual(scheme.bands[0].highLeft, .systemRed)
        XCTAssertEqual(scheme.bands[0].blend, .constant)
        XCTAssertEqual(scheme.swatch(percent: 5, flowMode: .discharging), .systemRed)
    }

    func testSmoothAndNeonPresetsSlide() {
        XCTAssertEqual(MenuBarTintScheme.smoothLevel.bands.map(\.blend), [.slide, .slide, .slide])
        XCTAssertEqual(MenuBarTintScheme.neon.bands.map(\.blend), [.slide, .slide])
        XCTAssertEqual(MenuBarTintScheme.lava.bands.map(\.blend), [.gradient])
        XCTAssertEqual(MenuBarTintScheme.dawn.bands.map(\.blend), [.slideGradient, .slideGradient])
    }

    func testDefaultBlendVariantsKeepDefaultStops() {
        let percents = [10, 20, 100]
        XCTAssertEqual(MenuBarTintScheme.defaultSlide.bands.map(\.throughPercent), percents)
        XCTAssertEqual(MenuBarTintScheme.defaultGradient.bands.map(\.throughPercent), percents)
        XCTAssertEqual(MenuBarTintScheme.defaultSlideGradient.bands.map(\.throughPercent), percents)
        XCTAssertEqual(MenuBarTintScheme.defaultSlide.bands.map(\.blend), [.slide, .slide, .slide])
        XCTAssertEqual(MenuBarTintScheme.defaultGradient.bands.map(\.blend), [.gradient, .gradient, .gradient])
        XCTAssertEqual(
            MenuBarTintScheme.defaultSlideGradient.bands.map(\.blend),
            [.slideGradient, .slideGradient, .slideGradient]
        )
        let mid = MenuBarTintScheme.defaultSlide.fillSwatches(percent: 15, flowMode: .discharging)
        XCTAssertEqual(mid.left, mid.right)
        guard case .custom(let red, let green, let blue) = mid.right else {
            return XCTFail("expected mixed color between red and yellow")
        }
        XCTAssertGreaterThan(red, 0.4)
        XCTAssertGreaterThan(green, 0.2)
        XCTAssertLessThan(blue, 0.2)
        let gradient = MenuBarTintScheme.defaultGradient.fillSwatches(percent: 5, flowMode: .discharging)
        XCTAssertEqual(gradient.left, .systemRed)
        XCTAssertEqual(gradient.right, .systemYellow)
    }

    func testSlideTowardMenuBarUsesTemplateAtEndAndLabelColorInBetween() {
        let aqua = NSAppearance(named: .aqua)!
        let dark = NSAppearance(named: .darkAqua)!
        let full = MenuBarTintScheme.defaultSlide.fill(percent: 100, flowMode: .discharging, appearance: aqua)
        XCTAssertTrue(full.isTemplate)
        let low = MenuBarTintScheme.defaultSlide.fill(percent: 20, flowMode: .discharging, appearance: aqua)
        XCTAssertFalse(low.isTemplate)
        let midAqua = MenuBarTintScheme.defaultSlide.fill(percent: 60, flowMode: .discharging, appearance: aqua)
        let midDark = MenuBarTintScheme.defaultSlide.fill(percent: 60, flowMode: .discharging, appearance: dark)
        XCTAssertFalse(midAqua.isTemplate)
        XCTAssertFalse(midDark.isTemplate)
        let aquaRGB = midAqua.right.usingColorSpace(.sRGB)!
        let darkRGB = midDark.right.usingColorSpace(.sRGB)!
        // Dark menu-bar label is lighter than light menu-bar label, so the mid blend should differ.
        XCTAssertNotEqual(
            aquaRGB.redComponent + aquaRGB.greenComponent + aquaRGB.blueComponent,
            darkRGB.redComponent + darkRGB.greenComponent + darkRGB.blueComponent,
            accuracy: 0.05
        )
        // Must not collapse to opaque black (old bug: menuBar painted as .black).
        XCTAssertFalse(
            aquaRGB.redComponent < 0.05
                && aquaRGB.greenComponent < 0.05
                && aquaRGB.blueComponent < 0.05
        )
    }
}

final class RingColorTests: XCTestCase {
    func testLoadFillBands() {
        let theme = AppTheme.resolved(palette: .semantic, colorScheme: .dark)
        XCTAssertEqual(theme.loadFill(percent: 0), theme.charging)
        XCTAssertEqual(theme.loadFill(percent: 59.9), theme.charging)
        XCTAssertEqual(theme.loadFill(percent: 60), theme.lowBatteryYellow)
        XCTAssertEqual(theme.loadFill(percent: 74.9), theme.lowBatteryYellow)
        XCTAssertEqual(theme.loadFill(percent: 75), theme.discharging)
        XCTAssertEqual(theme.loadFill(percent: 89.9), theme.discharging)
        XCTAssertEqual(theme.loadFill(percent: 90), theme.lowBatteryRed)
        XCTAssertEqual(theme.loadFill(percent: 100), theme.lowBatteryRed)
    }

    func testBatteryLevelFillBands() {
        let theme = AppTheme.resolved(palette: .semantic, colorScheme: .dark)
        XCTAssertEqual(theme.batteryLevelFill(percent: 100), theme.charging)
        XCTAssertEqual(theme.batteryLevelFill(percent: 40), theme.charging)
        XCTAssertEqual(theme.batteryLevelFill(percent: 39.9), theme.lowBatteryYellow)
        XCTAssertEqual(theme.batteryLevelFill(percent: 25), theme.lowBatteryYellow)
        XCTAssertEqual(theme.batteryLevelFill(percent: 24.9), theme.discharging)
        XCTAssertEqual(theme.batteryLevelFill(percent: 10), theme.discharging)
        XCTAssertEqual(theme.batteryLevelFill(percent: 9.9), theme.lowBatteryRed)
        XCTAssertEqual(theme.batteryLevelFill(percent: 0), theme.lowBatteryRed)
    }

    func testValueTintSchemeBatteryLevelUsesRoundStops() {
        let scheme = ValueTintScheme.batteryLevel(
            red: .systemRed,
            orange: .systemOrange,
            yellow: .systemYellow,
            green: .systemGreen
        )
        XCTAssertEqual(scheme.sortedBands.map(\.throughPercent), [10, 25, 40, 100])
        XCTAssertEqual(scheme.fillSwatches(percent: 0).left, .systemRed)
        XCTAssertEqual(scheme.fillSwatches(percent: 10).left, .systemRed)
        XCTAssertEqual(scheme.fillSwatches(percent: 11).left, .systemOrange)
        XCTAssertEqual(scheme.fillSwatches(percent: 25).left, .systemOrange)
        XCTAssertEqual(scheme.fillSwatches(percent: 26).left, .systemYellow)
        XCTAssertEqual(scheme.fillSwatches(percent: 40).left, .systemYellow)
        XCTAssertEqual(scheme.fillSwatches(percent: 41).left, .systemGreen)
        XCTAssertEqual(scheme.fillSwatches(percent: 100).left, .systemGreen)
    }

    func testValueTintSchemeLoadLevelUsesRoundStops() {
        let scheme = ValueTintScheme.loadLevel(
            green: .systemGreen,
            yellow: .systemYellow,
            orange: .systemOrange,
            red: .systemRed
        )
        XCTAssertEqual(scheme.sortedBands.map(\.throughPercent), [60, 75, 90, 100])
        XCTAssertEqual(scheme.fillSwatches(percent: 0).left, .systemGreen)
        XCTAssertEqual(scheme.fillSwatches(percent: 60).left, .systemGreen)
        XCTAssertEqual(scheme.fillSwatches(percent: 61).left, .systemYellow)
        XCTAssertEqual(scheme.fillSwatches(percent: 75).left, .systemYellow)
        XCTAssertEqual(scheme.fillSwatches(percent: 76).left, .systemOrange)
        XCTAssertEqual(scheme.fillSwatches(percent: 90).left, .systemOrange)
        XCTAssertEqual(scheme.fillSwatches(percent: 91).left, .systemRed)
        XCTAssertEqual(scheme.fillSwatches(percent: 100).left, .systemRed)
    }

    func testRingTintEditingForksCustom() {
        var tint = RingTintSettings.preset(.semantic)
        XCTAssertEqual(tint.preset, .semantic)
        let first = tint.battery.sortedBands[0]
        tint = tint.replacing(.battery, with: tint.battery.replacingBand(id: first.id, throughPercent: 12))
        XCTAssertEqual(tint.preset, .custom)
        XCTAssertEqual(tint.battery.sortedBands[0].throughPercent, 12)
        XCTAssertEqual(tint.cpu.sortedBands.map(\.throughPercent), [60, 75, 90, 100])
    }

    func testTintSchemeMergeNilForMixedFields() {
        let shared = MenuBarTintBand(throughPercent: 50, swatch: .systemGreen)
        let top = MenuBarTintBand(throughPercent: 100, swatch: .systemYellow)
        let a = ValueTintScheme(bands: [shared, top])
        var otherLow = shared
        otherLow.highRight = .systemRed
        let b = ValueTintScheme(bands: [otherLow, top])
        let merged = TintSchemeMerge.bands(from: [a, b])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].throughPercent, 50)
        XCTAssertNil(merged[0].highRight)
        XCTAssertEqual(merged[1].throughPercent, 100)
        XCTAssertEqual(merged[1].highRight, .systemYellow)

        let c = ValueTintScheme(bands: [
            MenuBarTintBand(throughPercent: 40, swatch: .systemGreen),
            top
        ])
        let mixedStops = TintSchemeMerge.bands(from: [a, c])
        XCTAssertNil(mixedStops[0].throughPercent)
    }

    func testRingTintMapAllUpdatesFourRings() {
        var tint = RingTintSettings.preset(.system)
        tint = tint.mapAll { scheme in
            scheme.replacingBand(at: 0) { $0.throughPercent = 11 }
        }
        XCTAssertEqual(tint.preset, .custom)
        XCTAssertEqual(tint.battery.sortedBands[0].throughPercent, 11)
        XCTAssertEqual(tint.cpu.sortedBands[0].throughPercent, 11)
        XCTAssertEqual(tint.gpu.sortedBands[0].throughPercent, 11)
        XCTAssertEqual(tint.memory.sortedBands[0].throughPercent, 11)
    }

    func testFlowTintPresetSeedsFourModes() {
        let tint = FlowTintSettings.preset(.semantic)
        XCTAssertEqual(tint.preset, .semantic)
        XCTAssertNil(tint.motionColor)
        XCTAssertEqual(tint.charging.bands.count, 1)
        XCTAssertEqual(tint.discharging.bands.count, 1)
        XCTAssertEqual(tint.adapterHold.bands.count, 1)
        XCTAssertEqual(tint.underpowered.bands.count, 1)
        XCTAssertNotEqual(
            tint.scheme(for: .charging).fillSwatches(percent: 50).left,
            tint.scheme(for: .discharging).fillSwatches(percent: 50).left
        )
    }

    func testShowcasePresetsUseSlideAndGradientBlends() {
        let ringSmooth = RingTintSettings.preset(.smooth)
        XCTAssertEqual(ringSmooth.battery.bands.map(\.blend), [.slide, .slide, .slide, .slide])
        XCTAssertEqual(ringSmooth.cpu.bands.map(\.blend), [.slide, .slide, .slide, .slide])

        let ringGradient = RingTintSettings.preset(.gradient)
        XCTAssertEqual(ringGradient.battery.bands.map(\.blend), [.gradient])
        XCTAssertEqual(ringGradient.cpu.sortedBands[0].highLeft, .systemGreen)
        XCTAssertEqual(ringGradient.cpu.sortedBands[0].highRight, .systemRed)

        let ringGlide = RingTintSettings.preset(.glide)
        XCTAssertTrue(ringGlide.battery.bands.allSatisfy { $0.blend == .slideGradient })

        let flowGradient = FlowTintSettings.preset(.gradient)
        XCTAssertEqual(flowGradient.charging.bands.map(\.blend), [.gradient])
        let charging = flowGradient.charging.fillSwatches(percent: 50)
        XCTAssertNotEqual(charging.left, charging.right)

        let flowSmooth = FlowTintSettings.preset(.smooth)
        XCTAssertEqual(flowSmooth.discharging.bands.map(\.blend), [.slide])
        XCTAssertNotEqual(
            flowSmooth.discharging.fillSwatches(percent: 0).right,
            flowSmooth.discharging.fillSwatches(percent: 100).right
        )
    }

    func testLegacyPaletteMigratesIntoRingAndFlowTint() {
        let suite = "MacPower.RingFlowTintMigrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(ThemePalette.highContrast.rawValue, forKey: "palette")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.ringTint.preset, .highContrast)
        XCTAssertEqual(settings.flowTint.preset, .highContrast)
        XCTAssertEqual(settings.ringTint.battery.bands.count, 4)
        XCTAssertEqual(settings.flowTint.charging.bands.count, 1)
        defaults.removePersistentDomain(forName: suite)
    }

    func testSavingAndSelectingNamedTintPresets() {
        let suite = "MacPower.SavedTint.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        settings.applyRingTintPreset(.gradient)
        let id = settings.saveRingTintPreset(named: "  渐变备份  ")
        XCTAssertEqual(settings.savedTintLibrary.ring.count, 1)
        XCTAssertEqual(settings.savedTintLibrary.ring[0].name, "渐变备份")
        XCTAssertEqual(settings.ringActiveSavedID, id)

        settings.applyRingTintPreset(.semantic)
        XCTAssertNil(settings.ringActiveSavedID)
        settings.applySavedRingTint(id: id!)
        XCTAssertEqual(settings.ringActiveSavedID, id)
        XCTAssertEqual(settings.ringTint.battery.bands.map(\.blend), [.gradient])

        // Editing a saved custom keeps the active ID so Save can overwrite.
        settings.ringTint = settings.ringTint.mapAll { $0.addingBand() }
        XCTAssertEqual(settings.ringActiveSavedID, id)
        XCTAssertTrue(settings.updateRingTintPreset())
        XCTAssertEqual(settings.savedTintLibrary.ring.first(where: { $0.id == id })?.payload.battery.bands.count, 2)
        XCTAssertEqual(settings.ringActiveSavedID, id)
        XCTAssertEqual(settings.savedTintLibrary.ring.count, 1)

        settings.applySavedRingTint(id: id!)
        settings.deleteSavedRingTint(id: id!)
        XCTAssertTrue(settings.savedTintLibrary.ring.isEmpty)
        XCTAssertNil(settings.ringActiveSavedID)
        defaults.removePersistentDomain(forName: suite)
    }

    func testUpdateTintPresetRequiresActiveSavedID() {
        let suite = "MacPower.UpdateTint.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        settings.applyFlowTintPreset(.smooth)
        XCTAssertFalse(settings.updateFlowTintPreset())
        let id = settings.saveFlowTintPreset(named: "柔和")
        settings.flowTint = settings.flowTint.markedCustom()
        var tint = settings.flowTint
        tint.motionColor = .systemOrange
        settings.flowTint = tint
        XCTAssertTrue(settings.updateFlowTintPreset())
        XCTAssertEqual(settings.savedTintLibrary.flow.first?.payload.motionColor, .systemOrange)
        XCTAssertEqual(settings.flowActiveSavedID, id)
        defaults.removePersistentDomain(forName: suite)
    }

    func testSavingAndUpdatingNamedIconPresets() throws {
        let suite = "MacPower.SavedIcon.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        settings.applyRingIconPreset(.circles)
        let id = settings.saveRingIconPreset(named: "  圆环备份  ")
        XCTAssertEqual(settings.savedIconLibrary.ring.count, 1)
        XCTAssertEqual(settings.savedIconLibrary.ring[0].name, "圆环备份")
        XCTAssertEqual(settings.ringActiveSavedIconID, id)

        settings.applyRingIconPreset(.classic)
        XCTAssertNil(settings.ringActiveSavedIconID)
        settings.applySavedRingIcon(id: id!)
        XCTAssertEqual(settings.ringIcons.battery.name, "bolt.circle.fill")
        XCTAssertEqual(settings.ringActiveSavedIconID, id)

        settings.ringIcons = settings.ringIcons.withScale(1.4, for: .gpu)
        XCTAssertEqual(settings.ringActiveSavedIconID, id)
        XCTAssertTrue(settings.updateRingIconPreset())
        let savedGPU = try XCTUnwrap(settings.savedIconLibrary.ring.first(where: { $0.id == id })?.payload.gpu.scale)
        XCTAssertEqual(savedGPU, 1.4, accuracy: 0.001)

        let asNew = settings.saveRingIconPreset(named: "圆环备份2")
        XCTAssertEqual(settings.savedIconLibrary.ring.count, 2)
        XCTAssertEqual(settings.ringActiveSavedIconID, asNew)

        settings.applyFlowIconPreset(.bolt)
        let flowID = settings.saveFlowIconPreset(named: "闪电")
        settings.flowIcons = settings.flowIcons.withScale(0.8, for: .mac)
        XCTAssertTrue(settings.updateFlowIconPreset())
        let savedMac = try XCTUnwrap(settings.savedIconLibrary.flow.first(where: { $0.id == flowID })?.payload.mac.scale)
        XCTAssertEqual(savedMac, 0.8, accuracy: 0.001)

        settings.deleteSavedRingIcon(id: id!)
        settings.deleteSavedFlowIcon(id: flowID!)
        XCTAssertEqual(settings.savedIconLibrary.ring.count, 1)
        XCTAssertTrue(settings.savedIconLibrary.flow.isEmpty)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.savedIconLibrary.ring.count, 1)
        XCTAssertEqual(reloaded.savedIconLibrary.ring[0].name, "圆环备份2")
        defaults.removePersistentDomain(forName: suite)
    }

    func testRingAndFlowIconPresetsAndPersistence() {
        XCTAssertEqual(RingIconSettings.classic.gpu.source, .asset)
        XCTAssertEqual(RingIconSettings.classic.gpu.name, "GPUMark")
        XCTAssertEqual(RingIconSettings.classic.gpu.opticalScale, 0.86, accuracy: 0.001)
        XCTAssertEqual(RingIconSettings.classic.gpu.scale, 1.0, accuracy: 0.001)
        XCTAssertEqual(FlowIconSettings.classic.supply.name, "ChargeMark")
        XCTAssertEqual(FlowIconSettings.classic.supply.opticalScale, 0.9, accuracy: 0.001)
        XCTAssertEqual(
            FlowIconSettings.classic.slot(forBubbleID: "battery", charging: true).name,
            "battery.100percent.bolt"
        )

        let devices = RingIconSettings.preset(.devices)
        XCTAssertEqual(devices.preset, .devices)
        XCTAssertEqual(devices.battery.name, "macbook")

        let bolt = FlowIconSettings.preset(.bolt)
        XCTAssertEqual(bolt.supply.name, "bolt.fill")
        XCTAssertEqual(bolt.mac.name, "macbook")

        let suite = "MacPower.IconPack.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.ringIcons.gpu.scale, 1.0, accuracy: 0.001)
        settings.ringIcons = settings.ringIcons.withScale(1.35, for: .gpu)
        settings.flowIcons = settings.flowIcons.withScale(0.7, for: .supply)
        XCTAssertEqual(settings.ringIcons.gpu.scale, 1.35, accuracy: 0.001)
        XCTAssertEqual(settings.flowIcons.supply.scale, 0.7, accuracy: 0.001)
        XCTAssertEqual(settings.ringIcons.preset, .custom)
        XCTAssertEqual(settings.flowIcons.preset, .custom)

        settings.applyRingIconPreset(.circles)
        settings.applyFlowIconPreset(.plug)
        XCTAssertEqual(settings.ringIcons.preset, .circles)
        XCTAssertEqual(settings.flowIcons.preset, .plug)
        XCTAssertEqual(settings.ringIcons.gpu.scale, 1.0, accuracy: 0.001)
        XCTAssertEqual(settings.flowIcons.supply.scale, 1.0, accuracy: 0.001)

        settings.ringIcons = settings.ringIcons.withScale(1.35, for: .gpu)
        settings.flowIcons = settings.flowIcons.withScale(0.7, for: .supply)
        let custom = GlyphSlot.customFile("demo.png", template: true, scale: 1.2)
        settings.ringIcons = settings.ringIcons.replacing(.gpu, with: custom)
        XCTAssertEqual(settings.ringIcons.preset, .custom)
        XCTAssertEqual(settings.ringIcons.gpu, custom)
        XCTAssertEqual(settings.ringIcons.gpu.scale, 1.2, accuracy: 0.001)

        settings.flowIcons = settings.flowIcons.replacing(.battery, with: custom, syncCharging: true)
        XCTAssertEqual(settings.flowIcons.battery, custom)
        XCTAssertEqual(settings.flowIcons.batteryCharging, custom)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.ringIcons.preset, .custom)
        XCTAssertEqual(reloaded.ringIcons.gpu, custom)
        XCTAssertEqual(reloaded.ringIcons.gpu.scale, 1.2, accuracy: 0.001)
        XCTAssertEqual(reloaded.flowIcons.preset, .custom)
        XCTAssertEqual(reloaded.flowIcons.supply.name, "powerplug.fill")
        XCTAssertEqual(reloaded.flowIcons.supply.scale, 0.7, accuracy: 0.001)
        XCTAssertEqual(reloaded.flowIcons.battery, custom)
        defaults.removePersistentDomain(forName: suite)
    }

    func testLegacyPackScaleMigratesOntoGlyphSlots() throws {
        let json = """
        {
          "preset":"classic",
          "scale":1.5,
          "battery":{"source":"system","name":"laptopcomputer","template":true},
          "cpu":{"source":"system","name":"cpu.fill","template":true},
          "gpu":{"source":"asset","name":"GPUMark","template":true},
          "memory":{"source":"system","name":"memorychip.fill","template":true}
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RingIconSettings.self, from: json)
        XCTAssertEqual(decoded.battery.scale, 1.5, accuracy: 0.001)
        XCTAssertEqual(decoded.gpu.scale, 1.5, accuracy: 0.001)
    }

    func testCustomIconStoreSavesPNG() {
        let image = NSImage(size: NSSize(width: 64, height: 48))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        guard let id = CustomIconStore.save(image: image) else {
            return XCTFail("expected custom icon id")
        }
        defer { try? FileManager.default.removeItem(at: CustomIconStore.url(for: id)) }
        XCTAssertTrue(id.hasSuffix(".png"))
        XCTAssertNotNil(CustomIconStore.image(id: id))
        guard let png = CustomIconStore.pngData(from: image, maxSide: 32) else {
            return XCTFail("expected png data")
        }
        XCTAssertFalse(png.isEmpty)
    }
}

final class RibbonMorphTests: XCTestCase {
    func testDirectUnplugStartsChargingClose() {
        let decision = RibbonMorph.decide(
            from: nil,
            startedAt: nil,
            duration: 1.65,
            previous: stub(.charging),
            nextMode: .discharging,
            now: Date()
        )
        guard case .start(let from) = decision else {
            return XCTFail("expected a new close, got \(decision)")
        }
        XCTAssertEqual(from.flowMode, .charging)
    }

    func testUnplugHoldThenDischargeKeepsTheSameChargingClose() {
        let charging = stub(.charging)
        let startedAt = Date()
        let later = startedAt.addingTimeInterval(0.12)
        let decision = RibbonMorph.decide(
            from: charging,
            startedAt: startedAt,
            duration: 1.65,
            previous: stub(.adapterHold),
            nextMode: .discharging,
            now: later
        )
        XCTAssertEqual(decision, .keepGoing)
    }

    func testUnplugDischargeThenHoldKeepsTheSameChargingClose() {
        let charging = stub(.charging)
        let startedAt = Date()
        let decision = RibbonMorph.decide(
            from: charging,
            startedAt: startedAt,
            duration: 1.65,
            previous: stub(.discharging),
            nextMode: .adapterHold,
            now: startedAt.addingTimeInterval(0.4)
        )
        XCTAssertEqual(decision, .keepGoing)
    }

    func testPluginDuringUnplugReversesElapsedTime() {
        let startedAt = Date()
        let elapsed: TimeInterval = 0.55
        let decision = RibbonMorph.decide(
            from: stub(.charging),
            startedAt: startedAt,
            duration: 1.65,
            previous: stub(.discharging),
            nextMode: .charging,
            now: startedAt.addingTimeInterval(elapsed)
        )
        guard case .reverse(let from, let reversedElapsed) = decision else {
            return XCTFail("expected a reverse, got \(decision)")
        }
        XCTAssertEqual(from.flowMode, .discharging)
        XCTAssertEqual(reversedElapsed, elapsed, accuracy: 0.001)
    }

    func testFinishedMorphStartsFresh() {
        let startedAt = Date()
        let decision = RibbonMorph.decide(
            from: stub(.charging),
            startedAt: startedAt,
            duration: 1.65,
            previous: stub(.discharging),
            nextMode: .charging,
            now: startedAt.addingTimeInterval(2)
        )
        guard case .start(let from) = decision else {
            return XCTFail("expected a fresh morph, got \(decision)")
        }
        XCTAssertEqual(from.flowMode, .discharging)
    }

    private func stub(_ mode: EnergyFlowMode) -> PowerSnapshot {
        var snapshot = PowerSnapshot.empty
        snapshot.hasBattery = true
        snapshot.flowMode = mode
        snapshot.externalConnected = mode != .discharging
        snapshot.isCharging = mode == .charging
        return snapshot
    }
}
