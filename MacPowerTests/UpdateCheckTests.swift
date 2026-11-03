import AppKit
import CoreServices
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
        XCTAssertTrue(UpdateCheckPolicy.shouldCheck(enabled: false, reason: .manual, lastCheck: nil, now: now))
    }

    func testLaunchAndToggleAlwaysCheckWhenEnabled() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = now.addingTimeInterval(-3_600)
        XCTAssertTrue(UpdateCheckPolicy.shouldCheck(enabled: true, reason: .launch, lastCheck: recent, now: now))
        XCTAssertTrue(UpdateCheckPolicy.shouldCheck(enabled: true, reason: .userEnabled, lastCheck: recent, now: now))
    }

    func testPeriodicChecksOncePerClockHour() {
        let calendar = Calendar.current
        let checked = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 14, minute: 5))!
        let laterSameHour = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 14, minute: 50))!
        let nextHour = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 15, minute: 0))!
        XCTAssertFalse(UpdateCheckPolicy.shouldCheck(
            enabled: true, reason: .periodic, lastCheck: checked, now: laterSameHour, calendar: calendar
        ))
        XCTAssertTrue(UpdateCheckPolicy.shouldCheck(
            enabled: true, reason: .periodic, lastCheck: checked, now: nextHour, calendar: calendar
        ))
        XCTAssertTrue(UpdateCheckPolicy.shouldCheck(
            enabled: true, reason: .periodic, lastCheck: nil, now: nextHour, calendar: calendar
        ))
    }

    func testNextCheckLandsOnTheFollowingHour() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 14, minute: 5, second: 30))!
        let next = UpdateCheckPolicy.nextHourlyCheck(after: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: next), 15)
        XCTAssertEqual(calendar.component(.minute, from: next), 0)
        XCTAssertEqual(calendar.component(.second, from: next), 0)
        let onTheHour = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 15, minute: 0, second: 0))!
        let afterExactHour = UpdateCheckPolicy.nextHourlyCheck(after: onTheHour, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: afterExactHour), 16)
    }

    func testDeferredUpdateStaysQuietUntilANewerRelease() {
        XCTAssertFalse(UpdateCheckPolicy.shouldPresentUpdate(latest: "1.3.1", deferred: "v1.3.1"))
        XCTAssertFalse(UpdateCheckPolicy.shouldPresentUpdate(latest: "v1.3.1", deferred: "1.3.1"))
        XCTAssertTrue(UpdateCheckPolicy.shouldPresentUpdate(latest: "1.3.2", deferred: "1.3.1"))
        XCTAssertTrue(UpdateCheckPolicy.shouldPresentUpdate(latest: "1.3.1", deferred: nil))
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

    func testSha256MarkerReadsTheDigest() {
        let digest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        let body = """
        notes
        <!-- macpower-sha256
        \(digest)
        -->
        """
        XCTAssertEqual(ReleaseNotes.sha256(in: body), digest)
        XCTAssertNil(ReleaseNotes.sha256(in: "<!-- macpower-sha256\nnope\n-->"))
    }

    func testUpdateOfferUsesGitHubZipAndFallsBackToGiteeURL() {
        let digest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        let body = "<!-- macpower-sha256 \(digest) -->"
        let github = URL(string: "https://github.com/RyanStarFox/MacPower/releases/download/v1.3.1/MacPower-1.3.1.zip")!
        let offer = UpdatePackage.offer(
            tag: "v1.3.1",
            body: body,
            assets: [.init(name: "MacPower-1.3.1.zip", url: github), .init(name: "MacPower-1.3.1.dmg", url: github)]
        )
        XCTAssertEqual(offer?.sha256, digest)
        XCTAssertEqual(offer?.githubZip, github)
        XCTAssertEqual(
            offer?.giteeZip.absoluteString,
            "https://gitee.com/Ryan_LS_Wang/MacPower/releases/download/v1.3.1/MacPower-1.3.1.zip"
        )
        XCTAssertEqual(UpdatePackage.sourceOrder, [.github])
        XCTAssertEqual(UpdatePackage.noDataTimeout, 60)
        XCTAssertNil(UpdatePackage.offer(tag: "v1.3.1", body: body, assets: []))
    }

    func testFileSha256MatchesCryptoKit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("macpower-sha-\(UUID().uuidString)")
        try Data("MacPower".utf8).write(to: url)
        XCTAssertEqual(
            UpdateInstaller.sha256Hex(of: url),
            "d66e7cc8af522112be9c0b2c6d75a580552094ec4c74e1ce6b65c263e8643f2a"
        )
        try? FileManager.default.removeItem(at: url)
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

final class LoginLaunchTests: XCTestCase {
    func testPlainOpenIsNotLogin() {
        XCTAssertFalse(LoginLaunch.isLoginLaunch(nil))
        XCTAssertFalse(LoginLaunch.isLoginLaunch(openEvent()))
    }

    func testNestedLoginFlag() {
        let event = openEvent()
        let record = NSAppleEventDescriptor.record()
        record.setParam(NSAppleEventDescriptor(boolean: true), forKeyword: keyAELaunchedAsLogInItem)
        event.setParam(record, forKeyword: keyAEPropData)
        XCTAssertTrue(LoginLaunch.isLoginLaunch(event))
    }

    func testDirectLoginFlag() {
        let event = openEvent()
        event.setParam(NSAppleEventDescriptor(boolean: true), forKeyword: keyAELaunchedAsLogInItem)
        XCTAssertTrue(LoginLaunch.isLoginLaunch(event))
    }

    func testExplicitFalseIsNotLogin() {
        let event = openEvent()
        event.setParam(NSAppleEventDescriptor(boolean: false), forKeyword: keyAELaunchedAsLogInItem)
        XCTAssertFalse(LoginLaunch.isLoginLaunch(event))
    }

    private func openEvent() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: kCoreEventClass,
            eventID: kAEOpenApplication,
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }
}
