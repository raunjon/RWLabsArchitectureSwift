import XCTest
@testable import RWLabsArchitecture

/// Implements only the one required method, to prove the per-level methods come for free
private final class RecordingLogger: LoggerService, @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [(String, LogLevel, Bool)] = []
    var entries: [(String, LogLevel, Bool)] { lock.withLock { _entries } }
    func log(_ message: String, level: LogLevel, error: Error?, file: String, function: String, line: Int) {
        lock.withLock { _entries.append((message, level, error != nil)) }
    }
}

private struct SampleError: Error {}

final class LoggerTests: XCTestCase {
    private var logger: RecordingLogger!

    override func setUp() {
        logger = RecordingLogger()
        DependencyContainer.shared.registerSingleton(LoggerService.self, instance: logger)
    }

    func testPerLevelMethodsWorkThroughTheProtocol() {
        let service: LoggerService = logger
        service.info("hello")
        service.error("failed", error: SampleError())
        service.network("request")
        XCTAssertEqual(logger.entries.map(\.0), ["hello", "failed", "request"])
        XCTAssertEqual(logger.entries.map(\.1), [.info, .error, .network])
        XCTAssertEqual(logger.entries.map(\.2), [false, true, false])
    }

    func testLogFacadeWorksFromABackgroundThread() {
        let done = expectation(description: "logged off the main thread")
        DispatchQueue.global().async {
            Log.w("from background")
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(logger.entries.last?.0, "from background")
        XCTAssertEqual(logger.entries.last?.1, .warning)
    }

    func testLogFacadeDropsMessagesWhenNoLoggerIsRegistered() {
        DependencyContainer.shared.clear()
        Log.i("nobody listening")      // must not crash
        XCTAssertTrue(logger.entries.isEmpty)
    }
}

final class ValidationTests: XCTestCase {
    private let validation = DefaultValidationService()

    func testRequiredAndEmailOnEmptyGivesOneError() {
        XCTAssertEqual(validation.validate("", rules: [.required, .email]).errors, ["This field is required"])
    }

    func testOptionalFormatFieldsMayBeEmpty() {
        XCTAssertTrue(validation.validate(nil, rules: [.email]).isValid)
        XCTAssertTrue(validation.validate("  ", rules: [.phone]).isValid)
        XCTAssertTrue(validation.validate("", rules: [.minAge(18, dateFormat: "yyyy-MM-dd")]).isValid)
    }

    func testFormatRulesStillCheckNonEmptyValues() {
        XCTAssertFalse(validation.validate("not-an-email", rules: [.email]).isValid)
        XCTAssertTrue(validation.validate("a@b.co", rules: [.email]).isValid)
        XCTAssertFalse(validation.validate("123", rules: [.phone]).isValid)
    }

    func testMinAge() {
        let format = "yyyy-MM-dd"
        XCTAssertTrue(validation.validate("1990-01-01", rules: [.minAge(18, dateFormat: format)]).isValid)
        let recent = DateFormatter()
        recent.locale = Locale(identifier: "en_US_POSIX")
        recent.dateFormat = format
        let tenYearsAgo = Calendar(identifier: .gregorian).date(byAdding: .year, value: -10, to: Date())!
        XCTAssertFalse(validation.validate(recent.string(from: tenYearsAgo), rules: [.minAge(18, dateFormat: format)]).isValid)
        XCTAssertEqual(validation.validate("01/01/1990", rules: [.minAge(18, dateFormat: format)]).errors, ["Invalid date format."])
    }
}
