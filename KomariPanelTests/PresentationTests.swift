import XCTest
@testable import KomariPanel

final class PresentationTests: XCTestCase {
    @MainActor func testLegacyIconPreferencesAlwaysRestorePrimaryAndKeepAppTheme() async throws {
        for legacyMode in ["light", "dark", "system", "invalid"] {
            for appMode in AppearanceMode.allCases {
                let suite = "IconMigrationTests.\(UUID().uuidString)"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                defaults.set(legacyMode, forKey: "iconAppearance")
                defaults.set(appMode.rawValue, forKey: "appAppearance")
                let client = TestAppIconClient(name: "AppIconDark")
                let controller = AppIconController(app: client, defaults: defaults)

                let restored = await controller.restoreSystemIcon()

                XCTAssertTrue(restored)
                XCTAssertNil(client.alternateIconName)
                XCTAssertEqual(client.restoreCount, 1)
                XCTAssertNil(defaults.object(forKey: "iconAppearance"))
                XCTAssertEqual(defaults.string(forKey: "appAppearance"), appMode.rawValue)
                let repeated = await controller.restoreSystemIcon()
                XCTAssertTrue(repeated)
                XCTAssertEqual(client.restoreCount, 1, "Already-primary launches must not prompt again")
            }
        }
    }

    @MainActor func testPrimaryIconNeedsNoSwitchEvenWhenAlternatesAreUnsupported() async throws {
        let suite = "IconMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("dark", forKey: "iconAppearance")
        let client = TestAppIconClient(name: nil)
        client.supportsAlternateIcons = false
        let controller = AppIconController(app: client, defaults: defaults)

        let restored = await controller.restoreSystemIcon()

        XCTAssertTrue(restored)
        XCTAssertEqual(client.restoreCount, 0)
        XCTAssertNil(defaults.object(forKey: "iconAppearance"))
        XCTAssertNil(controller.error)
    }

