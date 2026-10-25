import XCTest
@testable import RWLabsArchitecture

/// Records start/stop calls across services, in order
nonisolated(unsafe) private var events: [String] = []

private protocol AlphaService: Service {}
private protocol BetaService: Service {}
private protocol LazyService: Service {}
private protocol FactoryService: Service {}

private final class Recording: AlphaService, BetaService, LazyService, FactoryService {
    let name: String
    init(_ name: String) { self.name = name }
    func start() { events.append("start \(name)") }
    func stop() { events.append("stop \(name)") }
}

private final class StubErrorService: ErrorService {
    func handleError(_ error: Error) {}
}

@MainActor
final class ServiceLifecycleTests: XCTestCase {
    private let container = DependencyContainer.shared

    override func setUp() async throws {
        AppCoordinator.shared.teardown()
        container.clear()
        events = []
        container.registerSingleton(ErrorService.self, instance: StubErrorService())
    }

    override func tearDown() async throws {
        AppCoordinator.shared.teardown()
        AppCoordinator.shared.onConfigure = nil
    }

    func testStartsInRegistrationOrderAndStopsInReverse() {
        container.registerSingleton(AlphaService.self, instance: Recording("alpha"))
        container.registerSingleton(BetaService.self, instance: Recording("beta"))

        AppCoordinator.shared.configure()
        XCTAssertEqual(events, ["start alpha", "start beta"])

        AppCoordinator.shared.teardown()
        XCTAssertEqual(events, ["start alpha", "start beta", "stop beta", "stop alpha"])
    }

    func testOnConfigureRegistrationsAreStartedAndNotOverwritten() {
        let alpha = Recording("alpha")
        AppCoordinator.shared.onConfigure = {
            DependencyContainer.shared.registerSingleton(AlphaService.self, instance: alpha)
        }
        AppCoordinator.shared.configure()
        XCTAssertTrue(container.resolve(AlphaService.self) as AnyObject === alpha)
        XCTAssertEqual(events, ["start alpha"])
    }

    func testConfigureIfNeededDoesNotStartTwice() {
        container.registerSingleton(AlphaService.self, instance: Recording("alpha"))
        AppCoordinator.shared.configureIfNeeded()
        AppCoordinator.shared.configureIfNeeded()
        AppCoordinator.shared.configure()           // startServices is idempotent too
        XCTAssertEqual(events, ["start alpha"])
    }

    func testLazySingletonStartsWhenFirstResolvedAfterConfigure() {
        container.registerLazySingleton(LazyService.self) { Recording("lazy") }
        AppCoordinator.shared.configure()
        XCTAssertEqual(events, [], "not created, so not started")

        _ = container.resolve(LazyService.self)
        XCTAssertEqual(events, ["start lazy"])

        AppCoordinator.shared.teardown()
        XCTAssertEqual(events, ["start lazy", "stop lazy"])
    }

    func testFactoryServicesAreNotStarted() {
        container.register(FactoryService.self) { Recording("factory") }
        AppCoordinator.shared.configure()
        _ = container.resolve(FactoryService.self)
        XCTAssertEqual(events, [])
    }

    func testInstanceRegisteredUnderTwoTypesStartsOnce() {
        let shared = Recording("shared")
        container.registerSingleton(AlphaService.self, instance: shared)
        container.registerSingleton(BetaService.self, instance: shared)
        AppCoordinator.shared.configure()
        XCTAssertEqual(events, ["start shared"])
    }

    func testIsConfiguredFlag() {
        XCTAssertFalse(AppCoordinator.shared.isConfigured)
        AppCoordinator.shared.configure()
        XCTAssertTrue(AppCoordinator.shared.isConfigured)
        AppCoordinator.shared.teardown()
        XCTAssertFalse(AppCoordinator.shared.isConfigured)
    }
}
