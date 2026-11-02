import Darwin
import Foundation
import Network
import SystemConfiguration

enum IPAddressScope: String, CaseIterable, Identifiable, Codable, Sendable {
    case local
    case publicAddress = "public"
    case loopback
    case linkLocal

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .local: "ip.scope.local"
        case .publicAddress: "ip.scope.public"
        case .loopback: "ip.scope.loopback"
        case .linkLocal: "ip.scope.linkLocal"
        }
    }
}

enum IPAddressFamily: String, CaseIterable, Identifiable, Codable, Sendable {
    case ipv4
    case ipv6

    var id: String { rawValue }

    var localizationKey: String { "ip.family.\(rawValue)" }
}

struct LocalIPInterfaceAddress: Equatable, Sendable {
    var interfaceName: String
    var address: String
}

struct IPAddressRow: Equatable, Identifiable, Sendable {
    var scope: IPAddressScope
    var family: IPAddressFamily
    var interfaceName: String?
    var address: String
    var failed: Bool

    var id: String {
        "\(scope.rawValue)|\(family.rawValue)|\(interfaceName ?? "")|\(address)|\(failed)"
    }
}

enum LocalIPFilter {
    struct Parsed: Equatable {
        var family: IPAddressFamily
        var interfaceScope: IPAddressScope?
        var display: String
        var bytes: [UInt8]
    }

    static func parse(_ raw: String) -> Parsed? {
        let display = stripZone(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !display.isEmpty else { return nil }
        if let bytes = ipv4Bytes(display) {
            return Parsed(family: .ipv4, interfaceScope: ipv4Scope(bytes), display: display, bytes: bytes)
        }
        if let bytes = ipv6Bytes(display) {
            if let mapped = ipv4Mapped(bytes) {
                return Parsed(family: .ipv4, interfaceScope: ipv4Scope(mapped), display: display, bytes: mapped)
            }
            return Parsed(family: .ipv6, interfaceScope: ipv6Scope(bytes), display: display, bytes: bytes)
        }
        return nil
    }

    static func rows(
        interfaces: [LocalIPInterfaceAddress],
        scopes: Set<IPAddressScope>,
        families: Set<IPAddressFamily>,
        publicIPv4: String? = nil,
        publicIPv6: String? = nil,
        publicIPv4Failed: Bool = false,
        publicIPv6Failed: Bool = false
    ) -> [IPAddressRow] {
        var rows: [IPAddressRow] = []
        var interfaceOrder: [String] = []
        var seen = Set<String>()
        let publicV6 = publicIPv6.flatMap(parse)

        for item in interfaces {
            guard let parsed = parse(item.address), let scope = parsed.interfaceScope else { continue }
            guard scopes.contains(scope), families.contains(parsed.family) else { continue }
            if parsed.family == .ipv6, scope == .local, let publicV6, parsed.bytes == publicV6.bytes {
                continue
            }
            if !interfaceOrder.contains(item.interfaceName) {
                interfaceOrder.append(item.interfaceName)
            }
            let key = "\(scope.rawValue)|\(parsed.family.rawValue)|\(item.interfaceName)|\(parsed.display)"
            guard seen.insert(key).inserted else { continue }
            rows.append(IPAddressRow(
                scope: scope,
                family: parsed.family,
                interfaceName: item.interfaceName,
                address: parsed.display,
                failed: false
            ))
        }

        appendPublic(
            &rows,
            family: .ipv4,
            address: publicIPv4,
            failed: publicIPv4Failed,
            scopes: scopes,
            families: families
        )
        appendPublic(
            &rows,
            family: .ipv6,
            address: publicIPv6,
            failed: publicIPv6Failed,
            scopes: scopes,
            families: families
        )

        return rows.sorted { lhs, rhs in
            let leftScope = scopeRank(lhs.scope)
            let rightScope = scopeRank(rhs.scope)
            if leftScope != rightScope { return leftScope < rightScope }
            let leftInterface = lhs.interfaceName.flatMap { interfaceOrder.firstIndex(of: $0) } ?? Int.max
            let rightInterface = rhs.interfaceName.flatMap { interfaceOrder.firstIndex(of: $0) } ?? Int.max
            if leftInterface != rightInterface { return leftInterface < rightInterface }
            if lhs.family != rhs.family { return lhs.family == .ipv4 }
            if lhs.failed != rhs.failed { return !lhs.failed }
            return lhs.address < rhs.address
        }
    }

    private static func appendPublic(
        _ rows: inout [IPAddressRow],
        family: IPAddressFamily,
        address: String?,
        failed: Bool,
        scopes: Set<IPAddressScope>,
        families: Set<IPAddressFamily>
    ) {
        guard scopes.contains(.publicAddress), families.contains(family) else { return }
        if let address, let parsed = parse(address), parsed.family == family {
            rows.append(IPAddressRow(
                scope: .publicAddress,
                family: family,
                interfaceName: nil,
                address: parsed.display,
                failed: false
            ))
            return
        }
        guard address == nil, failed else { return }
        rows.append(IPAddressRow(
            scope: .publicAddress,
            family: family,
            interfaceName: nil,
            address: "",
            failed: true
        ))
    }

    private static func scopeRank(_ scope: IPAddressScope) -> Int {
        switch scope {
        case .local: 0
        case .publicAddress: 1
        case .loopback: 2
        case .linkLocal: 3
        }
    }

    private static func stripZone(_ address: String) -> String {
        guard let percent = address.firstIndex(of: "%") else { return address }
        return String(address[..<percent])
    }

    private static func ipv4Bytes(_ address: String) -> [UInt8]? {
        var addr = in_addr()
        guard address.withCString({ inet_pton(AF_INET, $0, &addr) }) == 1 else { return nil }
        let value = addr.s_addr.bigEndian
        return [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value)
        ]
    }

