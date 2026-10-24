import Foundation

struct GitHubLatestRelease: Equatable, Sendable {
    var tagName: String
    var htmlURL: URL

    static func decode(_ data: Data) throws -> GitHubLatestRelease {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let url = URL(string: payload.htmlURL) else {
            throw URLError(.badURL)
        }
        return GitHubLatestRelease(tagName: payload.tagName, htmlURL: url)
    }

    private struct Payload: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}

enum UpdateCheckReason: Sendable {
    /// App launch: always query GitHub if the setting is on.
    case launch
    /// Background: at most once per `interval` while the app stays open.
    case periodic
    /// User turned the setting on: check immediately.
    case userEnabled
}

enum UpdateCheckPolicy {
    static let interval: TimeInterval = 86_400

    static func shouldCheck(
        enabled: Bool,
        reason: UpdateCheckReason,
        lastCheck: Date?,
        now: Date
    ) -> Bool {
        guard enabled else { return false }
        switch reason {
        case .launch, .userEnabled:
            return true
        case .periodic:
            guard let lastCheck else { return true }
            return now.timeIntervalSince(lastCheck) >= interval
        }
    }
}

@MainActor
final class UpdateChecker {
    static let githubRepoURL = URL(string: "https://github.com/RyanStarFox/MacPower")!
    static let koFiURL = URL(string: "https://ko-fi.com/ryanstarfox")!
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/RyanStarFox/MacPower/releases/latest")!

    private enum Keys {
        static let lastCheck = "lastUpdateCheckAt"
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.session = session
        self.now = now
    }

    func checkIfNeeded(
        enabled: Bool,
        reason: UpdateCheckReason,
        currentVersion: String
    ) async -> GitHubLatestRelease? {
        guard UpdateCheckPolicy.shouldCheck(
            enabled: enabled,
            reason: reason,
            lastCheck: defaults.object(forKey: Keys.lastCheck) as? Date,
            now: now()
        ) else {
            return nil
        }
        do {
            var request = URLRequest(url: Self.latestReleaseURL)
            request.setValue("MacPower/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            let release = try GitHubLatestRelease.decode(data)
            defaults.set(now(), forKey: Keys.lastCheck)
            guard AppVersion.isNewer(release.tagName, than: currentVersion) else { return nil }
            return release
        } catch {
            return nil
        }
    }
}
