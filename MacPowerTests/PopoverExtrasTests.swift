import Darwin
import XCTest
@testable import MacPower

final class PopoverExtrasTests: XCTestCase {
    func testLowPowerPresetMapping() {
        XCTAssertEqual(LowPowerPreset.preset(battery: false, ac: false), .alwaysPerformance)
        XCTAssertEqual(LowPowerPreset.preset(battery: true, ac: true), .alwaysSave)
        XCTAssertEqual(LowPowerPreset.preset(battery: true, ac: false), .onlyBattery)
        XCTAssertEqual(LowPowerPreset.preset(battery: false, ac: true), .onlyPower)
    }

    func testLowPowerPresetParsesPmsetSections() {
        let output = """
        Battery Power:
         lowpowermode         1
         displaysleep         2
        AC Power:
         lowpowermode         0
         displaysleep         10
        """
        XCTAssertEqual(LowPowerPreset.parse(pmsetOutput: output), .onlyBattery)
        XCTAssertNil(LowPowerPreset.parse(pmsetOutput: "Battery Power:\n sleep 1\n"))
    }

    func testLowPowerCommandsAndReapplyRule() {
        XCTAssertEqual(
            LowPowerModeController.command(for: .onlyBattery),
            "pmset -b lowpowermode 1 -c lowpowermode 0"
        )
        XCTAssertEqual(
            LowPowerModeController.command(activeOn: true, externalConnected: false),
            "pmset -b lowpowermode 1"
        )
        XCTAssertEqual(
            LowPowerModeController.command(activeOn: false, externalConnected: true),
            "pmset -c lowpowermode 0"
        )
        XCTAssertFalse(LowPowerModeController.shouldReapplyStrategy(previousExternal: nil, external: true, hasStrategy: true))
        XCTAssertFalse(LowPowerModeController.shouldReapplyStrategy(previousExternal: false, external: false, hasStrategy: true))
        XCTAssertFalse(LowPowerModeController.shouldReapplyStrategy(previousExternal: false, external: true, hasStrategy: false))
        XCTAssertTrue(LowPowerModeController.shouldReapplyStrategy(previousExternal: false, external: true, hasStrategy: true))
    }