    private static func ipv6Bytes(_ address: String) -> [UInt8]? {
        var addr = in6_addr()
        guard address.withCString({ inet_pton(AF_INET6, $0, &addr) }) == 1 else { return nil }
        return withUnsafeBytes(of: addr) { Array($0) }
    }

    private static func ipv4Mapped(_ bytes: [UInt8]) -> [UInt8]? {
        guard bytes.count == 16 else { return nil }
        let prefix = bytes.prefix(10).allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
        guard prefix else { return nil }
        return Array(bytes.suffix(4))
    }

    private static func ipv4Scope(_ bytes: [UInt8]) -> IPAddressScope? {
        guard bytes.count == 4 else { return nil }
        let first = bytes[0]
        let second = bytes[1]
        if first == 127 { return .loopback }
        if first == 169, second == 254 { return .linkLocal }
        if first == 10 { return .local }
        if first == 172, (16...31).contains(Int(second)) { return .local }
        if first == 192, second == 168 { return .local }
        return nil
    }

    private static func ipv6Scope(_ bytes: [UInt8]) -> IPAddressScope? {
        guard bytes.count == 16 else { return nil }
        if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes.last == 1 { return .loopback }
        if bytes.allSatisfy({ $0 == 0 }) { return nil }
        if bytes[0] == 0xfe, bytes[1] & 0xc0 == 0x80 { return .linkLocal }
        if bytes[0] == 0xff { return nil }
        if bytes[0] & 0xfe == 0xfc { return .local }
        if bytes[0] & 0xe0 == 0x20 { return .local }
        return nil
    }
}

enum LocalIPReader {
    static func interfaceAddresses() -> [LocalIPInterfaceAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return [] }
        defer { freeifaddrs(head) }
        let names = displayNames()
        var results: [LocalIPInterfaceAddress] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let current = cursor {
            let iface = current.pointee
            cursor = iface.ifa_next
            guard let sa = iface.ifa_addr else { continue }
            let family = sa.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            guard Int32(iface.ifa_flags) & IFF_UP != 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(sa.pointee.sa_len)
            guard getnameinfo(sa, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let raw = buffer.withUnsafeBufferPointer { bytes in
                bytes.baseAddress.map { String(cString: $0) } ?? ""
            }
            guard let parsed = LocalIPFilter.parse(raw) else { continue }
            let bsd = String(cString: iface.ifa_name)
            let display = names[bsd].flatMap { $0.isEmpty ? nil : $0 } ?? bsd
            results.append(LocalIPInterfaceAddress(interfaceName: display, address: parsed.display))
        }
        return results
    }

    private static func displayNames() -> [String: String] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var names: [String: String] = [:]
        for interface in interfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            guard let localized = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?, !localized.isEmpty else { continue }
            names[bsd] = localized
        }
        return names
    }
}

