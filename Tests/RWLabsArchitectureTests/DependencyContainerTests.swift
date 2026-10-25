import XCTest
@testable import RWLabsArchitecture

// Two different types that share the name `Logger`
private enum FeatureA { final class Logger { let name = "A" } }
private enum FeatureB { final class Logger { let name = "B" } }

private final class Counter {}
private final class LazyThing {
    nonisolated(unsafe) static var made = 0
    init() { LazyThing.made += 1 }
}
private typealias Handler = () -> Int

final class DependencyContainerTests: XCTestCase {
    private let container = DependencyContainer.shared

    func testFactoryReturnsNewInstanceEachTime() {
        container.register(Counter.self) { Counter() }
        XCTAssertFalse(container.resolve(Counter.self) === container.resolve(Counter.self))
    }

    func testSingletonReturnsSameInstance() {
        let counter = Counter()
        container.registerSingleton(Counter.self, instance: counter)
        XCTAssertTrue(container.resolve(Counter.self) === counter)
        XCTAssertTrue(container.resolve(Counter.self) === counter)
    }

    func testLazySingletonIsBuiltOnceOnFirstResolve() {
        LazyThing.made = 0
        container.registerLazySingleton(LazyThing.self) { LazyThing() }
        XCTAssertEqual(LazyThing.made, 0, "not built at registration")
        let first = container.resolve(LazyThing.self)
        let second = container.resolve(LazyThing.self)
        XCTAssertEqual(LazyThing.made, 1)
        XCTAssertTrue(first === second)
    }

    func testTypesWithTheSameNameDoNotCollide() {
        container.registerSingleton(FeatureA.Logger.self, instance: FeatureA.Logger())
        container.registerSingleton(FeatureB.Logger.self, instance: FeatureB.Logger())
        XCTAssertEqual(container.resolve(FeatureA.Logger.self).name, "A")
        XCTAssertEqual(container.resolve(FeatureB.Logger.self).name, "B")
    }

    func testClosureTypedSingletonIsReturnedNotCalled() {
        container.registerSingleton(Handler.self, instance: { 42 })
        let handler = container.resolve(Handler.self)
        XCTAssertEqual(handler(), 42)
    }

    func testProtocolRegisteredAsProtocolResolves() {
        final class Stub: ErrorService { func handleError(_ error: Error) {} }
        let stub = Stub()
        container.registerSingleton(ErrorService.self, instance: stub)
        XCTAssertTrue(container.resolve(ErrorService.self) as AnyObject === stub)
    }

    func testFactoryCanResolveOtherDependencies() {
        container.registerSingleton(Counter.self, instance: Counter())
        container.register(FeatureA.Logger.self) {
            _ = DependencyContainer.shared.resolve(Counter.self)   // nested resolve under the lock
            return FeatureA.Logger()
        }
        XCTAssertEqual(container.resolve(FeatureA.Logger.self).name, "A")
    }

    func testUnregisteredResolvesToNil() {
        final class NeverRegistered {}
        XCTAssertNil(container.resolveOptional(NeverRegistered.self))
    }
}