    func testLowPowerStrategyPersists() {
        let suite = "MacPower.LowPowerStrategy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        XCTAssertNil(first.lowPowerStrategy)
        first.lowPowerStrategy = .onlyBattery
        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.lowPowerStrategy, .onlyBattery)
        second.lowPowerStrategy = nil
        let third = AppSettings(defaults: defaults)
        XCTAssertNil(third.lowPowerStrategy)
        defaults.removePersistentDomain(forName: suite)
    }

    func testSudoersAllowsOnlyLowPowerCommands() {
        let text = LowPowerPrivilege.sudoers(user: "wang")
        XCTAssertEqual(text?.split(separator: "\n").filter { $0.contains("NOPASSWD") }.count, 8)
        XCTAssertTrue(text?.contains("wang ALL=(root) NOPASSWD: /usr/bin/pmset -b lowpowermode 1 -c lowpowermode 0") == true)
        XCTAssertNil(LowPowerPrivilege.sudoers(user: "wang shaoyan"))
        XCTAssertNil(LowPowerPrivilege.sudoers(user: "root;reboot"))
    }

    func testProcessEnergyFilterSkipsDaemonsOutsideApps() {
        XCTAssertTrue(ProcessEnergyFilter.include(path: "/Applications/Safari.app/Contents/MacOS/Safari", name: "Safari"))
        XCTAssertTrue(ProcessEnergyFilter.include(path: "/usr/libexec/mds", name: "mds"))
        XCTAssertFalse(ProcessEnergyFilter.include(path: "/usr/libexec/sysmond", name: "sysmond"))
        XCTAssertFalse(ProcessEnergyFilter.include(path: "/System/Library/CoreServices/WindowManager", name: ""))
        XCTAssertFalse(ProcessEnergyFilter.include(
            path: "/System/Library/CoreServices/WindowManager.app/Contents/MacOS/WindowManager",
            name: "WindowManager"
        ))
        XCTAssertFalse(ProcessEnergyFilter.include(
            path: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
            name: "ControlCenter"
        ))
        XCTAssertTrue(ProcessEnergyFilter.include(
            path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
            name: "Finder"
        ))
    }

    func testTopAppsChartScaleUsesTheTallestBar() {
        let fractions = TopAppsChartScale.fractions([2, 8, 0])
        XCTAssertEqual(fractions[0], 0.25, accuracy: 0.001)
        XCTAssertEqual(fractions[1], 1, accuracy: 0.001)
        XCTAssertEqual(fractions[2], 0, accuracy: 0.001)
        XCTAssertEqual(TopAppsChartStyle.resolved(stored: nil), .bars)
        XCTAssertEqual(TopAppsChartStyle.resolved(stored: "columns"), .columns)
        XCTAssertEqual(TopAppsChartStyle.resolved(stored: "nope"), .bars)
    }

    func testProcessGroupingUsesTheOuterApp() {
        let nested = ProcessGrouping.identity(
            path: "/Applications/Outer.app/Contents/Helpers/Inner.app/Contents/MacOS/Inner",
            fallbackName: "Inner"
        )
        XCTAssertEqual(nested.group, "/Applications/Outer.app")
        XCTAssertEqual(nested.name, "Outer")
        XCTAssertEqual(nested.iconPath, "/Applications/Outer.app")

        let kernel = ProcessGrouping.identity(path: "", fallbackName: "kernel_task")
        XCTAssertEqual(kernel.group, "kernel_task")
        XCTAssertNil(kernel.iconPath)
    }

    func testRankerSumsHelperProcessesAndSkipsIdleOnes() {
        let current = [
            ProcessTick(pid: 1, group: "/A.app", name: "A", iconPath: "/A.app", impact: 3),
            ProcessTick(pid: 2, group: "/A.app", name: "A", iconPath: "/A.app", impact: 2),
            ProcessTick(pid: 3, group: "kernel_task", name: "kernel_task", iconPath: nil, impact: 0),
            ProcessTick(pid: 4, group: "/B.app", name: "B", iconPath: "/B.app", impact: 2),
        ]
        let ranked = TopAppRanker.rank(current: current, limit: 5)
        XCTAssertEqual(ranked.map(\.name), ["A", "B"])
        XCTAssertEqual(ranked[0].impact, 5, accuracy: 0.001)
        XCTAssertEqual(ranked[1].impact, 2, accuracy: 0.001)
    }

    func testRankerAveragesTheThreeMinuteWindowAndCountsGapsAsZero() {
        let intervals = [
            EnergyInterval(apps: [
                AppEnergySample(group: "a", name: "A", iconPath: nil, impact: 9),
                AppEnergySample(group: "b", name: "B", iconPath: nil, impact: 4),
            ]),
            EnergyInterval(apps: [
                AppEnergySample(group: "b", name: "B", iconPath: nil, impact: 4),
            ]),
            EnergyInterval(apps: [
                AppEnergySample(group: "b", name: "B", iconPath: nil, impact: 4),
            ]),
        ]
        let ranked = TopAppRanker.rank(intervals: intervals, limit: 5)
        XCTAssertEqual(ranked.map(\.name), ["B", "A"])
        XCTAssertEqual(ranked[0].impact, 4, accuracy: 0.001)
        XCTAssertEqual(ranked[1].impact, 3, accuracy: 0.001)
    }

    func testRankerKeepsFiveAndOrdersTiesByName() {
        let current = [
            ProcessTick(pid: 1, group: "zeta", name: "zeta", iconPath: nil, impact: 10),
            ProcessTick(pid: 2, group: "alpha", name: "alpha", iconPath: nil, impact: 10),
            ProcessTick(pid: 3, group: "mid", name: "mid", iconPath: nil, impact: 5),
        ]
        let ranked = TopAppRanker.rank(current: current, limit: 2)
        XCTAssertEqual(ranked.map(\.name), ["alpha", "zeta"])
    }

    func testPowerSampleReadsThisProcess() {
        let first = PowerSample.take(pid: getpid())
        XCTAssertNotNil(first)
        var accumulator = 0
        for value in 0..<30_000_000 { accumulator &+= value }
        let second = PowerSample.take(pid: getpid())
        let rate = PowerSample.rate(previous: first ?? [], current: second ?? [], elapsed: 0.3)
        XCTAssertGreaterThan(accumulator, 0)
        XCTAssertGreaterThan(rate, 0)
    }

    func testEnergyImpactLabel() {
        XCTAssertEqual(EnergyImpact.label(48.54), "48.5")
        XCTAssertEqual(EnergyImpact.label(0.04), "0.0")
    }

    func testPopoverOrderPersistsAndKeepsEveryBlock() {
        let suite = "MacPower.PopoverOrder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        assertDividersBetweenEveryBlock(first.popoverOrder)
        let visible = first.renderedPopoverEntries
        XCTAssertEqual(visible.compactMap(\.block), [.rings, .flow, .topApps, .lowPower, .localIP, .batteryCycle])
        assertSingleDividerBetweenVisibleBlocks(visible)
        first.movePopoverBlock(.lowPower, to: .rings)
        XCTAssertEqual(
            first.popoverOrder.compactMap(\.block),
            [.lowPower, .rings, .flow, .topApps, .localIP, .batteryCycle, .settings]
        )
        defaults.set(["rings"], forKey: "popoverOrder")
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.popoverOrder, PopoverBlock.allCases.map(PopoverEntry.block))
        defaults.removePersistentDomain(forName: suite)
    }

    func testPopoverDividersRoundTripAndCollapse() throws {
        let suite = "MacPower.PopoverDividers.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let fresh = AppSettings(defaults: defaults)
        assertDividersBetweenEveryBlock(fresh.popoverOrder)
        fresh.showEnergyFlow = false
        fresh.showLowPower = false
        assertSingleDividerBetweenVisibleBlocks(fresh.renderedPopoverEntries)
        XCTAssertEqual(
            fresh.renderedPopoverEntries.compactMap(\.block),
            [.rings, .topApps, .localIP, .batteryCycle]
        )

        let leading = UUID()
        let between = UUID()
        let stacked = UUID()
        let trailing = UUID()
        defaults.set(
            [
                PopoverEntry.divider(leading).rawValue,
                PopoverBlock.rings.rawValue,
                PopoverEntry.divider(between).rawValue,
                PopoverEntry.divider(stacked).rawValue,
                PopoverBlock.flow.rawValue,
                PopoverEntry.divider(trailing).rawValue,
            ],
            forKey: "popoverOrder"
        )
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(
            Array(restored.popoverOrder.prefix(6)),
            [.divider(leading), .block(.rings), .divider(between), .divider(stacked), .block(.flow), .divider(trailing)]
        )
        XCTAssertEqual(restored.popoverOrder.compactMap(\.block), PopoverBlock.allCases)
        XCTAssertEqual(
            defaults.stringArray(forKey: "popoverOrder")?.prefix(2).map { $0 },
            [PopoverEntry.divider(leading).rawValue, PopoverBlock.rings.rawValue]
        )

        restored.showStatusRings = true
        restored.showEnergyFlow = true
        restored.showTopApps = false
        restored.showLowPower = false
        restored.showLocalIP = false
        restored.showBatteryCycle = false
        let rendered = restored.renderedPopoverEntries
        XCTAssertEqual(rendered, [.block(.rings), .divider(stacked), .block(.flow)])
        XCTAssertFalse(rendered.first?.isDivider == true)
        XCTAssertFalse(rendered.last?.isDivider == true)

        restored.showEnergyFlow = false
        XCTAssertEqual(restored.renderedPopoverEntries, [.block(.rings)])

        restored.addPopoverDivider()
        let saved = defaults.stringArray(forKey: "popoverOrder") ?? []
        XCTAssertEqual(saved.filter { PopoverBlock(rawValue: $0) != nil }.count, PopoverBlock.allCases.count)
        XCTAssertTrue(saved.contains { $0.hasPrefix(PopoverEntry.dividerPrefix) })
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.popoverOrder, restored.popoverOrder)

        if case .divider(let added) = reloaded.popoverOrder.last {
            reloaded.movePopoverEntry(.divider(added), to: .block(.flow))
            let flowIndex = try XCTUnwrap(reloaded.popoverOrder.firstIndex(of: .block(.flow)))
            XCTAssertGreaterThan(flowIndex, 0)
            XCTAssertEqual(reloaded.popoverOrder[flowIndex - 1], .divider(added))
        } else {
            XCTFail("Expected a divider at the end of the order")
        }
        reloaded.removePopoverDivider(id: stacked)
        XCTAssertFalse(reloaded.popoverOrder.contains(.divider(stacked)))
        defaults.removePersistentDomain(forName: suite)
    }

    func testPreviousDefaultPopoverOrderGainsDividersOnce() {
        let suite = "MacPower.PopoverDividerMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(AppSettings.previousDefaultPopoverOrder, forKey: "popoverOrder")
        defaults.set(3, forKey: "settingsDefaultsRevision")
        let migrated = AppSettings(defaults: defaults)
        assertDividersBetweenEveryBlock(migrated.popoverOrder)
        XCTAssertEqual(defaults.integer(forKey: "settingsDefaultsRevision"), 4)

        let dividerIDs = migrated.popoverOrder.compactMap { entry -> UUID? in
            if case .divider(let id) = entry { return id }
            return nil
        }
        for id in dividerIDs {
            migrated.removePopoverDivider(id: id)
        }
        XCTAssertEqual(migrated.popoverOrder.map(\.rawValue), AppSettings.previousDefaultPopoverOrder)
        let again = AppSettings(defaults: defaults)
        XCTAssertEqual(again.popoverOrder.map(\.rawValue), AppSettings.previousDefaultPopoverOrder)
        XCTAssertFalse(again.popoverOrder.contains(where: \.isDivider))
        defaults.removePersistentDomain(forName: suite)
    }

    func testCustomPopoverOrderKeepsItsDividers() {
        let suite = "MacPower.PopoverDividerCustom.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let reordered = ["flow", "rings", "topApps", "lowPower", "localIP", "batteryCycle", "settings"]
        defaults.set(reordered, forKey: "popoverOrder")
        defaults.set(3, forKey: "settingsDefaultsRevision")
        let custom = AppSettings(defaults: defaults)
        XCTAssertEqual(custom.popoverOrder.map(\.rawValue), reordered)
        XCTAssertEqual(defaults.integer(forKey: "settingsDefaultsRevision"), 4)

        let kept = UUID()
        defaults.removePersistentDomain(forName: suite)
        defaults.set(3, forKey: "settingsDefaultsRevision")
        defaults.set(
            [PopoverBlock.rings.rawValue, PopoverEntry.divider(kept).rawValue]
                + PopoverBlock.allCases.dropFirst().map(\.rawValue),
            forKey: "popoverOrder"
        )
        let withDivider = AppSettings(defaults: defaults)
        XCTAssertEqual(withDivider.popoverOrder.filter(\.isDivider).count, 1)
        XCTAssertTrue(withDivider.popoverOrder.contains(.divider(kept)))
        defaults.removePersistentDomain(forName: suite)
    }

    private func assertDividersBetweenEveryBlock(
        _ order: [PopoverEntry],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(order.count, PopoverBlock.allCases.count * 2 - 1, file: file, line: line)
        for (index, block) in PopoverBlock.allCases.enumerated() {
            XCTAssertEqual(order[index * 2], .block(block), file: file, line: line)
            if index > 0 {
                XCTAssertTrue(order[index * 2 - 1].isDivider, file: file, line: line)
            }
        }
    }

    private func assertSingleDividerBetweenVisibleBlocks(
        _ rendered: [PopoverEntry],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(rendered.first?.isDivider == true, file: file, line: line)
        XCTAssertFalse(rendered.last?.isDivider == true, file: file, line: line)
        var previousWasDivider = false
        for entry in rendered {
            if entry.isDivider {
                XCTAssertFalse(previousWasDivider, file: file, line: line)
                previousWasDivider = true
            } else {
                previousWasDivider = false
            }
        }
        let blocks = rendered.filter { !$0.isDivider }.count
        let dividers = rendered.filter(\.isDivider).count
        XCTAssertEqual(dividers, max(blocks - 1, 0), file: file, line: line)
    }

    func testTopAppSamplingSettingsPersistAndClamp() {
        let suite = "MacPower.TopAppSampling.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.topAppWindowMinutes, 3)
        XCTAssertEqual(first.topAppIntervalSeconds, 30)
        XCTAssertEqual(first.topAppLimit, 3)
        first.topAppWindowMinutes = 12
        first.topAppIntervalSeconds = 30
        first.topAppLimit = 8
        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.topAppWindowMinutes, 12)
        XCTAssertEqual(second.topAppIntervalSeconds, 30)
        XCTAssertEqual(second.topAppLimit, 8)
        second.topAppWindowMinutes = 0
        second.topAppIntervalSeconds = 500
        second.topAppLimit = 40
        XCTAssertEqual(second.topAppWindowMinutes, 1)
        XCTAssertEqual(second.topAppIntervalSeconds, 120)
        XCTAssertEqual(second.topAppLimit, 12)
        defaults.removePersistentDomain(forName: suite)
    }

    func testLowPowerButtonSettingsPersistAndClamp() {
        let suite = "MacPower.LowPowerButtons.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.lowPowerButtonLayout, .fitTwoPerRow)
        XCTAssertEqual(first.lowPowerButtonVisibility, .both)
        XCTAssertTrue(LowPowerButtonVisibility.allCases.allSatisfy { $0.showsStrategy || $0.showsLowPower })

        first.lowPowerButtonLayout = .alwaysOnePerRow
        first.lowPowerButtonVisibility = .strategy
        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.lowPowerButtonLayout, .alwaysOnePerRow)
        XCTAssertEqual(second.lowPowerButtonVisibility, .strategy)
        second.lowPowerButtonVisibility = .lowPower
        let savedLowPowerOnly = AppSettings(defaults: defaults)
        XCTAssertEqual(savedLowPowerOnly.lowPowerButtonVisibility, .lowPower)

        defaults.set("none", forKey: "lowPowerButtonVisibility")
        defaults.set("diagonal", forKey: "lowPowerButtonLayout")
        let clamped = AppSettings(defaults: defaults)
        XCTAssertEqual(clamped.lowPowerButtonLayout, .fitTwoPerRow)
        XCTAssertEqual(clamped.lowPowerButtonVisibility, .both)
        XCTAssertEqual(defaults.string(forKey: "lowPowerButtonLayout"), LowPowerButtonLayout.fitTwoPerRow.rawValue)
        XCTAssertEqual(defaults.string(forKey: "lowPowerButtonVisibility"), LowPowerButtonVisibility.both.rawValue)

        let wideLabels = ["性能", "节能"]
        XCTAssertTrue(
            LowPowerButtonRowLayout.placesSideBySide(
                layout: .fitTwoPerRow,
                visibility: .both,
                strategyLabels: wideLabels,
                lowPowerLabel: "低电量",
                panelWidth: 2_000
            )
        )
        XCTAssertFalse(
            LowPowerButtonRowLayout.placesSideBySide(
                layout: .alwaysOnePerRow,
                visibility: .both,
                strategyLabels: wideLabels,
                lowPowerLabel: "低电量",
                panelWidth: 2_000
            )
        )
        XCTAssertFalse(
            LowPowerButtonRowLayout.placesSideBySide(
                layout: .fitTwoPerRow,
                visibility: .strategy,
                strategyLabels: wideLabels,
                lowPowerLabel: "低电量",
                panelWidth: 2_000
            )
        )
        XCTAssertEqual(
            Localization.string("settings.tab.lowPower", language: .simplifiedChinese),
            "能耗模式"
        )
        XCTAssertEqual(
            Localization.string("settings.lowPower.layout.fit", language: .simplifiedChinese),
            "长度允许下两个一行"
        )
        XCTAssertEqual(
            Localization.string("settings.lowPower.layout.stack", language: .simplifiedChinese),
            "永远一个一行"
        )
        XCTAssertEqual(
            Localization.string("settings.lowPower.buttons.both", language: .simplifiedChinese),
            "都出现"
        )
        XCTAssertEqual(
            Localization.string("settings.lowPower.buttons.strategy", language: .simplifiedChinese),
            "仅策略"
        )
        XCTAssertEqual(
            Localization.string("settings.lowPower.buttons.now", language: .simplifiedChinese),
            "仅低电量"
        )
        let keys = [
            "settings.tab.lowPower",
            "settings.lowPower.layout",
            "settings.lowPower.layout.fit",
            "settings.lowPower.layout.stack",
            "settings.lowPower.buttons",
            "settings.lowPower.buttons.both",
            "settings.lowPower.buttons.strategy",
            "settings.lowPower.buttons.now",
        ]
        for language in AppLanguage.allCases where language != .system {
            for key in keys {
                XCTAssertNotEqual(
                    Localization.string(key, language: language),
                    key,
                    "\(language.rawValue) \(key)"
                )
            }
        }
        defaults.removePersistentDomain(forName: suite)
    }

    func testLowPowerTextColumnMatchesButtonChrome() {
        let side = LowPowerButtonRowLayout.textColumnWidth(panelWidth: 420, sideBySide: true)
        XCTAssertEqual(side, 142)
        let stacked = LowPowerButtonRowLayout.textColumnWidth(panelWidth: 420, sideBySide: false)
        XCTAssertEqual(stacked, 342)
        XCTAssertFalse(LowPowerButtonRowLayout.labelFits("性能", width: 0, maxLines: 2))
    }

    func testLowPowerStrategyMayUseTwoLinesButNotThree() {
        let column = LowPowerButtonRowLayout.textColumnWidth(panelWidth: PopoverLayout.width, sideBySide: true)
        XCTAssertFalse(LowPowerButtonRowLayout.labelFits("Low Power when plugged in", width: column, maxLines: 1))
        XCTAssertTrue(LowPowerButtonRowLayout.labelFits("Low Power when plugged in", width: column, maxLines: 2))
        XCTAssertTrue(
            LowPowerButtonRowLayout.prefersSideBySide(
                strategyLabels: ["性能", "节能", "仅使用电池时节能", "仅接通电源时节能"],
                lowPowerLabel: "低电量",
                panelWidth: PopoverLayout.width
            )
        )
        let tooLong = String(repeating: "仅接通电源时节能", count: 8)
        XCTAssertFalse(
            LowPowerButtonRowLayout.prefersSideBySide(
                strategyLabels: ["性能", tooLong],
                lowPowerLabel: "低电量",
                panelWidth: PopoverLayout.width
            )
        )
        XCTAssertFalse(
            LowPowerButtonRowLayout.prefersSideBySide(
                strategyLabels: ["性能"],
                lowPowerLabel: String(repeating: "低电量", count: 30),
                panelWidth: PopoverLayout.width
            )
        )
    }

    func testChineseStrategyButtonNamesStayOnOneLine() {
        let width = PopoverLayout.width(ringCount: 8, twoRows: true, includesSettings: false)
        let column = LowPowerButtonRowLayout.textColumnWidth(panelWidth: width, sideBySide: true)
        XCTAssertFalse(
            LowPowerButtonRowLayout.labelFits("仅使用电池时节能", width: column, maxLines: 1)
        )
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese] {
            for preset in LowPowerPreset.allCases {
                let label = Localization.string(preset.shortLocalizationKey, language: language)
                XCTAssertTrue(
                    LowPowerButtonRowLayout.labelFits(label, width: column, maxLines: 1),
                    "\(language.rawValue) \(label) width \(column)"
                )
            }
        }
    }

    func testChineseLowPowerButtonsStaySideBySide() {
        let narrow = PopoverLayout.width(ringCount: 2, twoRows: false)
        XCTAssertLessThan(narrow, PopoverLayout.width)
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese] {
            let strategies = LowPowerPreset.allCases.map {
                Localization.string($0.localizationKey, language: language)
            }
            let now = Localization.string("popover.lowPower.now", language: language)
            for width in [PopoverLayout.width, narrow] {
                XCTAssertTrue(
                    LowPowerButtonRowLayout.prefersSideBySide(
                        strategyLabels: strategies,
                        lowPowerLabel: now,
                        panelWidth: width
                    ),
                    "\(language.rawValue) \(width)"
                )
            }
        }
    }

    func testLowPowerRowReflowsWhenThePanelNarrows() {
        let strategies = LowPowerPreset.allCases.map {
            Localization.string($0.localizationKey, language: .english)
        }
        let now = Localization.string("popover.lowPower.now", language: .english)
        XCTAssertTrue(
            LowPowerButtonRowLayout.prefersSideBySide(
                strategyLabels: strategies,
                lowPowerLabel: now,
                panelWidth: PopoverLayout.width
            )
        )
        XCTAssertFalse(
            LowPowerButtonRowLayout.prefersSideBySide(
                strategyLabels: strategies,
                lowPowerLabel: now,
                panelWidth: PopoverLayout.width(ringCount: 2, twoRows: false)
            )
        )
        for language in AppLanguage.allCases where language != .system {
            let labels = LowPowerPreset.allCases.map {
                Localization.string($0.localizationKey, language: language)
            }
            let lowPower = Localization.string("popover.lowPower.now", language: language)
            XCTAssertFalse(labels.contains { $0.hasPrefix("popover.lowPower.") })
            XCTAssertFalse(lowPower.hasPrefix("popover.lowPower."))
            XCTAssertTrue(
                LowPowerButtonRowLayout.prefersSideBySide(
                    strategyLabels: labels,
                    lowPowerLabel: lowPower,
                    panelWidth: 2_000
                ),
                language.rawValue
            )
            XCTAssertFalse(
                LowPowerButtonRowLayout.prefersSideBySide(
                    strategyLabels: labels,
                    lowPowerLabel: lowPower,
                    panelWidth: 80
                ),
                language.rawValue
            )
        }
    }

    func testLocalIPFilterHonorsScopeAndFamily() {
        let interfaces = [
            LocalIPInterfaceAddress(interfaceName: "Wi-Fi", address: "192.168.1.10"),
            LocalIPInterfaceAddress(interfaceName: "Wi-Fi", address: "2001:db8::10"),
            LocalIPInterfaceAddress(interfaceName: "Ethernet", address: "10.0.0.2"),
            LocalIPInterfaceAddress(interfaceName: "lo0", address: "127.0.0.1"),
            LocalIPInterfaceAddress(interfaceName: "lo0", address: "::1"),
            LocalIPInterfaceAddress(interfaceName: "en0", address: "169.254.1.1"),
            LocalIPInterfaceAddress(interfaceName: "awdl0", address: "fe80::1"),
            LocalIPInterfaceAddress(interfaceName: "bridge0", address: "172.16.5.1"),
            LocalIPInterfaceAddress(interfaceName: "bridge0", address: "8.8.8.8"),
        ]
        let defaults = LocalIPFilter.rows(
            interfaces: interfaces,
            scopes: [.local],
            families: [.ipv4, .ipv6]
        )
        XCTAssertEqual(
            defaults.map(\.address),
            ["192.168.1.10", "2001:db8::10", "10.0.0.2", "172.16.5.1"]
        )
        XCTAssertTrue(defaults.allSatisfy { $0.scope == .local && $0.failed == false })
        XCTAssertEqual(defaults.map(\.family), [.ipv4, .ipv6, .ipv4, .ipv4])

        let ipv4Only = LocalIPFilter.rows(
            interfaces: interfaces,
            scopes: [.local, .publicAddress, .loopback, .linkLocal],
            families: [.ipv4],
            publicIPv4: "203.0.113.10",
            publicIPv6: "2001:db8::50",
            publicIPv6Failed: true
        )
        XCTAssertFalse(ipv4Only.contains { $0.family == .ipv6 })
        XCTAssertEqual(
            ipv4Only.map(\.address),
            ["192.168.1.10", "10.0.0.2", "172.16.5.1", "203.0.113.10", "127.0.0.1", "169.254.1.1"]
        )

        let withPublic = LocalIPFilter.rows(
            interfaces: interfaces,
            scopes: [.local, .publicAddress],
            families: [.ipv4, .ipv6],
            publicIPv4: "203.0.113.10",
            publicIPv6: "2001:db8::10"
        )
        XCTAssertEqual(withPublic.filter { $0.scope == .publicAddress }.map(\.address), ["203.0.113.10", "2001:db8::10"])
        XCTAssertFalse(withPublic.contains { $0.scope == .local && $0.address == "2001:db8::10" })
        XCTAssertTrue(withPublic.contains { $0.scope == .local && $0.address == "192.168.1.10" })

        let hiddenPublic = LocalIPFilter.rows(
            interfaces: interfaces,
            scopes: [.local],
            families: [.ipv4, .ipv6],
            publicIPv4: "203.0.113.10"
        )
        XCTAssertFalse(hiddenPublic.contains { $0.scope == .publicAddress })

        let failedPublic = LocalIPFilter.rows(
            interfaces: [],
            scopes: [.publicAddress],
            families: [.ipv4],
            publicIPv4Failed: true
        )
        XCTAssertEqual(failedPublic.count, 1)
        XCTAssertTrue(failedPublic[0].failed)
        XCTAssertEqual(failedPublic[0].scope, .publicAddress)

        let cachedPublic = LocalIPFilter.rows(
            interfaces: [],
            scopes: [.publicAddress],
            families: [.ipv4],
            publicIPv4: "198.51.100.8",
            publicIPv4Failed: true
        )
        XCTAssertEqual(cachedPublic.map(\.address), ["198.51.100.8"])
        XCTAssertFalse(cachedPublic[0].failed)
    }

    func testLocalIPSettingsPersist() {
        let suite = "MacPower.LocalIP.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        XCTAssertTrue(first.showLocalIP)
        XCTAssertEqual(first.ipScopes, Set(IPAddressScope.allCases))
        XCTAssertEqual(first.ipFamilies, [.ipv4])
        first.showLocalIP = false
        first.ipScopes = [.publicAddress, .loopback]
        first.ipFamilies = [.ipv6]
        let second = AppSettings(defaults: defaults)
        XCTAssertFalse(second.showLocalIP)
        XCTAssertEqual(second.ipScopes, [.publicAddress, .loopback])
        XCTAssertEqual(second.ipFamilies, [.ipv6])
        defaults.removePersistentDomain(forName: suite)
    }

    func testScopeColumnWidthFollowsTheLabelsItIsGiven() {
        let local = LocalIPRowLayout.scopeColumnWidth(labels: ["本地"])
        let mixed = LocalIPRowLayout.scopeColumnWidth(labels: ["本地", "链路本地"])
        XCTAssertGreaterThan(local, 0)
        XCTAssertGreaterThan(mixed, local)
        XCTAssertEqual(local, LocalIPRowLayout.textWidth("本地", font: LocalIPRowLayout.labelFont).rounded(.up))
    }

    func testLocalIPInterfaceNameAbbreviation() {
        XCTAssertEqual(LocalIPRowLayout.abbreviatedInterfaceName("Wi-Fi"), "Wi-Fi")
        XCTAssertEqual(LocalIPRowLayout.abbreviatedInterfaceName("en0"), "en0")
        XCTAssertEqual(LocalIPRowLayout.abbreviatedInterfaceName("abcd"), "abcd")
        XCTAssertEqual(LocalIPRowLayout.abbreviatedInterfaceName("abcde"), "abcde")
        XCTAssertEqual(LocalIPRowLayout.abbreviatedInterfaceName("feth691"), "fe…91")
        XCTAssertEqual(LocalIPRowLayout.abbreviatedInterfaceName("utun1500"), "ut…00")
    }

    func testLocalIPAddressWrapsOntoAnotherLine() {
        let address = "240e:b8f:b13:701:842:edcc:5239:e612"
        let wide = LocalIPRowLayout.presentation(
            interfaceName: "Wi-Fi",
            address: address,
            wrapsAddress: true,
            scopeColumnWidth: 48,
            panelWidth: 2_000
        )
        XCTAssertEqual(wide.interfaceName, "Wi-Fi")
        XCTAssertEqual(wide.address, address)

        let narrow = LocalIPRowLayout.presentation(
            interfaceName: "feth691",
            address: address,
            wrapsAddress: true,
            scopeColumnWidth: 80,
            panelWidth: PopoverLayout.width(ringCount: 3, twoRows: false)
        )
        XCTAssertTrue(narrow.address.contains("\n"))
        XCTAssertEqual(narrow.address.replacingOccurrences(of: "\n", with: ""), address)
        XCTAssertFalse(narrow.address.contains("…"))

        let ipv4 = LocalIPRowLayout.presentation(
            interfaceName: "Wi-Fi",
            address: "192.168.3.19",
            wrapsAddress: false,
            scopeColumnWidth: 80,
            panelWidth: 220
        )
        XCTAssertEqual(ipv4.address, "192.168.3.19")
        XCTAssertEqual(ipv4.interfaceName, "Wi-Fi")
    }

    func testBatteryTemperatureCurveMatchesNetworkRing() {
        XCTAssertEqual(BatteryTemperatureFormat.ringPercent(celsius: 30), 50, accuracy: 0.0001)
        XCTAssertLessThan(BatteryTemperatureFormat.ringPercent(celsius: 20), 50)
        XCTAssertGreaterThan(BatteryTemperatureFormat.ringPercent(celsius: 40), 50)
        XCTAssertEqual(BatteryTemperatureFormat.ringPercent(celsius: 0), 0)
        XCTAssertEqual(BatteryTemperatureFormat.ringPercent(celsius: -4), 0)
        XCTAssertEqual(BatteryTemperatureFormat.celsius(raw: 3409) ?? 0, 34.09, accuracy: 0.001)
        XCTAssertEqual(BatteryTemperatureFormat.celsius(raw: 310) ?? 0, 31, accuracy: 0.001)
        XCTAssertNil(BatteryTemperatureFormat.celsius(raw: 0))
        XCTAssertNil(BatteryTemperatureFormat.celsius(raw: -10))
        XCTAssertEqual(BatteryTemperatureFormat.caption(celsius: 31.4), "31°C")
        let megabyte = 1024.0 * 1024.0
        XCTAssertEqual(NetworkRateFormat.ringPercent(bytesPerSecond: megabyte), 50, accuracy: 0.001)
        XCTAssertLessThan(
            NetworkRateFormat.ringPercent(bytesPerSecond: megabyte, centerBytesPerSecond: megabyte * 2),
            50
        )
        XCTAssertEqual(
            NetworkRateFormat.ringPercent(bytesPerSecond: megabyte * 2, centerBytesPerSecond: megabyte * 2),
            50,
            accuracy: 0.001
        )
        XCTAssertEqual(BatteryTemperatureFormat.ringPercent(celsius: 40, centerCelsius: 40), 50, accuracy: 0.001)
        XCTAssertEqual(
            MacThermalState.fair.ringPercent(nominal: 10, fair: 40, serious: 70, critical: 100),
            40,
            accuracy: 0.001
        )
    }

    func testRingMidpointsPersist() {
        let suite = "MacPower.RingMidpoint.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.downloadHalfKilobytes, 1024)
        XCTAssertEqual(first.uploadHalfKilobytes, 1024)
        XCTAssertEqual(first.temperatureHalfCelsius, 30)
        XCTAssertEqual(first.thermalNominalPercent, 25)
        XCTAssertEqual(first.thermalCriticalPercent, 100)
        first.downloadHalfKilobytes = 2048
        first.temperatureHalfCelsius = 35
        first.thermalNominalPercent = 10
        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.downloadHalfKilobytes, 2048)
        XCTAssertEqual(second.temperatureHalfCelsius, 35)
        XCTAssertEqual(second.thermalNominalPercent, 10)
        defaults.removePersistentDomain(forName: suite)
    }

    func testBatteryCapacityPercentUsesFullOverDesign() {
        let percent = BatteryCapacityFormat.percent(fullChargeMilliAmpHours: 4626, designMilliAmpHours: 6075)
        XCTAssertEqual(percent ?? 0, 4626.0 / 6075.0 * 100, accuracy: 0.001)
        XCTAssertNil(BatteryCapacityFormat.percent(fullChargeMilliAmpHours: 4626, designMilliAmpHours: 0))
        XCTAssertEqual(
            BatteryCapacityFormat.fullChargeMilliAmpHours(nominal: 4626, appleRawMax: 4476, fullCharge: 4476),
            4626
        )
        XCTAssertEqual(
            BatteryCapacityFormat.fullChargeMilliAmpHours(nominal: nil, appleRawMax: 4476, fullCharge: 4000),
            4476
        )
        XCTAssertNil(BatteryCapacityFormat.fullChargeMilliAmpHours(nominal: nil, appleRawMax: nil, fullCharge: nil))
        XCTAssertEqual(
            BatteryCapacityFormat.detail(fullChargeMilliAmpHours: 4626, designMilliAmpHours: 6075),
            "76% · 4626/6075 mAh"
        )
        XCTAssertEqual(
            BatteryCapacityFormat.text(fullChargeMilliAmpHours: 4626, designMilliAmpHours: 6075, style: .percent),
            "76%"
        )
        XCTAssertEqual(
            BatteryCapacityFormat.text(fullChargeMilliAmpHours: 4626, designMilliAmpHours: 6075, style: .milliampHours),
            "4626/6075 mAh"
        )
    }

    func testBatteryCapacityStylePersists() {
        let suite = "MacPower.BatteryCapacityStyle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.batteryCapacityStyle, .both)
        first.batteryCapacityStyle = .percent
        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.batteryCapacityStyle, .percent)
        defaults.set("nope", forKey: "batteryCapacityStyle")
        let third = AppSettings(defaults: defaults)
        XCTAssertEqual(third.batteryCapacityStyle, .both)
        defaults.removePersistentDomain(forName: suite)
    }

    func testBatteryTemperatureRingStaysOffUntilEnabled() {
        let suite = "MacPower.BatteryTemperatureRing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.ringCatalog.contains(.batteryTemperature))
        XCTAssertFalse(settings.ringOrder.contains(.batteryTemperature))
        XCTAssertTrue(settings.showBatteryCycle)
        settings.setRingSlot(.batteryTemperature, visible: true)
        XCTAssertTrue(settings.ringOrder.contains(.batteryTemperature))
        defaults.removePersistentDomain(forName: suite)
    }

    func testThermalStateLevelMapsToRingFillAndCaption() {
        XCTAssertEqual(MacThermalState.nominal.ringPercent, 25, accuracy: 0.001)
        XCTAssertEqual(MacThermalState.fair.ringPercent, 50, accuracy: 0.001)
        XCTAssertEqual(MacThermalState.serious.ringPercent, 75, accuracy: 0.001)
        XCTAssertEqual(MacThermalState.critical.ringPercent, 100, accuracy: 0.001)
        XCTAssertEqual(MacThermalState(.nominal), .nominal)
        XCTAssertEqual(MacThermalState(.fair), .fair)
        XCTAssertEqual(MacThermalState(.serious), .serious)
        XCTAssertEqual(MacThermalState(.critical), .critical)

        let captions: [AppLanguage: [MacThermalState: String]] = [
            .german: [.nominal: "Normal", .fair: "Erhöht", .serious: "Ernst", .critical: "Kritisch"],
            .english: [.nominal: "Nominal", .fair: "Fair", .serious: "Serious", .critical: "Critical"],
            .spanish: [.nominal: "Normal", .fair: "Elevado", .serious: "Grave", .critical: "Crítico"],
            .french: [.nominal: "Normal", .fair: "Élevé", .serious: "Grave", .critical: "Critique"],
            .italian: [.nominal: "Normale", .fair: "Elevato", .serious: "Grave", .critical: "Critico"],
            .japanese: [.nominal: "正常", .fair: "高め", .serious: "深刻", .critical: "危険"],
            .korean: [.nominal: "정상", .fair: "높음", .serious: "심각", .critical: "위험"],
            .brazilianPortuguese: [.nominal: "Normal", .fair: "Elevado", .serious: "Grave", .critical: "Crítico"],
            .russian: [.nominal: "Норма", .fair: "Повышен", .serious: "Серьёзно", .critical: "Критично"],
            .simplifiedChinese: [.nominal: "正常", .fair: "偏高", .serious: "严重", .critical: "危急"],
            .traditionalChinese: [.nominal: "正常", .fair: "偏高", .serious: "嚴重", .critical: "危急"],
        ]
        for (language, expected) in captions {
            for (level, caption) in expected {
                let shown = Localization.string(level.captionKey, language: language)
                XCTAssertEqual(shown, caption)
                XCTAssertFalse(shown.contains("°"))
            }
        }

        let suite = "MacPower.ThermalStateRing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(["battery", "cpu", "gpu"], forKey: "visibleRings")
        defaults.set(true, forKey: "ringOrderMigrated")
        let restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.ringCatalog.contains(.thermalState))
        XCTAssertTrue(restored.ringOrder.contains(.thermalState))
        XCTAssertFalse(restored.ringOrder.contains(.batteryTemperature))
        restored.setRingSlot(.thermalState, visible: false)
        let hidden = AppSettings(defaults: defaults)
        XCTAssertFalse(hidden.ringOrder.contains(.thermalState))
        defaults.removePersistentDomain(forName: suite)
    }
}
