import XCTest
import SwiftUI
import CasePaths
@testable import RWLabsArchitecture

private final class StubErrorService: ErrorService {
    func handleError(_ error: Error) {}
}

final class OptionalDummyModel: ComponentModel<OptionalDummyModel.State, OptionalDummyModel.Action, OptionalDummyModel.Output> {
    struct State: ViewModelState {
        var note = ""
        var isLoading = false
        var error: (any Error)?
        var destination: EmptyDestination?
    }
    enum Action: ViewModelAction { case remove, write(String) }
    enum Output: ViewModelOutput { case removeMe }
    override func send(_ action: Action) {
        switch action {
        case .remove: sendOutput(.removeMe)
        case .write(let text): state.note = text
        }
    }
}

final class OptionalHostModel: ComponentModel<OptionalHostModel.State, OptionalHostModel.Action, EmptyOutput> {
    struct State: ViewModelState {
        var isLoading = false
        var error: (any Error)?
        var destination: EmptyDestination?
        var optionalDummyState: OptionalDummyModel.State?
    }
    enum Action: ViewModelAction { case addOptionalDummy }
    lazy var connections = Connections(parent: self)
    final class Connections: ViewModelConnections<OptionalHostModel> {
        lazy var optionalDummy = Connection<OptionalDummyModel> { [weak parent] output in
            guard let parent else { return }
            switch output {
            case .removeMe: parent.optionalDummyState = nil
            }
        }
        .connect(state: \.optionalDummyState, parent: parent)

        override func setupConnections() { _ = optionalDummy }
    }
    override func send(_ action: Action) {
        switch action {
        case .addOptionalDummy: self.optionalDummyState = .init()
        }
    }
}

/// Compile check: the optional form works with the presentation helpers and inline `if let`
@MainActor
private struct OptionalHostView: View {
    @ObservedObject var model: OptionalHostModel
    var body: some View {
        VStack {
            if let child = model.connections.optionalDummy.model {
                Text(child.note)
            }
        }
        .present(model.connections.optionalDummy) { Text($0.note) }
        .push($model.connections.optionalDummy) { Text($0.note) }
    }
}

@MainActor
final class OptionalStateConnectionTests: XCTestCase {
    override func setUp() async throws {
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
    }

    private func drainMainQueue(_ turns: Int = 5) async {
        for _ in 0..<turns {
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        }
    }

    func testChildExistsWhileTheStateIsSet() async {
        let host = OptionalHostModel(initialState: .init())
        XCTAssertNil(host.connections.optionalDummy.model)

        host.send(.addOptionalDummy)
        XCTAssertNotNil(host.connections.optionalDummy.model, "created from the state")

        host.connections.optionalDummy.model?.send(.remove)   // child asks the parent to remove it
        await drainMainQueue()
        XCTAssertNil(host.state.optionalDummyState)
        XCTAssertNil(host.connections.optionalDummy.model, "dropped with the state")
    }

    /// What a SwiftUI re-render sees: `model` read straight after the state changes,
    /// before the connection's main-queue observer has run
    func testModelReflectsTheStateImmediately() {
        let host = OptionalHostModel(initialState: .init())
        XCTAssertNil(host.connections.optionalDummy.model)

        host.send(.addOptionalDummy)
        XCTAssertNotNil(host.connections.optionalDummy.model, "shown as soon as the state is set")

        host.state.optionalDummyState = nil
        XCTAssertNil(host.connections.optionalDummy.model, "gone as soon as the state is cleared")

        host.send(.addOptionalDummy)
        XCTAssertNotNil(host.connections.optionalDummy.model, "can be added again")
    }

    func testRemovingThroughTheChildsOutputHidesItImmediately() {
        let host = OptionalHostModel(initialState: .init())
        host.send(.addOptionalDummy)
        host.connections.optionalDummy.model?.send(.remove)   // output handler sets the state to nil
        XCTAssertNil(host.connections.optionalDummy.model)
    }

    func testSyncsBothWays() async {
        let host = OptionalHostModel(initialState: .init())
        host.send(.addOptionalDummy)
        let child = host.connections.optionalDummy.model!

        child.send(.write("from child"))
        await drainMainQueue()
        XCTAssertEqual(host.state.optionalDummyState?.note, "from child")

        host.state.optionalDummyState?.note = "from parent"
        await drainMainQueue()
        XCTAssertEqual(child.state.note, "from parent")
        XCTAssertTrue(host.connections.optionalDummy.model === child, "same child kept")
    }

    func testDismissingThroughTheBindingClearsTheState() {
        let host = OptionalHostModel(initialState: .init())
        host.send(.addOptionalDummy)
        host.connections.optionalDummy.bindingModel.wrappedValue = nil
        XCTAssertNil(host.state.optionalDummyState)
    }

    func testViewBuilds() {
        _ = OptionalHostView(model: OptionalHostModel(initialState: .init())).body
    }

    func testHostAndChildAreFreed() async {
        weak var weakHost: OptionalHostModel?
        weak var weakChild: OptionalDummyModel?
        do {
            let host = OptionalHostModel(initialState: .init())
            host.send(.addOptionalDummy)
            weakHost = host
            weakChild = host.connections.optionalDummy.model
            XCTAssertNotNil(weakChild)
        }
        await drainMainQueue()
        XCTAssertNil(weakHost)
        XCTAssertNil(weakChild)
    }
}
