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
        func render(_ percent: Double, style: MenuBarIconStyle = .outlineFill, charging: Bool = false, fill: MenuBarResolvedFill = .template) -> NSBitmapImageRep {
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
        for style in [MenuBarIconStyle.systemFill, .systemPercentInside, .classicBeside] {
            for charging in [false, true] {
                let keepsTerminalDim = [99.0, 99.5, 100].allSatisfy { percent in
                    let bitmap = render(percent, style: style, charging: charging)
                    return abs(color(bitmap, bitmap.size.width - 1.75, 8).alphaComponent - 0.62) < 0.01
                }
                check(keepsTerminalDim, "\(style), charging=\(charging): the terminal stays dim near and at full charge")
            }
        }
        let borderlessCharge = render(0, style: .systemFill, charging: true)
        let boltTip = (12..<16).flatMap { x in (28..<31).map { y in color(borderlessCharge, CGFloat(x), CGFloat(y) / 2).alphaComponent } }
        check(boltTip.contains(where: { $0 > 0.1 }), "The 2.1.1 borderless bolt still extends beyond the battery body")

        let digits = render(0, style: .outlinePercentInside)
        let digitAlphas = (5..<19).flatMap { x in (5..<11).map { y in color(digits, CGFloat(x), CGFloat(y)).alphaComponent } }
        check(digitAlphas.contains(where: { $0 > 0.9 }), "Inside digits remain visible without a gray backing")
        let borderlessDigits = render(0, style: .systemPercentInside)
        let borderlessDigitAlphas = (8..<16).flatMap { x in (5..<11).map { y in color(borderlessDigits, CGFloat(x), CGFloat(y)).alphaComponent } }
        check(borderlessDigitAlphas.contains(where: { $0 < 0.01 }) && borderlessDigitAlphas.contains(where: { abs($0 - 0.52) < 0.01 }), "Borderless digits retain the original knockout over a visible backing")

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
        struct Ink { var width: Int; var height: Int; var widestRow: Int; var area: CGFloat; var first: Int; var last: Int }
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
                    last: j
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
        check(digitArea > 145 && digitArea < 168, "Borderless inside digits match the system's stroke weight")

        let chargingRuns = inkRuns(render(94, style: .systemPercentInside, charging: true))
        let tallBolt = inkRuns(render(94, style: .systemPercentInside, charging: true), threshold: 0.12).last
        if let bolt = chargingRuns.last, chargingRuns.count == 3, let tallBolt {
            print("  inside bolt: \(bolt.width)x\(bolt.height) (\(tallBolt.height) at 0.12), widest row \(bolt.widestRow), area \(Int(bolt.area)), gap \(bolt.first - chargingRuns[1].last - 1)")
            check(bolt.width >= 10 && bolt.height >= 14 && tallBolt.height >= 16, "The inside bolt matches the system's 10 x 16px ink")
            check(bolt.area > 44 && bolt.area < 58, "The inside bolt matches the system's ink area")
            check(bolt.widestRow >= 8, "The inside bolt has the system's wide middle bar")
            let gap = bolt.first - chargingRuns[1].last - 1
            check(gap >= 1 && gap <= 3, "The inside bolt sits as close to the digits as the system's")
        } else {
            check(false, "The inside bolt separates from the digits")
        }
        let fullCharging = render(100, style: .systemPercentInside, charging: true)
        let inkColumns = (1..<49).filter { px in
            (8..<24).contains { py in fullCharging.colorAt(x: px, y: py)!.alphaComponent < 0.5 }
        }
        print("  100% charging ink columns: \(inkColumns.first ?? -1)-\(inkColumns.last ?? -1) in a 1-48px body")
        check(inkColumns.count > 20 && inkColumns.first! >= 1 + 3 && inkColumns.last! <= 48 - 3, "Three digits and the bolt still fit inside the 24pt body")

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
        let outlinedStart = topEdgeStart(render(0), from: 0, threshold: 0.5 * 0.97)
        // The outline PDF's corner crosses its diagonal like a 3.35pt circular arc.
        let outlinedCircularStart = topEdgeStart(circular(NSRect(x: 0, y: 2, width: 23, height: 12), radius: 3.35), from: 0)
        print("  outlined top edge starts: circular \(outlinedCircularStart), frame \(outlinedStart)")
        check(outlinedStart >= outlinedCircularStart + 0.75 && outlinedStart <= outlinedCircularStart + 1.5, "The outlined frame keeps a similar corner size")
        let source = try String(contentsOfFile: "MacPower/Views/MenuBarBatteryIcon.swift", encoding: .utf8)
        check(!source.contains("roundedRect:") && !source.contains("\"MenuBarBatteryOutline\""), "Battery bodies use the shared continuous corner path instead of circular arcs or the PDF frame")

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
