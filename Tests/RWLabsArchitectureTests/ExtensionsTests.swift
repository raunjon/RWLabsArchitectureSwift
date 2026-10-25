import XCTest
import SwiftUI
@testable import RWLabsArchitecture

private final class Box {
    var name = "box"
    var flag = true
}

final class ExtensionsTests: XCTestCase {
    func testOptionalStringOrEmptyUsesTheValue() {
        let id: String? = "abc"
        let missing: String? = nil
        XCTAssertEqual(id.orEmpty, "abc")
        XCTAssertEqual(missing.orEmpty, "")
    }

    func testCollectionHelpers() {
        let empty: [Int]? = []
        let none: [Int]? = nil
        let some: [Int]? = [1]
        XCTAssertTrue(empty.nilOrEmpty)
        XCTAssertTrue(none.nilOrEmpty)
        XCTAssertFalse(some.nilOrEmpty)
        XCTAssertNil(empty.content)
        XCTAssertEqual(some.content, [1])
    }

    func testIsNil() {
        let value: Int? = nil
        XCTAssertTrue((value as Any as? AnyOptional)?.isNil == true)
    }

    func testOrEmptyBindings() {
        var text: String? = nil
        var flag: Bool? = nil
        let textBinding = Binding(get: { text }, set: { text = $0 }).orEmpty()
        let flagBinding = Binding(get: { flag }, set: { flag = $0 }).orEmpty()
        XCTAssertEqual(textBinding.wrappedValue, "")
        XCTAssertFalse(flagBinding.wrappedValue)
        textBinding.wrappedValue = "typed"
        flagBinding.wrappedValue = true
        XCTAssertEqual(text, "typed")
        XCTAssertEqual(flag, true)
    }

    func testOrDefaultBinding() {
        var count: Int? = nil
        let binding = Binding(get: { count }, set: { count = $0 }).orDefault(7)
        XCTAssertEqual(binding.wrappedValue, 7)
        binding.wrappedValue = 3
        XCTAssertEqual(count, 3)
    }

    func testUnwrapOnOptionalObject() {
        var box: Box? = nil
        let binding = Binding(get: { box }, set: { box = $0 })
        XCTAssertEqual(binding.unwrap(\Box.name).wrappedValue, "")
        box = Box()
        binding.unwrap(\Box.name).wrappedValue = "renamed"
        XCTAssertEqual(box?.name, "renamed")
        XCTAssertTrue(binding.unwrap(\Box.flag).wrappedValue)
    }

    func testIsPresentBinding() {
        var item: Int? = 1
        let presented = Binding(get: { item }, set: { item = $0 }).isPresent()
        XCTAssertTrue(presented.wrappedValue)
        presented.wrappedValue = false
        XCTAssertNil(item)
    }
}
