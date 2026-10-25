import XCTest
import Combine
import CasePaths
@testable import RWLabsArchitecture

private final class StubErrorService: ErrorService {
    func handleError(_ error: Error) {}
}

final class LifecycleChild: ComponentModel<LifecycleChild.State, LifecycleChild.Action, LifecycleChild.Output> {
    struct State: ViewModelState {
        var name = ""
        var isLoading = false
        var error: Error?
        var destination: EmptyDestination?
    }
    enum Action: ViewModelAction { case rename(String) }
    enum Output: ViewModelOutput { case renamed(String) }
    override func send(_ action: Action) {
        switch action {
        case .rename(let name):
            state.name = name
            sendOutput(.renamed(name))
        }
    }
}

final class LifecycleParent: ComponentModel<LifecycleParent.State, EmptyAction, EmptyOutput> {
    struct State: ViewModelState {
        var tab = LifecycleChild.State()
        var unrelated = 0
        var isLoading = false
        var error: Error?
        var destination: Destination?
    }
    @CasePathable
    enum Destination: ViewModelDestination {
        case sheet(LifecycleChild.State)
    }
    var lastOutput: String?
    lazy var connections = Connections(parent: self)
    final class Connections: ViewModelConnections<LifecycleParent> {
        lazy var tab: LifecycleChild = Connection<LifecycleChild> { [weak parent] output in
            if case .renamed(let name) = output { parent?.lastOutput = name }
        }
        .connect(from: parent!, to: \.tab)

        lazy var sheet = Connection<LifecycleChild>()
            .connect(state: \.destination, case: \.sheet, parent: parent)

        override func setupConnections() { _ = sheet }
    }
    override func send(_ action: EmptyAction) {}
}

@MainActor
final class ConnectionLifecycleTests: XCTestCase {
    override func setUp() async throws {
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
    }

    private func drainMainQueue(_ turns: Int = 5) async {
        for _ in 0..<turns {
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        }
    }

    // MARK: Direct connection sync

    func testDirectChildEditReachesParent() async {
        let parent = LifecycleParent(initialState: .init())
        let tab = parent.connections.tab
        tab.send(.rename("edited"))
        await drainMainQueue()
        XCTAssertEqual(parent.state.tab.name, "edited")
        XCTAssertEqual(parent.lastOutput, "edited", "output handler fires")
    }

    func testDirectParentChangeReachesChild() async {
        let parent = LifecycleParent(initialState: .init())
        let tab = parent.connections.tab
        parent.state.tab.name = "reset by parent"
        await drainMainQueue()
        XCTAssertEqual(tab.state.name, "reset by parent")
    }

    func testDirectSyncDoesNotLoop() async {
        let parent = LifecycleParent(initialState: .init())
        let tab = parent.connections.tab
        var parentChanges = 0
        var childChanges = 0
        let p = parent.objectWillChange.sink { _ in parentChanges += 1 }
        let c = tab.objectWillChange.sink { _ in childChanges += 1 }
        tab.send(.rename("once"))
        await drainMainQueue(20)
        XCTAssertEqual(childChanges, 1)
        XCTAssertEqual(parentChanges, 1)
        _ = (p, c)
    }

    func testUnrelatedParentChangeDoesNotOverwritePendingDirectEdit() async {
        let parent = LifecycleParent(initialState: .init())
        let tab = parent.connections.tab
        tab.send(.rename("typed"))
        parent.state.unrelated += 1
        await drainMainQueue()
        XCTAssertEqual(tab.state.name, "typed")
        XCTAssertEqual(parent.state.tab.name, "typed")
    }

    // MARK: Case connection reads

    func testCaseModelIsNilImmediatelyAfterTheDestinationIsCleared() {
        let parent = LifecycleParent(initialState: .init())
        parent.state.destination = .sheet(.init(name: "open"))
        XCTAssertNotNil(parent.connections.sheet.model)
        parent.state.destination = nil
        XCTAssertNil(parent.connections.sheet.model, "a re-render right after dismissal sees no child")
    }

    // MARK: Memory

    func testParentAndDirectChildAreFreed() async {
        weak var weakParent: LifecycleParent?
        weak var weakChild: LifecycleChild?
        do {
            let parent = LifecycleParent(initialState: .init())
            weakParent = parent
            weakChild = parent.connections.tab
        }
        await drainMainQueue()
        XCTAssertNil(weakParent, "parent leaked")
        XCTAssertNil(weakChild, "direct child leaked")
    }

    func testCaseConnectionAndItsChildAreFreed() async {
        weak var weakParent: LifecycleParent?
        weak var weakChild: LifecycleChild?
        weak var weakConnection: CaseConnection<LifecycleParent, LifecycleChild, LifecycleParent.Destination>?
        do {
            let parent = LifecycleParent(initialState: .init())
            parent.state.destination = .sheet(.init(name: "open"))
            weakParent = parent
            weakConnection = parent.connections.sheet
            weakChild = parent.connections.sheet.model
            XCTAssertNotNil(weakChild)
        }
        await drainMainQueue()
        XCTAssertNil(weakParent, "parent leaked")
        XCTAssertNil(weakConnection, "case connection leaked")
        XCTAssertNil(weakChild, "case child leaked")
    }
}
