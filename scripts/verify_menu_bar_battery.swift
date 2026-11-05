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
