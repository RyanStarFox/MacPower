import Darwin
import Foundation
import Security

enum LowPowerModeController {
    static func read() -> LowPowerPreset? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "custom"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return LowPowerPreset.parse(pmsetOutput: text)
    }

    static func arguments(for preset: LowPowerPreset) -> [String] {
        ["-b", "lowpowermode", preset.battery ? "1" : "0", "-c", "lowpowermode", preset.ac ? "1" : "0"]
    }

    static func arguments(activeOn: Bool, externalConnected: Bool) -> [String] {
        [externalConnected ? "-c" : "-b", "lowpowermode", activeOn ? "1" : "0"]
    }

    static func command(for preset: LowPowerPreset) -> String {
        (["pmset"] + arguments(for: preset)).joined(separator: " ")
    }

    /// Changes only the power source that is active now, leaving the other source's setting in place.
    static func command(activeOn: Bool, externalConnected: Bool) -> String {
        (["pmset"] + arguments(activeOn: activeOn, externalConnected: externalConnected)).joined(separator: " ")
    }

    /// True when a saved strategy should be written again because the cable was just plugged or unplugged.
    static func shouldReapplyStrategy(previousExternal: Bool?, external: Bool, hasStrategy: Bool) -> Bool {
        guard hasStrategy, let previousExternal, previousExternal != external else { return false }
        return true
    }

    /// macOS only lets System Settings change this without a password. `pmset` asks an administrator.
    /// One authorization is kept for the process, so later changes reuse it until that credential expires.
    static func apply(_ preset: LowPowerPreset) async -> Bool {
        await run(arguments(for: preset))
    }

    static func applyActive(on: Bool, externalConnected: Bool) async -> Bool {
        await run(arguments(activeOn: on, externalConnected: externalConnected))
    }

    private static func run(_ arguments: [String]) async -> Bool {
        await Task.detached {
            runSync(arguments)
        }.value
    }

    /// True when the limited MacPower `pmset` sudoers rule is installed.
    static var hasPasswordlessRule: Bool {
        FileManager.default.isReadableFile(atPath: LowPowerPrivilege.sudoersPath)
    }

    /// How Low Power Mode can already run without an interactive password prompt.
    /// A machine with broader passwordless `sudo` (not our file) still counts as ready.
    enum AdminAccess: Equatable, Sendable {
        /// `/etc/sudoers.d/macpower-lowpower` is present.
        case macPowerRule
        /// `sudo -n pmset` already works (for example a NOPASSWD admin account).
        case systemSudo
        case unavailable
    }

    static var adminAccess: AdminAccess {
        if hasPasswordlessRule { return .macPowerRule }
        if canRunPmsetWithoutPassword { return .systemSudo }
        return .unavailable
    }

    /// `sudo -n` can invoke `pmset` without asking for a password.
    static var canRunPmsetWithoutPassword: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "/usr/bin/pmset", "-g", "custom"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        return process.terminationStatus == 0
    }

    /// Asks for an administrator password and installs the limited sudoers rule
    /// used for Low Power Mode changes. Returns whether the rule is present afterward.
    static func grantPasswordlessRule() async -> Bool {
        await Task.detached {
            _ = installPasswordlessRule()
            return hasPasswordlessRule
        }.value
    }

    /// Asks for an administrator password and removes the MacPower low-power sudoers rule.
    /// Broader system sudo (NOPASSWD elsewhere) is left alone.
    static func revokePasswordlessRule() async -> Bool {
        await Task.detached {
            guard hasPasswordlessRule else { return true }
            _ = removePasswordlessRule()
            return !hasPasswordlessRule
        }.value
    }

    /// Asks for an administrator password at most once, then keeps a sudoers rule that
    /// allows only these exact `pmset` low-power commands.
    private static func runSync(_ arguments: [String]) -> Bool {
        let first = sudo(arguments)
        if first.ok { return true }
        guard first.needsPrivilege, installPasswordlessRule() else { return false }
        return sudo(arguments).ok
    }

    private static func removePasswordlessRule() -> Bool {
        authorize(tool: "/bin/rm", arguments: ["-f", LowPowerPrivilege.sudoersPath])
    }

    private static func sudo(_ arguments: [String]) -> (ok: Bool, needsPrivilege: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "/usr/bin/pmset"] + arguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, true)
        }
        if process.terminationStatus == 0 { return (true, false) }
        let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let needsPrivilege = text.contains("password") || text.contains("not permitted") || text.contains("not allowed")
        return (false, needsPrivilege)
    }

    private static func installPasswordlessRule() -> Bool {
        guard let body = LowPowerPrivilege.sudoers(user: NSUserName()) else { return false }
        let payload = Data(body.utf8).base64EncodedString()
        let script = """
        set -eu
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        printf '%s' "$1" | /usr/bin/base64 -d > "$tmp"
        /usr/sbin/visudo -cf "$tmp"
        /usr/bin/install -m 440 "$tmp" "\(LowPowerPrivilege.sudoersPath)"
        """
        return authorize(tool: "/bin/sh", arguments: ["-c", script, "macpower", payload])
    }

    private typealias ExecutePrivileges = @convention(c) (
        AuthorizationRef?,
        UnsafePointer<CChar>?,
        AuthorizationFlags,
        UnsafePointer<UnsafeMutablePointer<CChar>>?,
        UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
    ) -> OSStatus

    private static let executePrivileges: ExecutePrivileges = {
        let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY)
        guard let handle, let symbol = dlsym(handle, "AuthorizationExecuteWithPrivileges") else {
            fatalError("AuthorizationExecuteWithPrivileges missing")
        }
        return unsafeBitCast(symbol, to: ExecutePrivileges.self)
    }()

    private final class AuthorizationStore: @unchecked Sendable {
        var ref: AuthorizationRef?
        let lock = NSLock()
    }

    private static let authorization = AuthorizationStore()

    private static func authorize(tool: String, arguments: [String]) -> Bool {
        authorization.lock.lock()
        defer { authorization.lock.unlock() }
        if authorization.ref == nil {
            var created: AuthorizationRef?
            guard AuthorizationCreate(nil, nil, [], &created) == errAuthorizationSuccess, let created else {
                return false
            }
            authorization.ref = created
        }
        guard let auth = authorization.ref else { return false }
        let owned = arguments.map { strdup($0) }
        defer { owned.forEach { free($0) } }
        var argv: [UnsafeMutablePointer<CChar>?] = owned
        argv.append(nil)
        let status = tool.withCString { path in
            argv.withUnsafeMutableBufferPointer { buffer -> OSStatus in
                buffer.baseAddress!.withMemoryRebound(to: UnsafeMutablePointer<CChar>.self, capacity: buffer.count) { rebound in
                    executePrivileges(auth, path, [], rebound, nil)
                }
            }
        }
        return status == errAuthorizationSuccess
    }
}

enum LowPowerPrivilege {
    static let sudoersPath = "/etc/sudoers.d/macpower-lowpower"

    /// Rules for one local account. The name is restricted so it cannot change the rule itself.
    static func sudoers(user: String) -> String? {
        guard user.range(of: #"^[A-Za-z0-9._-]{1,32}$"#, options: .regularExpression) != nil else { return nil }
        var lines = ["# MacPower may change only Low Power Mode."]
        for flag in ["0", "1"] {
            lines.append("\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -b lowpowermode \(flag)")
            lines.append("\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -c lowpowermode \(flag)")
        }
        for battery in ["0", "1"] {
            for ac in ["0", "1"] {
                lines.append("\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -b lowpowermode \(battery) -c lowpowermode \(ac)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
