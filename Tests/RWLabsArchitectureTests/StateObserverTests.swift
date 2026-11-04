import XCTest
import Observation
@testable import RWLabsArchitecture

private final class StubErrorService: ErrorService {
    func handleError(_ error: Error) {}
}

/// Counts calls from a `StateObserver` handler
@MainActor
final class ChangeCounter {
    var count = 0
}

@Component
private final class Counter: ComponentModel<Counter> {
    struct State {
        var value = 0
    }
    enum Action { case increment }

    override func send(_ action: Action) {
        switch action {
        case .increment: state.value += 1
        }
    }
}

@MainActor
final class StateObserverTests: XCTestCase {
    override func setUp() async throws {
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
    }

    func testReportsEveryChangeInTheSameTurn() {
        let model = Counter(initialState: .init())
        let changes = ChangeCounter()
        let observer = StateObserver(model) { changes.count += 1 }
        model.send(.increment)
        model.send(.increment)
        model.state.value = 10
        XCTAssertEqual(changes.count, 3)
        _ = observer
    }

    func testReportsBeforeTheValueChanges() {
        let model = Counter(initialState: .init())
        var seen: [Int] = []
        let observer = StateObserver(model) { [unowned model] in
            MainActor.assumeIsolated { seen.append(model.state.value) }
        }
        model.send(.increment)
        XCTAssertEqual(seen, [0], "the handler runs before the new value is stored")
        XCTAssertEqual(model.state.value, 1)
        _ = observer
    }

    func testStopsAfterCancel() {
        let model = Counter(initialState: .init())
        let changes = ChangeCounter()
        let observer = StateObserver(model) { changes.count += 1 }
        model.send(.increment)
        observer.cancel()
        model.send(.increment)
        XCTAssertEqual(changes.count, 1)
    }

    func testStopsWhenFreed() {
        let model = Counter(initialState: .init())
        let changes = ChangeCounter()
        var observer: StateObserver? = StateObserver(model) { changes.count += 1 }
        model.send(.increment)
        observer = nil
        model.send(.increment)
        XCTAssertEqual(changes.count, 1)
        _ = observer
    }

    /// What SwiftUI relies on: reading a state property through dynamic member lookup is tracked
    func testDynamicMemberReadIsTracked() {
        let model = Counter(initialState: .init())
        let changed = ChangeCounter()
        withObservationTracking {
            _ = model.value
        } onChange: {
            MainActor.assumeIsolated { changed.count += 1 }
        }
        model.send(.increment)
        XCTAssertEqual(changed.count, 1)
    }
}
