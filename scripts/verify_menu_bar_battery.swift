// Run from the repository root:
// swiftc -module-cache-path /private/tmp/macpower-swift-cache MacPower/Models/{EnergyFlowMode,SystemSnapshot,PowerSnapshot,MenuBarIconStyle}.swift MacPower/Views/MenuBarBatteryIcon.swift scripts/verify_menu_bar_battery.swift -o /private/tmp/verify-menu-bar-battery
// /private/tmp/verify-menu-bar-battery
import AppKit

@main
enum VerifyMenuBarBattery {
    static func main() throws {
        // Register the same resources that the app loads from its asset catalog.
        for name in ["ChargeMark", "MenuBarBatteryOutline", "MenuBarBatteryCap", "MenuBarBatteryBolt", "MenuBarBatteryBoltMask"] {
            let directory = "MacPower/Assets.xcassets/\(name).imageset"
            let file = name == "ChargeMark" ? "ChargeMark.png" : "\(name).pdf"
            NSImage(contentsOfFile: "\(directory)/\(file)")?.setName(NSImage.Name(name))
        }

        let appearance = NSAppearance(named: .darkAqua)!
        func render(_ percent: Double, style: MenuBarIconStyle = .outlineFill, charging: Bool = false, fill: MenuBarResolvedFill = .template, appearance: NSAppearance = appearance) -> NSBitmapImageRep {
            var snapshot = PowerSnapshot.empty
            snapshot.percent = percent
            snapshot.flowMode = charging ? .charging : .discharging
            let image = MenuBarBatteryRenderer.image(snapshot: snapshot, style: style, fill: fill, appearance: appearance, showChargeGlyphs: charging)
            return image.representations.first as! NSBitmapImageRep
        }

        func color(_ bitmap: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> NSColor {
            let px = min(bitmap.pixelsWide - 1, Int(x * CGFloat(bitmap.pixelsWide) / bitmap.size.width))
            let py = min(bitmap.pixelsHigh - 1, Int(y * CGFloat(bitmap.pixelsHigh) / bitmap.size.height))
            return bitmap.colorAt(x: px, y: bitmap.pixelsHigh - 1 - py)!.usingColorSpace(.sRGB)!
        }

        var failures = [String]()
        func check(_ condition: Bool, _ message: String) {
            print("\(condition ? "PASS" : "FAIL") \(message)")
            if !condition { failures.append(message) }
        }

        let empty = render(0)
        let half = render(50)
        let full = render(100)
        check(color(empty, 18, 8).alphaComponent < 0.01, "An empty outlined battery has a transparent interior")
        check(color(half, 5, 8).alphaComponent > 0.99 && color(half, 18, 8).alphaComponent < 0.01, "Charge fills only the used fraction")
        check(color(full, 12, 3.5).alphaComponent < 0.01, "A transparent gutter separates the fill from the border at 100%")
        check(abs(color(empty, 12, 2.25).alphaComponent - 0.5) < 0.05, "The native outline retains its half-opacity stroke")
        check(color(full, 23.5, 8).alphaComponent < 0.01, "The terminal stays detached from the frame")
        check(abs(color(full, 24.25, 8).alphaComponent - 0.6) < 0.05, "The native terminal retains its opacity")
        check(color(render(0, charging: true), 11, 8).alphaComponent > 0.9, "The outlined charging bolt remains visible over an empty battery")

        for style in [MenuBarIconStyle.systemFill, .classicBeside] {
            check(abs(color(render(0, style: style), 18, 8).alphaComponent - 0.52) < 0.01, "\(style): an empty battery keeps a slightly dimmer, visible backing")
            let half = render(50, style: style)
            check(color(half, 5, 8).alphaComponent > 0.99 && abs(color(half, 18, 8).alphaComponent - 0.52) < 0.01, "\(style): spent charge remains visible without changing charged fill")
        }
        for style in [MenuBarIconStyle.systemFill, .classicBeside] {
            for charging in [false, true] {
                let keepsTerminalDim = [99.0, 99.5, 100].allSatisfy { percent in
                    let bitmap = render(percent, style: style, charging: charging)
                    return abs(color(bitmap, bitmap.size.width - 1.75, 8).alphaComponent - 0.62) < 0.01
                }
                check(keepsTerminalDim, "\(style), charging=\(charging): the terminal stays dim near and at full charge")
            }
        }
        for charging in [false, true] {
            let keepsTerminalDim = [99.0, 99.5, 100].allSatisfy { percent in
                let bitmap = render(percent, style: .systemPercentInside, charging: charging)
                return abs(color(bitmap, bitmap.size.width - 1.75, 8).alphaComponent - 0.60) < 0.01
            }
            check(keepsTerminalDim, "systemPercentInside, charging=\(charging): the terminal stays at the measured opacity near and at full charge")
        }
        let insideEmpty = render(0, style: .systemPercentInside)
        check(abs(color(insideEmpty, 2, 8).alphaComponent - 0.50) < 0.01, "systemPercentInside: an empty battery keeps the measured 0.50 backing")
        let borderlessCharge = render(0, style: .systemFill, charging: true)
        let boltTip = (12..<16).flatMap { x in (28..<31).map { y in color(borderlessCharge, CGFloat(x), CGFloat(y) / 2).alphaComponent } }
        check(boltTip.contains(where: { $0 > 0.1 }), "The 2.1.1 borderless bolt still extends beyond the battery body")

        let digits = render(0, style: .outlinePercentInside)
        let digitAlphas = (5..<19).flatMap { x in (5..<11).map { y in color(digits, CGFloat(x), CGFloat(y)).alphaComponent } }
        check(digitAlphas.contains(where: { $0 > 0.9 }), "Inside digits remain visible without a gray backing")
        let borderlessDigits = render(0, style: .systemPercentInside)
        let borderlessDigitAlphas = (8..<16).flatMap { x in (5..<11).map { y in color(borderlessDigits, CGFloat(x), CGFloat(y)).alphaComponent } }
        let retained = 0.50 * 0.105
        check(borderlessDigitAlphas.contains(where: { abs($0 - retained) < 0.03 }) && borderlessDigitAlphas.contains(where: { abs($0 - 0.50) < 0.01 }) && !borderlessDigitAlphas.contains(where: { $0 < 0.01 }), "Borderless digits keep about 10.5% of the backing and stay antialiased")

        let lowPowerYellow = MenuBarTintScheme.systemDefault.fill(percent: 65, flowMode: .discharging, appearance: appearance, lowPowerMode: true)
        let lowPowerRed = MenuBarTintScheme.systemDefault.fill(percent: 10, flowMode: .discharging, appearance: appearance, lowPowerMode: true)
        let lowPowerAtEleven = MenuBarTintScheme.systemDefault.fill(percent: 11, flowMode: .discharging, appearance: appearance, lowPowerMode: true)
        let lowPowerCharging = MenuBarTintScheme.systemDefault.fill(percent: 65, flowMode: .charging, appearance: appearance, lowPowerMode: true)
        let lowPowerOff = MenuBarTintScheme.systemDefault.fill(percent: 65, flowMode: .discharging, appearance: appearance, lowPowerMode: false)
        let tintDisabled = MenuBarTintScheme.off.fill(percent: 65, flowMode: .discharging, appearance: appearance, lowPowerMode: true)
        let expectedYellow = MenuBarTintSwatch.systemYellow.paintNSColor(appearance: appearance)
        let expectedRed = MenuBarTintSwatch.systemRed.paintNSColor(appearance: appearance)
        check(!lowPowerYellow.isTemplate && lowPowerYellow.left == expectedYellow, "Low Power Mode makes the charged portion yellow")
        check(!lowPowerRed.isTemplate && lowPowerRed.left == expectedRed, "Low Power Mode keeps 10% charge red")
        check(lowPowerAtEleven.left == expectedYellow, "Low Power Mode makes 11% charge yellow")
        check(!lowPowerCharging.isTemplate && lowPowerCharging.left == expectedYellow, "Low Power Mode stays yellow while charging")
        check(lowPowerOff.isTemplate, "Without Low Power Mode normal tint rules still apply")
        check(tintDisabled.isTemplate, "Disabling icon colors remains effective in Low Power Mode")
        let customThreshold = MenuBarTintScheme(preset: .custom, mode: .onBattery, bands: [
            MenuBarTintBand(throughPercent: 30, swatch: .systemRed),
            MenuBarTintBand(throughPercent: 100, swatch: .menuBar)
        ])
        let customRed = customThreshold.fill(percent: 25, flowMode: .discharging, appearance: appearance, lowPowerMode: true)
        let customRedCharging = customThreshold.fill(percent: 25, flowMode: .charging, appearance: appearance, lowPowerMode: true)
        let customYellow = customThreshold.fill(percent: 31, flowMode: .discharging, appearance: appearance, lowPowerMode: true)
        check(customRed.left == expectedRed, "Low Power Mode honors a custom 30% red threshold")
        check(customRedCharging.left == expectedRed, "Custom red thresholds also apply while charging in Low Power Mode")
        check(customYellow.left == expectedYellow, "Low Power Mode uses yellow above a custom red range")
        let customBlue = MenuBarTintScheme(preset: .custom, mode: .always, bands: [MenuBarTintBand(throughPercent: 100, swatch: .rgb(0.1, 0.3, 0.8))])
        let configured = customBlue.fill(percent: 5, flowMode: .discharging, appearance: appearance, lowPowerMode: true)
        check(configured.left == MenuBarTintSwatch.rgb(0.1, 0.3, 0.8).paintNSColor(appearance: appearance), "Low Power Mode preserves explicitly configured colors")

        let yellow = MenuBarResolvedFill(left: .systemYellow, right: .systemYellow, isTemplate: false)
        let yellowOutlined = render(50, fill: yellow)
        let yellowBorderless = render(50, style: .systemFill, fill: yellow)
        let outlinedCharge = color(yellowOutlined, 5, 8)
        let outlinedFrame = color(yellowOutlined, 12, 2.25)
        let borderlessEmpty = color(yellowBorderless, 18, 8)
        let borderlessCap = color(yellowBorderless, 25, 8)
        func isNeutral(_ c: NSColor) -> Bool {
            abs(c.redComponent - c.greenComponent) < 0.05 && abs(c.greenComponent - c.blueComponent) < 0.05
        }
        check(outlinedCharge.redComponent > outlinedCharge.blueComponent + 0.3, "Colored charge is yellow")
        check(isNeutral(outlinedFrame), "Colored outlined battery keeps a neutral frame")
        check(isNeutral(color(yellowOutlined, 24.25, 8)), "Colored outlined battery keeps a neutral terminal")
        check(isNeutral(borderlessEmpty), "Colored borderless battery keeps a neutral empty region")
        check(isNeutral(borderlessCap), "Colored borderless battery keeps a neutral terminal")
        check(isNeutral(color(render(50, charging: true, fill: yellow), 11, 8)), "Colored outlined battery keeps a neutral charging bolt")
        let lightFrame = color(render(50, fill: yellow, appearance: NSAppearance(named: .aqua)!), 12, 2.25)
        check(isNeutral(lightFrame) && lightFrame.redComponent < 0.2, "Colored frame adapts to light appearance")
        check(outlinedFrame.redComponent > 0.8, "Colored frame adapts to dark appearance")

        let gradient = render(100, fill: MenuBarResolvedFill(left: .red, right: .blue, isTemplate: false))
        check(color(gradient, 4, 7).redComponent > color(gradient, 4, 7).blueComponent && color(gradient, 20, 7).blueComponent > color(gradient, 20, 7).redComponent, "Custom gradients still flow from left to right")

        // Knockout coverage inside the borderless body, in 2x pixels, relative to each column's backing.
        func knockout(_ bitmap: NSBitmapImageRep) -> (coverage: [[CGFloat]], columns: Range<Int>, rows: Range<Int>) {
            let columns = 5..<(bitmap.pixelsWide - 12)
            let rows = 6..<26
            let coverage = rows.map { py in
                columns.map { px -> CGFloat in
                    let base = (5...26).map { bitmap.colorAt(x: px, y: $0)!.alphaComponent }.max()!
                    guard base > 0.3 else { return 0 }
                    return max(0, 1 - bitmap.colorAt(x: px, y: py)!.alphaComponent / base)
                }
            }
            return (coverage, columns, rows)
        }
        struct Ink { var width: Int; var height: Int; var widestRow: Int; var area: CGFloat; var first: Int; var last: Int; var rowInk: [CGFloat] }
        func inkRuns(_ bitmap: NSBitmapImageRep, threshold: CGFloat = 0.4) -> [Ink] {
            let (coverage, columns, _) = knockout(bitmap)
            let marked = (0..<columns.count).map { i in coverage.contains { $0[i] > threshold } }
            var runs = [Ink]()
            var i = 0
            while i < marked.count {
                guard marked[i] else { i += 1; continue }
                var j = i
                while j + 1 < marked.count, marked[j + 1] { j += 1 }
                let inkRows = coverage.filter { row in row[i...j].contains { $0 > threshold } }
                runs.append(Ink(
                    width: j - i + 1,
                    height: inkRows.count,
                    widestRow: coverage.map { $0[i...j].filter { $0 > threshold }.count }.max()!,
                    area: coverage.reduce(0) { $0 + $1[i...j].reduce(0, +) },
                    first: i,
                    last: j,
                    rowInk: coverage.map { $0[i...j].reduce(0, +) }.filter { $0 > threshold }
                ))
                i = j + 1
            }
            return runs
        }

        // Targets measured from the 2x screenshot of the macOS battery at 94% charging.
        let insideDigits = inkRuns(render(94, style: .systemPercentInside))
        let digitArea = insideDigits.reduce(0) { $0 + $1.area }
        print("  inside digits:", insideDigits.map { "\($0.width)x\($0.height)" }, "area", Int(digitArea))
        check(insideDigits.count == 2 && insideDigits.allSatisfy { $0.height >= 15 } && insideDigits.allSatisfy { $0.width >= 11 }, "Borderless inside digits match the system's 15px ink height and 11px glyph width")
        check(digitArea > 145 * 0.895 && digitArea < 168 * 0.895, "Borderless inside digits match the system's stroke weight")

        let chargingRuns = inkRuns(render(94, style: .systemPercentInside, charging: true))
        let tallBolt = inkRuns(render(94, style: .systemPercentInside, charging: true), threshold: 0.12).last
        if let bolt = chargingRuns.last, chargingRuns.count == 3, let tallBolt {
            print("  inside bolt: \(bolt.width)x\(bolt.height) (\(tallBolt.height) at 0.12), widest row \(bolt.widestRow), area \(Int(bolt.area)), gap \(bolt.first - chargingRuns[1].last - 1)")
            check(bolt.width >= 9 && bolt.height >= 14 && tallBolt.height >= 16, "The inside bolt keeps a 9px core and the system's 16px tips")
            check(bolt.area > 44 * 0.895 && bolt.area < 58 * 0.895, "The inside bolt matches the system's ink area")
            check(bolt.widestRow >= 8, "The inside bolt has the system's wide middle bar")
            let gap = bolt.first - chargingRuns[1].last - 1
            check(gap >= 1 && gap <= 3, "The inside bolt sits as close to the digits as the system's")
        } else {
            check(false, "The inside bolt separates from the digits")
        }
        // Targets measured from a 2x screenshot of the macOS battery at 100%, not charging.
        let threeIdle = inkRuns(render(100, style: .systemPercentInside))
        print("  100% runs:", threeIdle.map { "\($0.first)-\($0.last) \($0.width)x\($0.height) area \(Int($0.area))" })
        if threeIdle.count == 3 {
            check(threeIdle.allSatisfy { $0.height == 15 } && threeIdle[0].width == 6 && threeIdle.dropFirst().allSatisfy { $0.width == 11 }, "Three idle inside digits match the system's 15px height and 6px / 11px widths")
            let gaps = [threeIdle[1].first - threeIdle[0].last - 1, threeIdle[2].first - threeIdle[1].last - 1]
            check((3...4).contains(gaps[0]) && gaps[1] == 2, "Three idle inside digits keep the system's 3px and 2px spacing")
            check(threeIdle.dropFirst().allSatisfy { $0.area > 72 * 0.895 && $0.area < 84 * 0.895 }, "Three idle inside digits match the system's stroke weight")
        } else {
            check(false, "Three idle inside digits render as separate glyphs")
        }

        // Targets measured from a 2x menu-bar screenshot of the macOS battery at 100% charging,
        // where the system shrinks the digits to fit the bolt.
        let threeDigits = inkRuns(render(100, style: .systemPercentInside, charging: true))
        print("  100% charging runs:", threeDigits.map { "\($0.first)-\($0.last) \($0.width)x\($0.height) area \(Int($0.area))" })
        if threeDigits.count == 4 {
            let digitsOnly = threeDigits.prefix(3)
            check(digitsOnly.allSatisfy { $0.height == 13 } && digitsOnly.dropFirst().allSatisfy { $0.width >= 9 && $0.width <= 10 }, "Three inside digits match the system's 13px height and 9-10px zeros")
            check(threeDigits[1].first - threeDigits[0].last - 1 == 3 && threeDigits[2].first - threeDigits[1].last - 1 == 2, "Three inside digits keep the system's 3px and 2px spacing")
            let bolt = threeDigits[3]
            let stems = bolt.rowInk.prefix(3) + bolt.rowInk.suffix(3)
            print("  100% bolt rows:", bolt.rowInk.map { String(format: "%.1f", $0) })
            check(bolt.height == 12 && bolt.width >= 6 && bolt.width <= 9, "The three-digit bolt keeps the system's 12px height and a 6-9px core")
            check(bolt.area > 29 * 0.895 && bolt.area < 38 * 0.895, "The three-digit bolt matches the system's ink area")
            check(stems.allSatisfy { $0 < 2.4 * 0.895 } && bolt.rowInk.filter { $0 > 4 * 0.895 }.count == 2, "The three-digit bolt has the system's thin stems and two-pixel middle bar")
            let gap = bolt.first - threeDigits[2].last - 1
            check(gap >= 2 && gap <= 3, "The three-digit bolt sits as close to the digits as the system's")
        } else {
            check(false, "Three inside digits and the bolt render as separate glyphs")
        }

        let fullCharging = render(100, style: .systemPercentInside, charging: true)
        let inkColumns = (1..<46).filter { px in
            let samples = (8..<24).map { fullCharging.colorAt(x: px, y: $0)!.alphaComponent }
            return samples.contains { $0 < 0.2 } && samples.contains { $0 > 0.85 }
        }
        print("  100% charging ink columns: \(inkColumns.first ?? -1)-\(inkColumns.last ?? -1) in a 1-46px body")
        check(inkColumns.count > 20 && inkColumns.first! >= 1 + 3 && inkColumns.last! <= 46 - 3, "Three digits and the bolt still fit inside the 23pt body")

        // Continuous corners reach the solid straight edge later than a circular arc of the same radius.
        func topEdgeStart(_ bitmap: NSBitmapImageRep, from originX: CGFloat, threshold: CGFloat = 0.97) -> CGFloat {
            let row = 4
            let px = (0..<bitmap.pixelsWide / 2).first { bitmap.colorAt(x: $0, y: row)!.alphaComponent > threshold }!
            return CGFloat(px) / 2 - originX
        }
        func circular(_ rect: NSRect, radius: CGFloat) -> NSBitmapImageRep {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 60, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = NSSize(width: 30, height: 16)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        let circularStart = topEdgeStart(circular(NSRect(x: 0.35, y: 2, width: 23, height: 12), radius: 3.8), from: 0.35)
        let continuousStart = topEdgeStart(render(0, style: .systemFill), from: 0.35, threshold: 0.52 * 0.97)
        print("  top edge starts: circular \(circularStart), body \(continuousStart)")
        check(continuousStart >= circularStart + 0.5 && continuousStart <= circularStart + 1.5, "The borderless body uses continuous corners of a similar size")
        let insideCircular = topEdgeStart(circular(NSRect(x: 0.35, y: 2, width: 23, height: 12), radius: 4.04), from: 0.35)
        let insideStart = topEdgeStart(render(0, style: .systemPercentInside), from: 0.35, threshold: 0.50 * 0.97)
        print("  percent-inside top edge starts: circular \(insideCircular), body \(insideStart)")
        check(abs(insideStart - insideCircular) <= 0.35, "The percent-inside body uses a 4.04pt circular corner")
        let outlinedStart = topEdgeStart(render(0), from: 0, threshold: 0.5 * 0.97)
        // The outline PDF's corner crosses its diagonal like a 3.35pt circular arc.
        let outlinedCircularStart = topEdgeStart(circular(NSRect(x: 0, y: 2, width: 23, height: 12), radius: 3.35), from: 0)
        print("  outlined top edge starts: circular \(outlinedCircularStart), frame \(outlinedStart)")
        check(outlinedStart >= outlinedCircularStart + 0.75 && outlinedStart <= outlinedCircularStart + 1.5, "The outlined frame keeps a similar corner size")
        let source = try String(contentsOfFile: "MacPower/Views/MenuBarBatteryIcon.swift", encoding: .utf8)
        check(!source.contains("\"MenuBarBatteryOutline\""), "Battery frames stay drawn in code instead of the PDF outline")
        check(source.contains("continuousRoundedRect"), "Outlined and other borderless bodies keep continuous corners")
        check(source.contains("xRadius: 4.04"), "Only the percent-inside body opts into a circular corner")

        try FileManager.default.createDirectory(atPath: "build/icon-validation", withIntermediateDirectories: true)
        for (name, bitmap) in [("empty", empty), ("half", half), ("full", full), ("level-65", render(65)), ("charging", render(65, charging: true)), ("digits", digits), ("gradient", gradient), ("borderless-half", render(50, style: .systemFill)), ("borderless-charging", render(65, style: .systemFill, charging: true)), ("borderless-digits", borderlessDigits)] {
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/icon-validation/\(name).png"))
        }
        if !failures.isEmpty {
            fputs("\(failures.count) battery rendering checks failed\n", stderr)
            exit(1)
        }
    }
}
