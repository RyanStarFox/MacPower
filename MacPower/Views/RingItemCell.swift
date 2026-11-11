import AppKit
import SwiftUI

/// One cell of the panel's ring grid, drawn from live readings. The panel and
/// the settings preview both use it, so the preview always matches the panel.
struct RingItemCell: View {
    @Bindable var appState: AppState
    var item: RingItem

    var body: some View {
        if let slot = item.slot {
            ringCell(slot)
        } else {
            bluetoothRing(item)
        }
    }

    @ViewBuilder
    private func bluetoothRing(_ item: RingItem) -> some View {
        let language = appState.settings.language
        let devices = appState.settings.bluetoothRingDevices
        let ring = RingBoard.resolve(item, devices: devices)
        let reading = appState.bluetoothDevices.first { $0.address == item.address }
        let face = ring.flatMap {
            RingBoard.face(ring: $0, connected: reading?.connected == true, levels: reading?.levels ?? [:])
        }
        if let ring, let face {
            let device = devices.first { $0.address == item.address }
            let model = device?.model ?? .generic
            let name = device?.name ?? item.address ?? ""
            let captions = bluetoothCaptions(face: face, language: language)
            let title = ([name] + captions).joined(separator: " ")
            let scheme = appState.settings.ringTint.scheme(for: .battery)
            if face.parts.count == 2, let left = face.parts.first, let right = face.parts.last {
                let leftPercent = Double(face.levels[left] ?? 0)
                let rightPercent = Double(face.levels[right] ?? 0)
                PairRingView(
                    leftProgress: face.isPlaceholder ? 0 : leftPercent / 100,
                    rightProgress: face.isPlaceholder ? 0 : rightPercent / 100,
                    leftColor: ring.sideColors[left]?.color ?? scheme.colors(percent: leftPercent).left,
                    rightColor: ring.sideColors[right]?.color ?? scheme.colors(percent: rightPercent).left,
                    leftGlyph: ring.shownGlyph(model: model, part: left),
                    rightGlyph: ring.shownGlyph(model: model, part: right),
                    leftCaption: bluetoothCaption(part: left, face: face, language: language),
                    rightCaption: bluetoothCaption(part: right, face: face, language: language),
                    accessibilityValue: title
                )
            } else if face.parts.count <= 1 {
                let percent = face.parts.first.flatMap { face.levels[$0] }
                let shown = Double(percent ?? 0)
                let colors = scheme.colors(percent: shown)
                StatusRingView(
                    percent: shown,
                    fillLeft: colors.left,
                    fillRight: colors.right,
                    caption: face.isPlaceholder ? "—" : "\(percent ?? 0)%",
                    accessibilityName: title,
                    glyph: ring.shownGlyph(model: model, parts: face.parts),
                    glyphTint: ring.iconColor?.color
                )
            } else {
                MeterRingView(
                    segments: meterSegments(face: face, scheme: scheme),
                    glyph: ring.shownGlyph(model: model, parts: ring.parts),
                    glyphTint: ring.iconColor?.color,
                    accessibilityValue: title
                )
            }
        }
    }

    /// Index 0 is 60° (right ear), 1 is 180° (case), 2 is 300° (left ear).
    private func meterSegments(face: BluetoothRingFace, scheme: ValueTintScheme) -> [MeterRingView.MeterSegment] {
        let language = appState.settings.language
        var placed: [BluetoothBatteryPart?] = [nil, nil, nil]
        var rest: [BluetoothBatteryPart] = []
        for part in face.parts {
            switch part {
            case .right: placed[0] = part
            case .box: placed[1] = part
            case .left: placed[2] = part
            default: rest.append(part)
            }
        }
        for part in rest {
            if let index = placed.firstIndex(where: { $0 == nil }) {
                placed[index] = part
            }
        }
        return placed.compactMap { part in
            guard let part else { return nil }
            let percent = Double(face.levels[part] ?? 0)
            return MeterRingView.MeterSegment(
                progress: face.isPlaceholder ? 0 : percent / 100,
                color: scheme.colors(percent: percent).left,
                caption: bluetoothCaption(part: part, face: face, language: language)
            )
        }
    }