struct LocalIPSnapshot: Equatable, Sendable {
    var interfaces: [LocalIPInterfaceAddress] = []
    var publicIPv4: String?
    var publicIPv6: String?
    var publicIPv4Failed = false
    var publicIPv6Failed = false
}

/// Reads interface addresses when asked and watches `NWPathMonitor` only while the block is enabled.
/// Public addresses are fetched on popover open and on path changes, never on a timer.
final class LocalIPService: @unchecked Sendable {
    nonisolated init() {}

    @MainActor var onChange: ((LocalIPSnapshot) -> Void)?

    private var monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "app.macpower.local-ip")
    private var lastPathSignature: String?
    private var wantsPublic = false
    private var wantsIPv4 = false
    private var wantsIPv6 = false
    private var cachedIPv4: String?
    private var cachedIPv6: String?
    private var failedIPv4 = false
    private var failedIPv6 = false
    private var generation = 0
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private static let ipv4URL = URL(string: "https://api.ipify.org")!
    private static let ipv6URL = URL(string: "https://api6.ipify.org")!

    @MainActor
    func apply(
        enabled: Bool,
        scopes: Set<IPAddressScope>,
        families: Set<IPAddressFamily>,
        fetchPublic: Bool
    ) {
        wantsPublic = enabled && scopes.contains(.publicAddress)
        wantsIPv4 = families.contains(.ipv4)
        wantsIPv6 = families.contains(.ipv6)
        guard enabled else {
            stop()
            return
        }
        startMonitorIfNeeded()
        publish()
        guard fetchPublic, wantsPublic else { return }
        fetchPublicAddresses()
    }

    @MainActor
    private func stop() {
        generation += 1
        monitor?.cancel()
        monitor = nil
        lastPathSignature = nil
    }

    @MainActor
    private func startMonitorIfNeeded() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = Self.pathSignature(path)
            Task { @MainActor in
                self?.handlePath(signature)
            }
        }
        monitor.start(queue: monitorQueue)
        self.monitor = monitor
    }

    @MainActor
    private func handlePath(_ signature: String) {
        let changed = signature != lastPathSignature
        lastPathSignature = signature
        publish()
        guard changed, wantsPublic else { return }
        fetchPublicAddresses()
    }

    @MainActor
    private func fetchPublicAddresses() {
        generation += 1
        let token = generation
        if wantsIPv4 {
            fetch(url: Self.ipv4URL, family: .ipv4, token: token)
        }
        if wantsIPv6 {
            fetch(url: Self.ipv6URL, family: .ipv6, token: token)
        }
    }

    @MainActor
    private func fetch(url: URL, family: IPAddressFamily, token: Int) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.dataTask(with: request) { [weak self] data, _, error in
            let body = data.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let transportFailed = error != nil || body == nil
            Task { @MainActor in
                self?.complete(family: family, body: body, transportFailed: transportFailed, token: token)
            }
        }
        task.resume()
    }

    @MainActor
    private func complete(family: IPAddressFamily, body: String?, transportFailed: Bool, token: Int) {
        guard token == generation else { return }
        let parsed = body.flatMap { LocalIPFilter.parse($0) }
        let valid = parsed?.family == family ? parsed?.display : nil
        switch family {
        case .ipv4:
            if let valid {
                cachedIPv4 = valid
                failedIPv4 = false
            } else if cachedIPv4 == nil, transportFailed || body != nil {
                failedIPv4 = true
            }
        case .ipv6:
            if let valid {
                cachedIPv6 = valid
                failedIPv6 = false
            } else if cachedIPv6 == nil, transportFailed || body != nil {
                failedIPv6 = true
            }
        }
        publish()
    }

    @MainActor
    private func publish() {
        let snapshot = LocalIPSnapshot(
            interfaces: LocalIPReader.interfaceAddresses(),
            publicIPv4: cachedIPv4,
            publicIPv6: cachedIPv6,
            publicIPv4Failed: cachedIPv4 == nil && failedIPv4,
            publicIPv6Failed: cachedIPv6 == nil && failedIPv6
        )
        onChange?(snapshot)
    }

    private static func pathSignature(_ path: NWPath) -> String {
        let names = path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
        return "\(path.status)|\(names)"
    }
}
