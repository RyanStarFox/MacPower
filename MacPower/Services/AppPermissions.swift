import AppKit
import CoreBluetooth
import Foundation

/// Permissions MacPower may need, with status checks and links into System Settings.
enum AppPermissionKind: String, CaseIterable, Identifiable, Sendable {
    case bluetooth
    case lowPowerAdmin

    var id: String { rawValue }
}

enum AppPermissionStatus: Equatable, Sendable {
    case allowed
    case denied
    case restricted
    case notDetermined
    case unknown

    var localizationKey: String {
        switch self {
        case .allowed: "settings.permissions.status.allowed"
        case .denied: "settings.permissions.status.denied"
        case .restricted: "settings.permissions.status.restricted"
        case .notDetermined: "settings.permissions.status.notDetermined"
        case .unknown: "settings.permissions.status.unknown"
        }
    }
}

enum AppPermissions {
    static func status(for kind: AppPermissionKind) -> AppPermissionStatus {
        switch kind {
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: return .allowed
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined: return .notDetermined
            @unknown default: return .unknown
            }
        case .lowPowerAdmin:
            switch LowPowerModeController.adminAccess {
            case .macPowerRule, .systemSudo: return .allowed
            case .unavailable: return .notDetermined
            }
        }
    }

    /// Where Low Power Mode admin access comes from, when it is already allowed.
    static var lowPowerAdminAccess: LowPowerModeController.AdminAccess {
        LowPowerModeController.adminAccess
    }

    /// Whether live `IOBluetoothDevice` reads are allowed. Denied / restricted
    /// stay on `system_profiler` only so TCC does not abort the process.
    static var bluetoothDeviceReadsAllowed: Bool {
        switch status(for: .bluetooth) {
        case .allowed, .notDetermined: return true
        case .denied, .restricted, .unknown: return false
        }
    }

    static func openSystemSettings(for kind: AppPermissionKind) {
        switch kind {
        case .bluetooth:
            let candidates = [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Bluetooth",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth",
                "x-apple.systempreferences:com.apple.Settings.extension.PrivacySecurity?Privacy_Bluetooth",
            ]
            for raw in candidates {
                guard let url = URL(string: raw) else { continue }
                if NSWorkspace.shared.open(url) { return }
            }
        case .lowPowerAdmin:
            break
        }
    }

    /// Shows the system Bluetooth prompt when status is still undetermined.
    static func requestBluetoothAccess() async -> AppPermissionStatus {
        let current = status(for: .bluetooth)
        guard current == .notDetermined else { return current }
        return await BluetoothPermissionRequester.shared.request()
    }

    static func grantLowPowerAdmin() async -> AppPermissionStatus {
        _ = await LowPowerModeController.grantPasswordlessRule()
        return status(for: .lowPowerAdmin)
    }

    static func revokeLowPowerAdmin() async -> AppPermissionStatus {
        _ = await LowPowerModeController.revokePasswordlessRule()
        return status(for: .lowPowerAdmin)
    }
}

/// One shared probe so repeated taps do not create overlapping managers.
private final class BluetoothPermissionRequester: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    static let shared = BluetoothPermissionRequester()

    private let lock = NSLock()
    private var manager: CBCentralManager?
    private var waiting: [CheckedContinuation<AppPermissionStatus, Never>] = []

    func request() async -> AppPermissionStatus {
        let existing = AppPermissions.status(for: .bluetooth)
        guard existing == .notDetermined else { return existing }
        return await withCheckedContinuation { continuation in
            lock.lock()
            waiting.append(continuation)
            let needsManager = manager == nil
            if needsManager {
                manager = CBCentralManager(
                    delegate: self,
                    queue: nil,
                    options: [CBCentralManagerOptionShowPowerAlertKey: false]
                )
                lock.unlock()
            } else {
                lock.unlock()
                finish(with: AppPermissions.status(for: .bluetooth))
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        finish(with: AppPermissions.status(for: .bluetooth))
    }

    private func finish(with status: AppPermissionStatus) {
        lock.lock()
        let continuations = waiting
        waiting.removeAll()
        if status != .notDetermined {
            manager = nil
        }
        lock.unlock()
        for continuation in continuations {
            continuation.resume(returning: status)
        }
    }
}