    private func bluetoothCaptions(face: BluetoothRingFace, language: AppLanguage) -> [String] {
        if face.isPlaceholder { return ["—"] }
        if face.parts.count <= 1 { return ["\(face.parts.first.flatMap { face.levels[$0] } ?? 0)%"] }
        return face.parts.map { bluetoothCaption(part: $0, face: face, language: language) }
    }

    private func bluetoothCaption(part: BluetoothBatteryPart, face: BluetoothRingFace, language: AppLanguage) -> String {
        if face.isPlaceholder { return "—" }
        let name = Localization.string(part.shortLocalizationKey, language: language)
        return "\(name) \(face.levels[part] ?? 0)%"
    }

    @ViewBuilder
    private func ringCell(_ slot: RingSlot) -> some View {
        switch slot {
        case .download:
            speedRing(
                segment: .download,
                bytesPerSecond: appState.metrics.downloadBytesPerSecond,
                glyph: appState.settings.ringIcons.slot(for: .download),
                nameKey: "settings.rings.download"
            )
        case .upload:
            speedRing(
                segment: .upload,
                bytesPerSecond: appState.metrics.uploadBytesPerSecond,
                glyph: appState.settings.ringIcons.slot(for: .upload),
                nameKey: "settings.rings.upload"
            )
        case .speedPair:
            speedPairRing
        case .batteryTemperature:
            temperatureRing
        case .thermalState:
            thermalRing
        default:
            if let kind = slot.metric {
                metricRing(kind)
            }
        }
    }

