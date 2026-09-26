#if DEBUG
import AppKit
import SwiftUI

/// One-shot README shots. Launch with `--readme-gallery`, then the process quits.
@MainActor
enum ReadmeAssetCapture {
    private struct Shot {
        var name: String
        var mode: EnergyFlowMode
        var motion: EnergyMotionStyle
        var tint: PopoverTintPreset
    }

    /// Soft frosted panel for README embeds — lets the page theme show through.
    private static let panelFill = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 0.58)
    private static let panelCornerPoints: CGFloat = 18

    static func startIfNeeded() -> Bool {
        guard CommandLine.arguments.contains("--readme-gallery") else { return false }
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .aqua)
        ProcessInfo.processInfo.disableAutomaticTermination("readme-gallery")
        Task { await exportAll() }
        return true
    }

    private static func exportAll() async {
        let output = outputDirectory()
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let anchor = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 4, height: 4),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        anchor.isOpaque = true
        anchor.backgroundColor = .windowBackgroundColor
        anchor.level = .floating
        anchor.hasShadow = false
        anchor.orderFrontRegardless()

        let state = AppState()
        state.telemetry.stop()
        state.metricsService.stop()
        state.telemetry.onChange = nil
        state.metricsService.onChange = nil
        state.settings.language = .simplifiedChinese
        state.settings.pulseFlowIcons = false
        state.settings.showStatusRings = true
        state.settings.showEnergyFlow = true
        state.settings.showPopoverArrow = false
        state.metrics = SystemSnapshot(cpuPercent: 19, gpuPercent: 31, memoryPercent: 67)
        state.isPopoverOpen = true

        let hosting = NSHostingController(
            rootView: PopoverRootView(appState: state)
                .environment(\.colorScheme, .light)
                .environment(\.readmeGalleryCapture, true)
        )
        // Match the live menu extra: intrinsic sizing alone clips the 420pt
        // panel, which cuts off the right-aligned time estimate.
        hosting.sizingOptions = []
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = hosting
        if popover.responds(to: NSSelectorFromString("setShouldHideAnchor:")) {
            popover.setValue(true, forKey: "shouldHideAnchor")
        }

        // Six gallery shots: each pairs a flow shape with a distinct tint/motion
        // so color and animation show up without a separate axis of images.
        let shots: [Shot] = [
            .init(name: "flow-discharging", mode: .discharging, motion: .particles, tint: .semantic),
            .init(name: "flow-adapter-hold", mode: .adapterHold, motion: .particlesWhite, tint: .gradient),
            .init(name: "flow-underpowered", mode: .underpowered, motion: .filaments, tint: .highContrast),
            .init(name: "flow-charging", mode: .charging, motion: .sheen, tint: .glide),
            .init(name: "flow-discharging-smooth", mode: .discharging, motion: .filamentsSolid, tint: .smooth),
            .init(name: "flow-charging-off", mode: .charging, motion: .off, tint: .semantic)
        ]

        for shot in shots {
            state.settings.motionStyle = shot.motion
            state.settings.applyRingTintPreset(shot.tint)
            state.settings.applyFlowTintPreset(shot.tint)
            state.snapshot = .readme(shot.mode)
            // Open tall enough to lay out, then lock to the measured height.
            // Measuring before show clips the supply / charger footer.
            popover.contentSize = NSSize(width: PopoverLayout.width, height: 640)
            popover.show(
                relativeTo: anchor.contentView!.bounds,
                of: anchor.contentView!,
                preferredEdge: .maxY
            )
            // Give Liquid Glass / TimelineView time to settle before bitmap capture.
            for _ in 0..<4 {
                try? await Task.sleep(for: .milliseconds(400))
                hosting.view.layoutSubtreeIfNeeded()
                hosting.view.window?.layoutIfNeeded()
                hosting.view.window?.displayIfNeeded()
            }
            let fitted = hosting.sizeThatFits(
                in: NSSize(width: PopoverLayout.width, height: CGFloat.greatestFiniteMagnitude)
            )
            let height = max(ceil(fitted.height), 1)
            popover.contentSize = NSSize(width: PopoverLayout.width, height: height)
            hosting.view.frame.size = NSSize(width: PopoverLayout.width, height: height)
            hosting.view.layoutSubtreeIfNeeded()
            hosting.view.window?.layoutIfNeeded()
            hosting.view.window?.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(250))
            let dest = output.appendingPathComponent("\(shot.name).png")
            if captureView(hosting.view, to: dest) {
                flattenAndTrim(at: dest)
                print("wrote \(dest.lastPathComponent)")
            } else {
                print("failed \(shot.name)")
            }
        }

        state.isPopoverOpen = false
        popover.close()
        anchor.close()
        NSApp.terminate(nil)
    }

    private static func outputDirectory() -> URL {
        if let flag = CommandLine.arguments.first(where: { $0.hasPrefix("--readme-output=") }) {
            return URL(fileURLWithPath: String(flag.dropFirst("--readme-output=".count)), isDirectory: true)
        }
        return URL(fileURLWithPath: "/Users/wangshaoyan/Code/MacPower/docs/readme", isDirectory: true)
    }

    @discardableResult
    private static func captureView(_ view: NSView, to url: URL) -> Bool {
        let size = view.bounds.size
        guard size.width > 1, size.height > 1 else { return false }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        // Clear canvas — empty glass holes stay transparent; polish step adds a
        // frosted rounded panel behind the real content.
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            NSColor.clear.setFill()
            NSBezierPath.fill(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func flattenAndTrim(at url: URL) {
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff),
              let cg = source.cgImage else { return }
        let width = source.pixelsWide
        let height = source.pixelsHigh
        let scale = max(1.0, CGFloat(width) / max(image.size.width, 1))
        let radius = panelCornerPoints * scale

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        for y in 0..<height {
            for x in 0..<width {
                guard let color = source.colorAt(x: x, y: y) else { continue }
                let a = color.alphaComponent
                let lum = color.redComponent * 0.3 + color.greenComponent * 0.59 + color.blueComponent * 0.11
                // Secondary labels rasterize as black at ~50% alpha. A luminance
                // floor drops them, which cropped off the supply / charger footer.
                if a > 0.22 || (a > 0.08 && lum > 0.04) {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        let pad = Int((12 * scale).rounded())
        minX = max(0, minX - pad)
        minY = max(0, minY - pad)
        maxX = min(width - 1, maxX + pad)
        maxY = min(height - 1, maxY + pad)
        let cropW = maxX - minX + 1
        let cropH = maxY - minY + 1
        guard cropW > 8, cropH > 8,
              let cropped = cg.cropping(to: CGRect(x: minX, y: minY, width: cropW, height: cropH))
        else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: cropW,
            height: cropH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        let rect = CGRect(x: 0, y: 0, width: cropW, height: cropH)
        let panel = CGPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        // Soften opaque popover chrome before compositing.
        guard let softened = softenChrome(cropped) else { return }

        ctx.clear(rect)
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.58)
        ctx.addPath(panel)
        ctx.fillPath()
        ctx.draw(softened, in: rect)
        ctx.setBlendMode(.destinationIn)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.addPath(panel)
        ctx.fillPath()

        guard let polished = ctx.makeImage() else { return }
        let out = NSBitmapImageRep(cgImage: polished)
        if let png = out.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    /// Turn near-white chrome into translucent frost so GitHub themes show through.
    private static func softenChrome(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = ctx.data else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let frost: UInt8 = 148 // ~0.58 * 255 premul white
        for i in 0..<(width * height) {
            let o = i * 4
            let r = Int(ptr[o])
            let g = Int(ptr[o + 1])
            let b = Int(ptr[o + 2])
            let a = Int(ptr[o + 3])
            if a < 20 {
                ptr[o] = 0; ptr[o + 1] = 0; ptr[o + 2] = 0; ptr[o + 3] = 0
                continue
            }
            let lum = (r * 30 + g * 59 + b * 11) / 100
            if lum > 235 && r > 230 && g > 230 && b > 230 {
                ptr[o] = frost
                ptr[o + 1] = frost
                ptr[o + 2] = frost
                ptr[o + 3] = frost
            }
        }
        return ctx.makeImage()
    }
}

private extension PowerSnapshot {
    static func readme(_ mode: EnergyFlowMode) -> PowerSnapshot {
        switch mode {
        case .discharging:
            PowerSnapshot(
                hasBattery: true,
                percent: 95,
                isCharging: false,
                externalConnected: false,
                fullyCharged: false,
                adapterCeilingWatts: 0,
                adapterInWatts: 0,
                systemLoadWatts: 23.8,
                batteryWatts: -23.8,
                remainingCapacityWh: 70,
                missingCapacityWh: 4,
                systemTimeToEmptyMinutes: 156,
                systemTimeToFullMinutes: nil,
                timeToEmptyMinutes: 156,
                timeToFullMinutes: nil,
                flowMode: .discharging
            )
        case .adapterHold:
            PowerSnapshot(
                hasBattery: true,
                percent: 100,
                isCharging: false,
                externalConnected: true,
                fullyCharged: true,
                adapterCeilingWatts: 30,
                adapterInWatts: 12.4,
                systemLoadWatts: 12.4,
                batteryWatts: 0,
                remainingCapacityWh: 74,
                missingCapacityWh: 0,
                systemTimeToEmptyMinutes: nil,
                systemTimeToFullMinutes: nil,
                timeToEmptyMinutes: nil,
                timeToFullMinutes: nil,
                flowMode: .adapterHold
            )
        case .underpowered:
            PowerSnapshot(
                hasBattery: true,
                percent: 64,
                isCharging: false,
                externalConnected: true,
                fullyCharged: false,
                adapterCeilingWatts: 30,
                adapterInWatts: 18.0,
                systemLoadWatts: 28.5,
                batteryWatts: -10.5,
                remainingCapacityWh: 48,
                missingCapacityWh: 26,
                systemTimeToEmptyMinutes: 210,
                systemTimeToFullMinutes: nil,
                timeToEmptyMinutes: 210,
                timeToFullMinutes: nil,
                flowMode: .underpowered
            )
        case .charging:
            PowerSnapshot(
                hasBattery: true,
                percent: 42,
                isCharging: true,
                externalConnected: true,
                fullyCharged: false,
                adapterCeilingWatts: 70,
                adapterInWatts: 48.0,
                systemLoadWatts: 22.0,
                batteryWatts: 26.0,
                remainingCapacityWh: 31,
                missingCapacityWh: 43,
                systemTimeToEmptyMinutes: nil,
                systemTimeToFullMinutes: 95,
                timeToEmptyMinutes: nil,
                timeToFullMinutes: 95,
                flowMode: .charging
            )
        }
    }
}
#endif