    @MainActor func testActualAlternateIsRestoredEvenWithoutLegacyPreference() async throws {
        let suite = "IconMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for name in ["AppIconLight", "AppIconDark", "UnexpectedLegacyIcon"] {
            let client = TestAppIconClient(name: name)
            let controller = AppIconController(app: client, defaults: defaults)
            let restored = await controller.restoreSystemIcon()
            XCTAssertTrue(restored)
            XCTAssertNil(client.alternateIconName)
            XCTAssertEqual(client.restoreCount, 1)
        }
    }

    @MainActor func testFailedMigrationRetainsPreferenceAndRetries() async throws {
        let suite = "IconMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("light", forKey: "iconAppearance")
        let client = TestAppIconClient(name: "AppIconLight")
        client.failure = NSError(domain: "IconMigrationTests", code: 1)
        let controller = AppIconController(app: client, defaults: defaults)

        let failed = await controller.restoreSystemIcon()

        XCTAssertFalse(failed)
        XCTAssertNotNil(controller.error)
        XCTAssertFalse(controller.busy)
        XCTAssertEqual(client.alternateIconName, "AppIconLight")
        XCTAssertEqual(defaults.string(forKey: "iconAppearance"), "light")
        client.failure = nil
        let retried = await controller.restoreSystemIcon()
        XCTAssertTrue(retried)
        XCTAssertNil(controller.error)
        XCTAssertNil(defaults.object(forKey: "iconAppearance"))
        XCTAssertEqual(client.restoreCount, 2)
    }

    @MainActor func testUnsupportedAndUnchangedIconDoNotCompleteMigration() async throws {
        let suite = "IconMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("dark", forKey: "iconAppearance")
        let client = TestAppIconClient(name: "AppIconDark")
        client.supportsAlternateIcons = false
        let controller = AppIconController(app: client, defaults: defaults)
        let unsupported = await controller.restoreSystemIcon()
        XCTAssertFalse(unsupported)
        XCTAssertEqual(client.restoreCount, 0)
        XCTAssertNotNil(controller.error)
        XCTAssertEqual(defaults.string(forKey: "iconAppearance"), "dark")

        client.supportsAlternateIcons = true
        client.leavesIconUnchanged = true
        let unchanged = await controller.restoreSystemIcon()
        XCTAssertFalse(unchanged)
        XCTAssertNotNil(controller.error)
        XCTAssertEqual(defaults.string(forKey: "iconAppearance"), "dark")
    }

    @MainActor func testConcurrentMigrationDoesNotIssueDuplicateRequests() async throws {
        let suite = "IconMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = TestAppIconClient(name: "AppIconDark")
        let controller = AppIconController(app: client, defaults: defaults)
        client.beforeRestore = {
            XCTAssertTrue(controller.busy)
            let duplicate = await controller.restoreSystemIcon()
            XCTAssertFalse(duplicate)
        }
        let restored = await controller.restoreSystemIcon()
        client.beforeRestore = nil
        XCTAssertTrue(restored)
        XCTAssertFalse(controller.busy)
        XCTAssertEqual(client.restoreCount, 1)
    }

    func testAverageUsesEveryTargetNotFirstSortedKey() throws {
        let p: JSON = .object([
            "z": .object(["latest": .number(90), "loss": .number(20)]),
            "a": .object(["latest": .number(10), "loss": .number(0)]),
            "b": .object(["latest": .number(50), "loss": .number(10)])
        ])
        let summary = PingSummary(p)
        // Dictionary iteration order can change the final IEEE-754 rounding bit.
        XCTAssertEqual(try XCTUnwrap(summary.averageLatency), 50, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(summary.averageLoss), 10, accuracy: 1e-9)
        XCTAssertEqual(summary.validCount, 3)
        XCTAssertFalse(summary.allTimedOut)
    }

    func testTimeoutMissingAndInvalidValuesAreNotZeroLatency() {
        let p: JSON = .object([
            "ok": .object(["latest": .number(80), "loss": .number(0)]),
            "timeout": .object(["latest": .number(-1), "loss": .number(100)]),
            "missing": .object([:]),
            "string": .object(["latest": .string("10"), "loss": .string("0")]),
            "nan": .object(["latest": .number(.nan), "loss": .number(.infinity)])
        ])
        let summary = PingSummary(p)
        XCTAssertEqual(summary.averageLatency, 80)
        XCTAssertEqual(summary.averageLoss, 50)
        XCTAssertEqual(summary.validCount, 1)
        XCTAssertEqual(summary.timeoutCount, 1)
        XCTAssertFalse(summary.allTimedOut)
    }

    func testNoSamplesAndAllTimeoutsAreDistinct() {
        XCTAssertNil(PingSummary(.null).averageLatency)
        XCTAssertNil(PingSummary(.object([:])).averageLoss)
        XCTAssertFalse(PingSummary(.null).allTimedOut)
        let timeouts = PingSummary(.object([
            "one": .object(["latest": .number(-1)]),
            "two": .object(["latest": .number(-1)])
        ]))
        XCTAssertNil(timeouts.averageLatency)
        XCTAssertTrue(timeouts.allTimedOut)
    }

    func testZeroIsAValidSampleAndLossMustBeAPercentage() {
        let summary = PingSummary(.object([
            "zero": .object(["latest": .number(0), "loss": .number(-1)]),
            "other": .object(["latest": .number(10), "loss": .number(101)])
        ]))
        XCTAssertEqual(summary.averageLatency, 5)
        XCTAssertNil(summary.averageLoss)
    }
}

@MainActor private final class TestAppIconClient: AppIconClient {
    var alternateIconName: String?
    var supportsAlternateIcons = true
    var restoreCount = 0
    var failure: Error?
    var leavesIconUnchanged = false
    var beforeRestore: (() async -> Void)?

    init(name: String?) { alternateIconName = name }

    func restorePrimaryIcon() async throws {
        restoreCount += 1
        await beforeRestore?()
        if let failure { throw failure }
        if !leavesIconUnchanged { alternateIconName = nil }
    }
}
