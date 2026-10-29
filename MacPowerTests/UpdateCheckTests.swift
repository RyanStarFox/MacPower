import XCTest
@testable import MacPower

final class AppVersionTests: XCTestCase {
    func testTagPrefixDoesNotCountAsNewer() {
        XCTAssertFalse(AppVersion.isNewer("v1.2.4", than: "1.2.4"))
        XCTAssertFalse(AppVersion.isNewer("1.2.4", than: "v1.2.4"))
    }

    func testLaterPatchIsNewer() {
        XCTAssertTrue(AppVersion.isNewer("1.2.5", than: "1.2.4"))
        XCTAssertFalse(AppVersion.isNewer("1.2.4", than: "1.2.5"))
    }

    func testNumericComponentsBeatStringOrder() {
        XCTAssertTrue(AppVersion.isNewer("1.10.0", than: "1.9.0"))
        XCTAssertTrue(AppVersion.isNewer("2.0.0", than: "1.9.9"))
    }

    func testMissingPatchTreatsAsZero() {
        XCTAssertFalse(AppVersion.isNewer("1.2", than: "1.2.0"))
        XCTAssertTrue(AppVersion.isNewer("1.2.1", than: "1.2"))
    }
}

final class GitHubLatestReleaseTests: XCTestCase {
    func testDecodesTagAndHTMLURL() throws {
        let json = """
        {"tag_name":"v1.2.5","html_url":"https://github.com/RyanStarFox/MacPower/releases/tag/v1.2.5","body":"<!-- macpower-notes\\n{\\"en\\":\\"Hello\\",\\"zh-Hans\\":\\"你好\\"}\\n-->"}
        """
        let release = try GitHubLatestRelease.decode(Data(json.utf8))
        XCTAssertEqual(release.tagName, "v1.2.5")
        XCTAssertEqual(release.htmlURL.absoluteString, "https://github.com/RyanStarFox/MacPower/releases/tag/v1.2.5")
        XCTAssertEqual(release.notes.text(for: .english), "Hello")
        XCTAssertEqual(release.notes.text(for: .simplifiedChinese), "你好")
    }

    func testReleaseWithoutNotesStillDecodes() throws {
        let json = """
        {"tag_name":"v1.2.5","html_url":"https://github.com/RyanStarFox/MacPower/releases/tag/v1.2.5"}
        """
        let release = try GitHubLatestRelease.decode(Data(json.utf8))
        XCTAssertEqual(release.notes.text(for: .english), "")
    }

    func testRejectsMissingURL() {
        let json = """
        {"tag_name":"v1.2.5"}
        """
        XCTAssertThrowsError(try GitHubLatestRelease.decode(Data(json.utf8)))
    }
}

final class UpdateCheckPolicyTests: XCTestCase {
    func testDisabledNeverChecks() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(UpdateCheckPolicy.shouldCheck(enabled: false, reason: .launch, lastCheck: nil, now: now))
        XCTAssertFalse(UpdateCheckPolicy.shouldCheck(enabled: false, reason: .periodic, lastCheck: nil, now: now))
        XCTAssertFalse(UpdateCheckPolicy.shouldCheck(enabled: false, reason: .userEnabled, lastCheck: nil, now: now))
    }

    func testLaunchAndToggleAlwaysCheckWhenEnabled() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = now.addingTimeInterval(-3_600)
        XCTAssertTrue(UpdateCheckPolicy.shouldCheck(enabled: true, reason: .launch, lastCheck: recent, now: now))
        XCTAssertTrue(UpdateCheckPolicy.shouldCheck(enabled: true, reason: .userEnabled, lastCheck: recent, now: now))
    }

    func testPeriodicSkipsInsideTwentyFourHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = now.addingTimeInterval(-3_600)
        XCTAssertFalse(UpdateCheckPolicy.shouldCheck(enabled: true, reason: .periodic, lastCheck: recent, now: now))
        XCTAssertTrue(UpdateCheckPolicy.shouldCheck(enabled: true, reason: .periodic, lastCheck: nil, now: now))
    }

    func testPeriodicChecksAfterTwentyFourHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stale = now.addingTimeInterval(-UpdateCheckPolicy.interval)
        XCTAssertTrue(UpdateCheckPolicy.shouldCheck(enabled: true, reason: .periodic, lastCheck: stale, now: now))
        XCTAssertEqual(UpdateCheckPolicy.interval, 86_400)
    }
}

final class ReleaseNotesTests: XCTestCase {
    func testBundledNotesCoverEveryLanguage() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MacPower/ReleaseNotes.json")
        let data = try Data(contentsOf: url)
        let notes = try JSONDecoder().decode([String: String].self, from: data)
        let required = AppLanguage.allCases.compactMap(\.localeIdentifier)
        for key in required {
            let text = notes[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            XCTAssertFalse(text.isEmpty, key)
        }
    }

    func testUnknownLanguageFallsBackToEnglish() {
        let notes = ReleaseNotes(sections: ["en": "Hello", "zh-Hans": "你好"])
        XCTAssertEqual(notes.text(for: .korean), "Hello")
        XCTAssertEqual(notes.text(for: .simplifiedChinese), "你好")
    }

    func testParagraphsKeepEachBulletOnItsOwnRow() {
        let notes = "• 第一行比较长\n• 第二行\n续在下一段"
        XCTAssertEqual(ReleaseNotes.paragraphs(in: notes), ["第一行比较长", "第二行 续在下一段"])
        XCTAssertEqual(ReleaseNotes.paragraphs(in: "1. Hello\n2) Next"), ["Hello", "Next"])
        XCTAssertTrue(ReleaseNotes.paragraphs(in: "   \n").isEmpty)
    }

    func testWhatsNewShowsWhenVersionChangesOrIsUnrecorded() {
        XCTAssertTrue(ReleaseNotes.shouldPresentWhatsNew(stored: nil, current: "1.3.0"))
        XCTAssertTrue(ReleaseNotes.shouldPresentWhatsNew(stored: "1.2.14", current: "1.3.0"))
        XCTAssertFalse(ReleaseNotes.shouldPresentWhatsNew(stored: "1.3.0", current: "1.3.0"))
    }
}

final class AutoUpdateSettingsTests: XCTestCase {
    func testAutomaticallyCheckForUpdatesDefaultsOnAndPersists() {
        let suite = "MacPower.AutoUpdateTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        XCTAssertTrue(first.automaticallyCheckForUpdates)
        first.automaticallyCheckForUpdates = false
        let second = AppSettings(defaults: defaults)
        XCTAssertFalse(second.automaticallyCheckForUpdates)
        defaults.removePersistentDomain(forName: suite)
    }
}
