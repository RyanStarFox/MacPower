import CryptoKit
import Foundation

/// Where an update zip is downloaded from. Version lookup stays on GitHub.
enum UpdateDownloadSource: String, Equatable, Sendable {
    case github
    case gitee
}

enum UpdatePackage {
    /// Idle time with no new bytes before the current download is abandoned.
    static let stallTimeout: TimeInterval = 15

    struct Offer: Equatable, Sendable {
        var version: String
        var sha256: String
        var githubZip: URL
        var giteeZip: URL
    }

    /// GitHub first. Gitee is only tried after GitHub fails.
    static let sourceOrder: [UpdateDownloadSource] = [.github, .gitee]

    static func zipName(version: String) -> String {
        "MacPower-\(version).zip"
    }

    static func giteeZipURL(tag: String) -> URL {
        let version = AppVersion.display(tag)
        var tagName = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if tagName.first != "v" && tagName.first != "V" {
            tagName = "v" + tagName
        }
        let file = zipName(version: version)
        return URL(string: "https://gitee.com/Ryan_LS_Wang/MacPower/releases/download/\(tagName)/\(file)")!
    }

    /// One-click install needs the zip attached to the GitHub release and a sha256 in the body.
    static func offer(
        tag: String,
        body: String,
        assets: [GitHubLatestRelease.ReleaseAsset]
    ) -> Offer? {
        let version = AppVersion.display(tag)
        guard let sha = ReleaseNotes.sha256(in: body),
              let github = assets.first(where: { $0.name == zipName(version: version) })?.url
        else { return nil }
        return Offer(
            version: version,
            sha256: sha,
            githubZip: github,
            giteeZip: giteeZipURL(tag: tag)
        )
    }

    static func url(for source: UpdateDownloadSource, offer: Offer) -> URL {
        switch source {
        case .github: offer.githubZip
        case .gitee: offer.giteeZip
        }
    }
}

final class UpdateDownloadSession: @unchecked Sendable {
    private let lock = NSLock()
    private var session: URLSession?
    private var cancelled = false

    func store(_ session: URLSession) {
        lock.lock()
        self.session = session
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let session = self.session
        lock.unlock()
        session?.invalidateAndCancel()
    }

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

enum UpdateInstaller {
    enum Failure: Error {
        case downloadFailed
        case checksumMismatch
        case extractFailed
        case notWritable
    }

    /// Downloads GitHub, then Gitee, and returns the first zip whose sha256 matches the release.
    static func downloadVerifiedZip(
        offer: UpdatePackage.Offer,
        sessionBox: UpdateDownloadSession,
        progress: @escaping @Sendable (UpdateDownloadSource) -> Void
    ) async throws -> URL {
        for source in UpdatePackage.sourceOrder {
            if sessionBox.isCancelled() { throw CancellationError() }
            progress(source)
            let url = UpdatePackage.url(for: source, offer: offer)
            do {
                let file = try await download(url, box: sessionBox)
                if sessionBox.isCancelled() { throw CancellationError() }
                let digest = sha256Hex(of: file)
                guard digest == offer.sha256 else {
                    try? FileManager.default.removeItem(at: file)
                    continue
                }
                return file
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if sessionBox.isCancelled() { throw CancellationError() }
                continue
            }
        }
        throw Failure.downloadFailed
    }

    static func extractApp(from zip: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPower-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, destination.path]
        try process.run()
        process.waitUntilExit()
        let app = destination.appendingPathComponent("MacPower.app")
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: app.path) else {
            throw Failure.extractFailed
        }
        return app
    }

    static func destinationApp() -> URL {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            return bundle
        }
        return URL(fileURLWithPath: "/Applications/MacPower.app")
    }

    /// Replaces the running app after this process exits, then opens it again.
    static func scheduleReplaceAndRelaunch(app: URL, destination: URL) throws {
        guard destination.pathExtension == "app", destination.lastPathComponent == "MacPower.app" else {
            throw Failure.notWritable
        }
        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw Failure.notWritable
        }
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do
          sleep 0.2
        done
        rm -rf \(shellQuote(destination.path))
        ditto \(shellQuote(app.path)) \(shellQuote(destination.path))
        xattr -dr com.apple.quarantine \(shellQuote(destination.path)) || true
        open \(shellQuote(destination.path))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    static func sha256Hex(of file: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try? handle.read(upToCount: 1024 * 1024)
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func download(_ url: URL, box: UpdateDownloadSession) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = UpdatePackage.stallTimeout
        configuration.timeoutIntervalForResource = 30 * 60
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        box.store(session)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.timeoutInterval = UpdatePackage.stallTimeout
        request.setValue("MacPower", forHTTPHeaderField: "User-Agent")
        let (temp, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.downloadFailed
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPower-\(UUID().uuidString).zip")
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct UpdateInstallText: Equatable, Sendable {
    var update: String
    var downloadingGitHub: String
    var downloadingGitee: String
    var installing: String
    var failed: String
}

@MainActor
@Observable
final class UpdateInstallController {
    enum Phase: Equatable {
        case ready
        case downloading(UpdateDownloadSource)
        case installing
        case failed
    }

    var phase: Phase = .ready
    let offer: UpdatePackage.Offer
    var text: UpdateInstallText
    var onInstalled: () -> Void = {}
    private var task: Task<Void, Never>?
    private let downloadSession = UpdateDownloadSession()

    init(offer: UpdatePackage.Offer, text: UpdateInstallText) {
        self.offer = offer
        self.text = text
    }

    func start() {
        guard phase == .ready || phase == .failed else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let zip = try await UpdateInstaller.downloadVerifiedZip(
                    offer: offer,
                    sessionBox: downloadSession
                ) { source in
                    Task { @MainActor in
                        self.phase = .downloading(source)
                    }
                }
                phase = .installing
                let app = try UpdateInstaller.extractApp(from: zip)
                try UpdateInstaller.scheduleReplaceAndRelaunch(
                    app: app,
                    destination: UpdateInstaller.destinationApp()
                )
                onInstalled()
            } catch is CancellationError {
                return
            } catch {
                phase = .failed
            }
        }
    }

    func cancel() {
        downloadSession.cancel()
        task?.cancel()
        task = nil
    }
}