    private var temperatureRing: some View {
        let language = appState.settings.language
        let celsius = appState.snapshot.batteryTemperatureCelsius
        let percent = celsius.map {
            BatteryTemperatureFormat.ringPercent(
                celsius: $0,
                centerCelsius: Double(appState.settings.temperatureHalfCelsius)
            )
        } ?? 0
        let colors = appState.settings.ringTint.scheme(forSegment: .batteryTemperature).colors(percent: percent)
        let unit = appState.settings.temperatureUnit
        let value = celsius.map { BatteryTemperatureFormat.caption(celsius: $0, unit: unit) } ?? "—"
        let caption = Localization.string("ring.caption.batteryTemperature %@", language: language, value)
        let name = Localization.string("settings.rings.batteryTemperature", language: language)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: caption,
            accessibilityName: name,
            glyph: appState.settings.ringIcons.slot(for: .batteryTemperature),
            glyphTint: appState.settings.slotIconColors[RingSlot.batteryTemperature.rawValue]?.color,
            accessibilityValue: "\(name) \(caption)"
        )
    }

    private var thermalRing: some View {
        let language = appState.settings.language
        let level = appState.snapshot.thermalState
        let percent = level?.ringPercent(
            nominal: appState.settings.thermalNominalPercent,
            fair: appState.settings.thermalFairPercent,
            serious: appState.settings.thermalSeriousPercent,
            critical: appState.settings.thermalCriticalPercent
        ) ?? 0
        let colors = appState.settings.ringTint.scheme(forSegment: .thermalState).colors(percent: percent)
        let caption = level.map { Localization.string($0.captionKey, language: language) } ?? "—"
        let name = Localization.string("settings.rings.thermalState", language: language)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: caption,
            accessibilityName: name,
            glyph: appState.settings.ringIcons.slot(for: .thermalState),
            glyphTint: appState.settings.slotIconColors[RingSlot.thermalState.rawValue]?.color,
            accessibilityValue: "\(name) \(caption)"
        )
    }

    private func metricRing(_ kind: RingKind) -> some View {
        let language = appState.settings.language
        let percent = percent(for: kind)
        let colors = appState.settings.ringTint.scheme(for: kind).colors(percent: percent)
        let name = Localization.string(kind.localizationKey, language: language)
        let caption = metricCaption(kind, percent: percent, language: language)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: caption,
            accessibilityName: name,
            glyph: appState.settings.ringIcons.slot(for: kind),
            accessibilityValue: kind == .swap || kind == .compressor ? "\(name) \(caption)" : nil
        )
    }

    private func networkPercent(bytesPerSecond: Double, segment: RingColorSegment) -> Double {
        let kilobytes = segment == .upload
            ? appState.settings.uploadHalfKilobytes
            : appState.settings.downloadHalfKilobytes
        return NetworkRateFormat.ringPercent(
            bytesPerSecond: bytesPerSecond,
            centerBytesPerSecond: Double(kilobytes) * 1024
        )
    }

    private func speedRing(
        segment: RingColorSegment,
        bytesPerSecond: Double,
        glyph: GlyphSlot,
        nameKey: String
    ) -> some View {
        let language = appState.settings.language
        let percent = networkPercent(bytesPerSecond: bytesPerSecond, segment: segment)
        let colors = appState.settings.ringTint.scheme(forSegment: segment).colors(percent: percent)
        let rate = NetworkRateFormat.string(bytesPerSecond: bytesPerSecond)
        let name = Localization.string(nameKey, language: language)
        return StatusRingView(
            percent: percent,
            fillLeft: colors.left,
            fillRight: colors.right,
            caption: rate,
            accessibilityName: name,
            glyph: glyph,
            glyphTint: colors.left,
            accessibilityValue: "\(name) \(rate)"
        )
    }

    private var speedPairRing: some View {
        let language = appState.settings.language
        let downBytes = appState.metrics.downloadBytesPerSecond
        let upBytes = appState.metrics.uploadBytesPerSecond
        let down = NetworkRateFormat.string(bytesPerSecond: downBytes)
        let up = NetworkRateFormat.string(bytesPerSecond: upBytes)
        let name = Localization.string("settings.rings.speedPair", language: language)
        let downloadPercent = networkPercent(bytesPerSecond: downBytes, segment: .download)
        let uploadPercent = networkPercent(bytesPerSecond: upBytes, segment: .upload)
        let downloadColor = appState.settings.ringTint.scheme(forSegment: .download)
            .colors(percent: downloadPercent).left
        let uploadColor = appState.settings.ringTint.scheme(forSegment: .upload)
            .colors(percent: uploadPercent).left
        return SpeedPairRingView(
            downloadProgress: downloadPercent / 100,
            uploadProgress: uploadPercent / 100,
            downloadCaption: down,
            uploadCaption: up,
            accessibilityValue: "\(name) ↓ \(down) ↑ \(up)",
            downloadColor: downloadColor,
            uploadColor: uploadColor
        )
    }

    private func metricCaption(_ kind: RingKind, percent: Double, language: AppLanguage) -> String {
        switch kind {
        case .swap:
            return Localization.string(
                kind.captionKey,
                language: language,
                SwapUsageFormat.string(bytes: appState.metrics.swapUsedBytes)
            )
        case .compressor:
            return Localization.string(
                kind.captionKey,
                language: language,
                SwapUsageFormat.string(bytes: appState.metrics.compressorUsedBytes)
            )
        default:
            return Localization.string(kind.captionKey, language: language, Int64(percent.rounded()))
        }
    }

    private func percent(for kind: RingKind) -> Double {
        switch kind {
        case .battery: appState.snapshot.percent
        case .cpu: appState.metrics.cpuPercent
        case .gpu: appState.metrics.gpuPercent
        case .memory: appState.metrics.memoryPercent
        case .disk: appState.metrics.diskPercent
        case .memoryPressure: appState.metrics.memoryPressurePercent
        case .swap:
            SwapUsageFormat.ringPercent(
                usedBytes: appState.metrics.swapUsedBytes,
                halfBytes: Double(appState.settings.swapHalfMegabytes) * 1_048_576,
                memoryBytes: SwapUsageFormat.physicalMemoryBytes()
            )
        case .compressor:
            SwapUsageFormat.ringPercent(
                usedBytes: appState.metrics.compressorUsedBytes,
                halfBytes: Double(appState.settings.compressorHalfMegabytes) * 1_048_576,
                memoryBytes: SwapUsageFormat.physicalMemoryBytes()
            )
        }
    }
}
