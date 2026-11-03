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

/// Reports byte progress while `runModal` is up. URLSession retains this delegate.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onFraction: @Sendable (Double?) -> Void
    private let lock = NSLock()
    private var session: URLSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var finished = false

    init(onFraction: @escaping @Sendable (Double?) -> Void, continuation: CheckedContinuation<URL, Error>) {
        self.onFraction = onFraction
        self.continuation = continuation
    }

    func attach(_ session: URLSession) {
        lock.lock()
        self.session = session
        lock.unlock()
    }

    private func finish(with result: Result<URL, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        lock.unlock()
        session?.finishTasksAndInvalidate()
        switch result {
        case .success(let url): continuation?.resume(returning: url)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        onFraction(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            finish(with: .failure(UpdateInstaller.Failure.downloadFailed))
            return
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPower-\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            finish(with: .success(destination))
        } catch {
            finish(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(with: .failure(error))
            return
        }
        if let response = task.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            finish(with: .failure(UpdateInstaller.Failure.downloadFailed))
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
        progress: @escaping @Sendable (UpdateDownloadSource) -> Void,
        onFraction: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        for source in UpdatePackage.sourceOrder {
            if sessionBox.isCancelled() { throw CancellationError() }
            progress(source)
            onFraction(nil)
            let url = UpdatePackage.url(for: source, offer: offer)
            do {
                let file = try await download(url, box: sessionBox, onFraction: onFraction)
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

    private static func download(
        _ url: URL,
        box: UpdateDownloadSession,
        onFraction: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = UpdatePackage.stallTimeout
        configuration.timeoutIntervalForResource = 30 * 60
        configuration.waitsForConnectivity = false
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadProgressDelegate(onFraction: onFraction, continuation: continuation)
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            delegate.attach(session)
            box.store(session)
            var request = URLRequest(url: url)
            request.timeoutInterval = UpdatePackage.stallTimeout
            request.setValue("MacPower", forHTTPHeaderField: "User-Agent")
            session.downloadTask(with: request).resume()
        }
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
    /// Nil while the server has not sent a total size. Otherwise 0...1.
    var fraction: Double?
    let offer: UpdatePackage.Offer
    var text: UpdateInstallText
    var onInstalled: () -> Void = {}

    /// One sentence for the status line. The percent is drawn beside the bar.
    var statusText: String {
        switch phase {
        case .ready:
            return ""
        case .downloading(.github):
            return text.downloadingGitHub
        case .downloading(.gitee):
            return text.downloadingGitee
        case .installing:
            return text.installing
        case .failed:
            return text.failed
        }
    }

    var percentText: String? {
        guard case .downloading = phase, let fraction else { return nil }
        return "\(Int((fraction * 100).rounded()))%"
    }
    private var task: Task<Void, Never>?
    private let downloadSession = UpdateDownloadSession()

    init(offer: UpdatePackage.Offer, text: UpdateInstallText) {
        self.offer = offer
        self.text = text
    }

    func start() {
        guard phase == .ready || phase == .failed else { return }
        fraction = nil
        phase = .downloading(.github)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let zip = try await UpdateInstaller.downloadVerifiedZip(
                    offer: offer,
                    sessionBox: downloadSession
                ) { source in
                    Task { @MainActor in
                        self.fraction = nil
                        self.phase = .downloading(source)
                    }
                } onFraction: { [weak self] value in
                    Task { @MainActor in
                        self?.fraction = value
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
