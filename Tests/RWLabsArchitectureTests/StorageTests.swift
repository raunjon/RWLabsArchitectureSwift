import XCTest
import Combine
@testable import RWLabsArchitecture

private enum Keys: String { case theme }

private struct Profile: Codable, Equatable { var name: String }

private final class Settings {
    @Preference("count", default: 0) var count: Int
    @Preference("flag") var flag: Bool?
    @Preference(Keys.theme, default: "light") var theme: String
    @StoredObject("profile") var profile: Profile?
}

final class StorageTests: XCTestCase {
    private var suite: String!

    override func setUp() {
        suite = "rwlabs.tests.\(UUID().uuidString)"
        UserDefaults.appSuiteName = suite
    }

    override func tearDown() {
        UserDefaults.app.removePersistentDomain(forName: suite)
        UserDefaults.appSuiteName = nil
    }

    func testAppUsesTheConfiguredSuiteAndDefaultsToStandard() {
        UserDefaults.app.set("x", forKey: "probe")
        XCTAssertEqual(UserDefaults(suiteName: suite)?.string(forKey: "probe"), "x")
        XCTAssertNil(UserDefaults.standard.string(forKey: "probe"))

        UserDefaults.appSuiteName = nil
        XCTAssertTrue(UserDefaults.app === UserDefaults.standard)
    }

    func testPreferenceDefaultsAndOptionals() {
        let settings = Settings()
        XCTAssertEqual(settings.count, 0)
        XCTAssertNil(settings.flag)
        XCTAssertEqual(settings.theme, "light")

        settings.count = 3
        settings.flag = true
        settings.theme = "dark"
        XCTAssertEqual(Settings().count, 3)
        XCTAssertEqual(Settings().flag, true)
        XCTAssertEqual(UserDefaults.app.string(forKey: "theme"), "dark", "RawRepresentable key uses its raw value")

        settings.flag = nil
        XCTAssertNil(UserDefaults.app.object(forKey: "flag"), "setting nil removes the key")
    }

    func testStoredObjectRoundTripsAndNilRemovesTheKey() {
        let settings = Settings()
        settings.profile = Profile(name: "Ada")
        XCTAssertEqual(Settings().profile, Profile(name: "Ada"))

        settings.profile = nil
        XCTAssertNil(UserDefaults.app.object(forKey: "profile"))
        XCTAssertNil(Settings().profile)
    }

    func testMigrateCopiesOldSuiteAndKeepsExistingValues() {
        let oldName = "rwlabs.tests.old.\(UUID().uuidString)"
        let old = UserDefaults(suiteName: oldName)!
        old.set("token-123", forKey: "token")
        old.set("old", forKey: "theme")
        UserDefaults.app.set("new", forKey: "theme")

        XCTAssertEqual(UserDefaults.app.migrate(fromSuite: oldName), 1)
        XCTAssertEqual(UserDefaults.app.string(forKey: "token"), "token-123")
        XCTAssertEqual(UserDefaults.app.string(forKey: "theme"), "new", "existing values win")
        XCTAssertNil(UserDefaults(suiteName: oldName)?.persistentDomain(forName: oldName)?["token"])
    }
}

private struct WrapperBox {
    @Clamped(0...10) var rating = 5
    @Trimmed var name = ""
    @Debounced(delay: 0.05) var query = ""
    @Logged(name: "count") var count = 0
    @Copyable var text: NSMutableString = "a"
}

final class StateWrapperTests: XCTestCase {
    func testClamped() {
        var box = WrapperBox()
        box.rating = 42
        XCTAssertEqual(box.rating, 10)
        box.rating = -1
        XCTAssertEqual(box.rating, 0)
    }

    func testTrimmedKeepsWhatWasTypedAndProjectsTheTrimmedValue() {
        var box = WrapperBox()
        box.name = "  Ada "
        XCTAssertEqual(box.name, "  Ada ")
        XCTAssertEqual(box.$name, "Ada")
    }

    func testDebouncedEmitsOnlyTheSettledValue() {
        var box = WrapperBox()
        var received: [String] = []
        let settled = expectation(description: "settled")
        let cancellable = box.$query.sink { value in
            received.append(value)
            settled.fulfill()
        }
        box.query = "a"
        box.query = "ab"
        box.query = "abc"
        wait(for: [settled], timeout: 1)
        XCTAssertEqual(received, ["abc"], "initial value isn't emitted; only the last change is")
        _ = cancellable
    }

    func testLoggedStoresValues() {
        var box = WrapperBox()
        box.count = 2
        XCTAssertEqual(box.count, 2)
    }

    func testCopyableStoresACopy() {
        let original = NSMutableString(string: "x")
        var box = WrapperBox()
        box.text = original
        original.append("y")
        XCTAssertEqual(box.text, "x")
    }
}
