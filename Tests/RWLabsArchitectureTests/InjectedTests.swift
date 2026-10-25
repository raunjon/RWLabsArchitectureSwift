import XCTest
@testable import RWLabsArchitecture

private protocol Greeter { func greet() -> String }
private struct RealGreeter: Greeter { func greet() -> String { "real" } }
private struct FakeGreeter: Greeter { func greet() -> String { "fake" } }
private protocol NeverRegisteredService {}

private final class Owner {
    @Injected var greeter: Greeter
    @LazyInjected var lazyGreeter: Greeter
    @OptionalInjected var missing: NeverRegisteredService?
}

private final class LateOwner {
    @LazyInjected var greeter: Greeter
}

final class InjectedTests: XCTestCase {
    override func setUp() {
        DependencyContainer.shared.registerSingleton(Greeter.self, instance: RealGreeter())
    }

    func testInjectedResolvesAtInit() {
        XCTAssertEqual(Owner().greeter.greet(), "real")
    }

    func testOptionalInjectedIsNilWhenUnregistered() {
        XCTAssertNil(Owner().missing)
    }

    func testLazyInjectedResolvesOnFirstAccess() {
        let owner = LateOwner()                     // created before the "right" registration
        DependencyContainer.shared.registerSingleton(Greeter.self, instance: FakeGreeter())
        XCTAssertEqual(owner.greeter.greet(), "fake")
    }

    func testLazyInjectedCachesFirstValue() {
        let owner = LateOwner()
        XCTAssertEqual(owner.greeter.greet(), "real")
        DependencyContainer.shared.registerSingleton(Greeter.self, instance: FakeGreeter())
        XCTAssertEqual(owner.greeter.greet(), "real", "cached after first read")
    }

    func testSettersAllowSwappingInFakes() {
        let owner = Owner()
        owner.greeter = FakeGreeter()
        owner.lazyGreeter = FakeGreeter()
        XCTAssertEqual(owner.greeter.greet(), "fake")
        XCTAssertEqual(owner.lazyGreeter.greet(), "fake")
    }
}
