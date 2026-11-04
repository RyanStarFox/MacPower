import AppKit
import Foundation

enum BluetoothBatteryReader {
    static func load() -> [BluetoothSeenDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return parse(data)
    }

    static func parse(_ data: Data) -> [BluetoothSeenDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = root["SPBluetoothDataType"] as? [[String: Any]],
              let group = groups.first
        else { return [] }
        var devices: [BluetoothSeenDevice] = []
        devices.append(contentsOf: readDevices(in: group["device_connected"], connected: true))
        devices.append(contentsOf: readDevices(in: group["device_not_connected"], connected: false))
        var seen = Set<String>()
        return devices.filter { seen.insert($0.address).inserted }
    }

    private static func readDevices(in value: Any?, connected: Bool) -> [BluetoothSeenDevice] {
        guard let entries = value as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let (name, info) = entry.first, let info = info as? [String: Any] else { return nil }
            let address = (info["device_address"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !address.isEmpty else { return nil }
            return BluetoothSeenDevice(
                address: address,
                name: name,
                connected: connected,
                levels: levels(in: info),
                productID: text(info["device_productID"]),
                minorType: text(info["device_minorType"]),
                vendorID: text(info["device_vendorID"])
            )
        }
    }

    private static func levels(in info: [String: Any]) -> [BluetoothBatteryPart: Int] {
        var levels: [BluetoothBatteryPart: Int] = [:]
        func store(_ part: BluetoothBatteryPart, _ key: String) {
            guard let percent = percent(info[key]) else { return }
            levels[part] = percent
        }
        store(.single, "device_batteryLevel")
        store(.left, "device_batteryLevelLeft")
        store(.right, "device_batteryLevelRight")
        store(.box, "device_batteryLevelCase")
        if levels[.single] == nil, levels.isEmpty == false {
            return levels
        }
        return levels
    }

    private static func text(_ value: Any?) -> String? {
        if let raw = value as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? Int { return String(number) }
        if let number = value as? Double { return String(Int(number)) }
        return nil
    }

    private static func percent(_ value: Any?) -> Int? {
        let text: String
        if let number = value as? Int { return min(100, max(0, number)) }
        if let number = value as? Double { return min(100, max(0, Int(number.rounded()))) }
        if let raw = value as? String { text = raw } else { return nil }
        let digits = text.prefix { $0.isNumber || $0 == "-" }
        guard let number = Int(digits) else { return nil }
        return min(100, max(0, number))
    }
}

enum HeadphoneSymbols {
    static func glyph(model: HeadphoneModel, part: BluetoothBatteryPart) -> GlyphSlot {
        slot(firstExisting(model.symbolCandidates(part: part)))
    }

    static func glyph(model: HeadphoneModel, parts: [BluetoothBatteryPart]) -> GlyphSlot {
        slot(firstExisting(model.symbolCandidates(parts: parts)))
    }

    static func choices(model: HeadphoneModel) -> [GlyphSlot] {
        let modelNames = Set(
            [model.symbolName(parts: [.single, .left])]
                + [BluetoothBatteryPart.left, .right, .box, .single].map { model.symbolName(part: $0) }
        )
        var seen = Set<String>()
        return model.choiceNames().compactMap { name in
            let resolved: String
            if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                resolved = name
            } else if modelNames.contains(name) {
                resolved = firstExisting([name])
            } else {
                return nil
            }
            guard seen.insert(resolved).inserted else { return nil }
            return slot(resolved)
        }
    }

    private static func slot(_ name: String) -> GlyphSlot {
        if name.hasPrefix(systemImagePrefix) {
            return GlyphSlot(source: .system, name: resolved(name), template: false, scale: 1, opticalScale: 1)
        }
        return .system(resolved(name))
    }

    static let systemImagePrefix = "system-bluetooth:"

    static func systemImageToken(_ file: String) -> String {
        systemImagePrefix + file
    }

    static func systemImage(named file: String) -> NSImage? {
        guard !file.isEmpty, !file.contains("/"), !file.contains("..") else { return nil }
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/CoreBluetoothUI.framework/Resources", isDirectory: true)
            .appendingPathComponent(file)
        return NSImage(contentsOf: url)
    }

    /// First candidate that exists on this Mac. A missing specific drawing falls back to a generic radio symbol, then headphones.
    private static func firstExisting(_ names: [String]) -> String {
        for name in names {
            if name.hasPrefix(systemImagePrefix) {
                let file = String(name.dropFirst(systemImagePrefix.count))
                if systemImage(named: file) != nil { return name }
                continue
            }
            if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil { return name }
        }
        if NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: nil) != nil {
            return "dot.radiowaves.left.and.right"
        }
        return "headphones"
    }

    /// System SF Symbols, or a Bluetooth product image shipped with macOS. A missing name falls back to the generic headphones symbol.
    private static func resolved(_ name: String) -> String {
        if name.hasPrefix(systemImagePrefix) {
            let file = String(name.dropFirst(systemImagePrefix.count))
            if systemImage(named: file) != nil { return name }
            return resolved("airpods.gen4")
        }
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil { return name }
        if name != "headphones", NSImage(systemSymbolName: "headphones", accessibilityDescription: nil) != nil {
            return "headphones"
        }
        return name
    }
}
