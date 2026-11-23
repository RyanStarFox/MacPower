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

    func testUpdateFailureRecordsTheStatus() {
        XCTAssertEqual(UpdateCheckFailure.http(status: 403, rateLimitRemaining: "0"), .http(403, rateLimited: true))
        XCTAssertEqual(UpdateCheckFailure.http(status: 429, rateLimitRemaining: "0"), .http(429, rateLimited: true))
        XCTAssertEqual(UpdateCheckFailure.http(status: 404, rateLimitRemaining: "0"), .http(404, rateLimited: false))
        XCTAssertEqual(UpdateCheckFailure.http(status: 403, rateLimitRemaining: "3"), .http(403, rateLimited: false))
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

    func testRingRowsMigrateFromTheOldTwoRowSplit() {
        let order: [RingSlot] = [.battery, .cpu, .gpu, .memory, .disk]
        let rows = RingBoard.migratedRows(order: order, twoRows: true)
        XCTAssertEqual(rows.map { $0.compactMap(\.slot) }, [[.battery, .cpu, .gpu], [.memory, .disk]])
        let single = RingBoard.migratedRows(order: order, twoRows: false)
        XCTAssertEqual(single.map { $0.compactMap(\.slot) }, [order])
    }

    func testDisconnectedDeviceHidesOrKeepsAnEmptyRing() {
        let left = BluetoothDisplayRing.make(parts: [.left])
        let box = BluetoothDisplayRing.make(parts: [.box])
        let device = BluetoothRingDevice(address: "aa", name: "Buds", multi: true, rings: [left, box])
        let rows: [[RingItem]] = [[
            .slot(.battery),
            .bluetooth(address: "aa", ringID: left.id),
            .bluetooth(address: "aa", ringID: box.id)
        ]]
        let hidden = RingBoard.visibleRows(rows: rows, devices: [device], seen: [])
        XCTAssertEqual(hidden, [[.slot(.battery)]])

        var emptyBox = box
        emptyBox.whenDisconnected = .empty
        var emptyDevice = device
        emptyDevice.rings = [left, emptyBox]
        let kept = RingBoard.visibleRows(rows: rows, devices: [emptyDevice], seen: [])
        XCTAssertEqual(kept, [[.slot(.battery), .bluetooth(address: "aa", ringID: box.id)]])

        let live = BluetoothSeenDevice(address: "aa", name: "Buds", connected: true, levels: [.left: 40])
        let partial = RingBoard.visibleRows(rows: rows, devices: [device], seen: [live])
        XCTAssertEqual(partial, [[.slot(.battery), .bluetooth(address: "aa", ringID: left.id)]])
        let face = RingBoard.face(ring: left, connected: true, levels: live.levels)
        XCTAssertEqual(face?.levels[.left], 40)
        XCTAssertNil(RingBoard.face(ring: box, connected: true, levels: live.levels))
    }

    func testMergedRingCanHideOrKeepTheRemainingBud() {
        var merged = BluetoothDisplayRing.make(parts: [.left, .right])
        merged.whenIncomplete = .showRemaining
        let device = BluetoothRingDevice(address: "aa", name: "Buds", multi: true, rings: [merged])
        let rows: [[RingItem]] = [[.bluetooth(address: "aa", ringID: merged.id)]]
        let live = BluetoothSeenDevice(address: "aa", name: "Buds", connected: true, levels: [.right: 70])
        let shown = RingBoard.visibleRows(rows: rows, devices: [device], seen: [live])
        XCTAssertEqual(shown, rows)
        XCTAssertEqual(
            RingBoard.face(ring: merged, connected: true, levels: live.levels)?.parts,
            [.right]
        )

        merged.whenIncomplete = .hide
        var hiding = device
        hiding.rings = [merged]
        XCTAssertEqual(RingBoard.visibleRows(rows: rows, devices: [hiding], seen: [live]), [])
    }

    func testBluetoothOnlyRowDisappearsWhenEveryRingIsHidden() {
        let ring = BluetoothDisplayRing.make(parts: [.single])
        let device = BluetoothRingDevice(address: "aa", name: "Mouse", multi: false, rings: [ring])
        let rows: [[RingItem]] = [[.slot(.cpu)], [.bluetooth(address: "aa", ringID: ring.id)]]
        let visible = RingBoard.visibleRows(rows: rows, devices: [device], seen: [])
        XCTAssertEqual(visible, [[.slot(.cpu)]])
    }

    func testHeadphoneIconsFollowTheModel() {
        XCTAssertEqual(
            HeadphoneModel.detect(name: "王邵言's AirPods 5", productID: nil),
            .airpods(generation: 5, artwork: "B868m.icns")
        )
        XCTAssertEqual(
            HeadphoneModel.detect(name: "Headphones", productID: "0x2030"),
            .airpods(generation: 5, artwork: "B868m.icns")
        )
        XCTAssertEqual(
            HeadphoneModel.detect(name: "Headphones", productID: "0x2030").symbolName(parts: [.left, .right, .box]),
            "airpods.gen4"
        )
        XCTAssertEqual(
            HeadphoneModel.detect(name: "Headphones", productID: "0x2036").symbolName(part: .left),
            "airpods.gen4.left"
        )
        XCTAssertEqual(HeadphoneModel.detect(name: "AirPods Pro", productID: nil).symbolName(part: .left), "airpods.pro.left")
        XCTAssertEqual(HeadphoneModel.detect(name: "AirPods Pro", productID: nil).symbolName(part: .box), "airpods.pro.chargingcase.wireless")
        XCTAssertEqual(HeadphoneModel.detect(name: "AirPods Max", productID: nil), .airpodsMax)
        XCTAssertEqual(HeadphoneModel.detect(name: "Beats Studio Buds", productID: nil).symbolName(part: .right), "beats.studiobuds.right")
        XCTAssertEqual(HeadphoneModel.detect(name: "Sony WH-1000XM5", productID: nil).symbolName(part: .single), "headphones")
        XCTAssertEqual(HeadphoneModel.detect(name: "Headphones", productID: "0x2013"), .airpods(generation: 3, artwork: nil))
        XCTAssertEqual(HeadphoneModel.detect(name: "Headphones", productID: "0x2013").symbolName(part: .left), "airpod.gen3.left")
    }

    func testBluetoothKindChoosesDefaultSymbolAndKeepsManualPicks() {
        func symbol(_ name: String, minor: String?, vendor: String? = nil, product: String? = nil) -> String {
            HeadphoneModel.detect(name: name, productID: product, minorType: minor, vendorID: vendor).symbolName(part: .single)
        }

        XCTAssertEqual(
            symbol("邵言的Magic Keyboard", minor: "Keyboard", vendor: "0x004C", product: "0x029C"),
            "keyboard"
        )
        XCTAssertEqual(
            HeadphoneModel.detect(name: "邵言的Magic Keyboard", productID: "0x029C", minorType: "Keyboard", vendorID: "0x004C"),
            .keyboard(apple: true)
        )
        XCTAssertEqual(symbol("键盘", minor: "Keyboard", vendor: "0x04E8", product: "0x7021"), "keyboard")
        XCTAssertEqual(symbol("Apple Magic Mouse", minor: "Mouse", vendor: "0x05AC", product: "0x030D"), "magicmouse")
        XCTAssertEqual(symbol("Logi POP Mouse", minor: "Mouse", vendor: "0x046D"), "computermouse")
        XCTAssertEqual(
            symbol("邵言的Magic Trackpad", minor: "Magic Trackpad", vendor: "0x004C", product: "0x0265"),
            "rectangle.and.hand.point.up.left"
        )
        XCTAssertEqual(symbol("SRS-XB13", minor: "Speaker"), "hifispeaker")
        XCTAssertEqual(symbol("[AV] Samsung Soundbar Q6C-Series", minor: "Headset", vendor: "0x04E8"), "hifispeaker")
        XCTAssertEqual(symbol("HomePod mini", minor: "Speaker", vendor: "0x004C"), "homepod.mini")
        XCTAssertEqual(symbol("Car Audio", minor: "Car Audio"), "car.front.waves.up")
        XCTAssertEqual(symbol("车载音响", minor: nil), "car.front.waves.up")
        XCTAssertEqual(symbol("Galaxy Buds2", minor: "Headphones"), "earbuds")
        XCTAssertEqual(symbol("Call Headset", minor: "Headset"), "headset")
        XCTAssertEqual(symbol("MOMENTUM 4", minor: "Headset"), "headphones")
        XCTAssertEqual(symbol("Xbox Wireless Controller", minor: "Gamepad"), "gamecontroller")
        XCTAssertEqual(symbol("助听器", minor: "Hearing Aid"), "hearingdevice.ear")
        XCTAssertEqual(symbol("王邵言's iPhone 15 Pro", minor: nil), "iphone")
        XCTAssertEqual(symbol("Some Accessory", minor: "Unknown"), "dot.radiowaves.left.and.right")

        let airpods = HeadphoneModel.detect(
            name: "王邵言's AirPods 5",
            productID: "0x2030",
            minorType: "Headphones",
            vendorID: "0x004C"
        )
        XCTAssertEqual(airpods.symbolName(parts: [.left, .right, .box]), "airpods.gen4")
        XCTAssertEqual(airpods.symbolName(part: .left), "airpods.gen4.left")
        XCTAssertFalse(airpods.symbolName(part: .single).contains("B868"))
        XCTAssertEqual(
            HeadphoneSymbols.glyph(model: airpods, parts: [.left, .right, .box]).name,
            "airpods.gen4"
        )
        XCTAssertEqual(HeadphoneSymbols.glyph(model: .mouse(apple: true), part: .single).name, "magicmouse")

        var ring = BluetoothDisplayRing.make(parts: [.single], model: .mouse(apple: false))
        XCTAssertEqual(ring.glyph.name, "computermouse")
        ring.automaticIcons = false
        ring.glyph = .system("star")
        ring.applyAutomaticIcons(model: .keyboard(apple: true))
        XCTAssertEqual(ring.glyph.name, "star")
        XCTAssertFalse(ring.automaticIcons)

        let json = """
        {"SPBluetoothDataType":[{"device_connected":[{"Apple Magic Mouse":{"device_address":"AA-BB","device_minorType":"Mouse","device_vendorID":"0x05AC","device_productID":"0x030D","device_batteryLevel":"80%"}}]}]}
        """.data(using: .utf8)!
        let seen = BluetoothBatteryReader.parse(json)
        XCTAssertEqual(seen.first?.minorType, "Mouse")
        XCTAssertEqual(seen.first?.vendorID, "0x05AC")
        XCTAssertEqual(seen.first?.model.symbolName(part: .single), "magicmouse")
    }

    func testBluetoothProfilerJSONReadsPercents() {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[{"Pods":{"device_address":"AA-BB","device_batteryLevelLeft":"80%","device_batteryLevelCase":"18%"}}],"device_not_connected":[{"Mouse":{"device_address":"CC-DD"}}]}]}
        """.data(using: .utf8)!
        let devices = BluetoothBatteryReader.parse(json)
        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].levels[.left], 80)
        XCTAssertEqual(devices[0].levels[.box], 18)
        XCTAssertTrue(devices[0].connected)
        XCTAssertFalse(devices[1].connected)
        XCTAssertTrue(devices[1].levels.isEmpty)
    }

    func testPermissionStatusLocalizationKeysExist() {
        for status in [
            AppPermissionStatus.allowed,
            .denied,
            .restricted,
            .notDetermined,
            .unknown,
        ] {
            XCTAssertFalse(status.localizationKey.isEmpty)
            XCTAssertTrue(status.localizationKey.hasPrefix("settings.permissions.status."))
        }
        XCTAssertEqual(AppPermissionKind.allCases.map(\.rawValue), ["bluetooth", "lowPowerAdmin"])
        _ = AppPermissions.status(for: .bluetooth)
        _ = AppPermissions.status(for: .lowPowerAdmin)
    }

    func testBluetoothMergeFillsHFPBatteryFromIOBluetooth() {
        let profiler = [
            BluetoothSeenDevice(
                address: "80-c3-ba-4a-92-9d",
                name: "MOMENTUM 4",
                connected: true,
                levels: [:],
                minorType: "Headset"
            ),
            BluetoothSeenDevice(
                address: "48:35:AB:56:64:1C",
                name: "AirPods 5",
                connected: false,
                levels: [.left: 100, .right: 100, .box: 85]
            ),
        ]
        let live = [
            BluetoothSeenDevice(
                address: "80:C3:BA:4A:92:9D",
                name: "MOMENTUM 4",
                connected: true,
                levels: [.single: 40]
            ),
            BluetoothSeenDevice(
                address: "48-35-ab-56-64-1c",
                name: "AirPods 5",
                connected: false,
                levels: [.left: 74, .right: 62]
            ),
        ]
        let merged = BluetoothBatteryReader.merge(profiler: profiler, live: live)
        let momentum = merged.first { $0.name.contains("MOMENTUM") }
        let airpods = merged.first { $0.name.contains("AirPods") }
        XCTAssertEqual(momentum?.address, "80:C3:BA:4A:92:9D")
        XCTAssertEqual(momentum?.levels[.single], 40)
        XCTAssertEqual(momentum?.minorType, "Headset")
        XCTAssertEqual(airpods?.levels[.left], 100)
        XCTAssertEqual(airpods?.levels[.right], 100)
        XCTAssertEqual(airpods?.levels[.box], 85)
        XCTAssertEqual(BluetoothBatteryReader.normalizeAddress("80-c3-ba-4a-92-9d"), "80:C3:BA:4A:92:9D")
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
