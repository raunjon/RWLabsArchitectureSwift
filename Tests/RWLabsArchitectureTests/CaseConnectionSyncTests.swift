import XCTest
import Combine
import CasePaths
@testable import RWLabsArchitecture

private final class StubErrorService: ErrorService {
    func handleError(_ error: Error) {}
}

private final class Child: ComponentModel<Child> {
    typealias Output = EmptyOutput
    struct State: ViewModelState {
        var name = ""
        var isLoading = false
        var error: Error?
        var destination: EmptyDestination?
    }
    enum Action: ViewModelAction { case rename(String) }
    override func send(_ action: Action) {
        switch action {
        case .rename(let name): self.name = name
        }
    }
}

private final class Parent: ComponentModel<Parent> {
    typealias Output = EmptyOutput
    @CasePathable
    enum Destination: ViewModelDestination {
        case child(Child.State)
    }
    struct State: ViewModelState {
        var title = ""
        var isLoading = false
        var error: Error?
        var destination: Destination?
    }
    enum Action: ViewModelAction { case none }
    lazy var connections = Connections(parent: self)
    final class Connections: ViewModelConnections<Parent> {
        lazy var child = Connection<Child>()
            .connect(state: \.destination, case: \.child, parent: parent)
        override func setupConnections() { _ = child }
    }
    override func send(_ action: Action) {}

    var childName: String? {
        guard case .child(let state)? = state.destination else { return nil }
        return state.name
    }
}

@MainActor
final class CaseConnectionSyncTests: XCTestCase {
    override func setUp() async throws {
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
    }

    private func drainMainQueue(_ turns: Int = 5) async {
        for _ in 0..<turns {
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        }
    }

    private func makeActive(name: String) async throws -> (Parent, Child) {
        let parent = Parent(initialState: .init())
        _ = parent.connections
        parent.state.destination = .child(.init(name: name))
        await drainMainQueue()
        let child = try XCTUnwrap(parent.connections.child.model)
        XCTAssertEqual(child.state.name, name)
        return (parent, child)
    }

    func testChildEditReachesParent() async throws {
        let (parent, child) = try await makeActive(name: "a")
        child.send(.rename("b"))
        await drainMainQueue()
        XCTAssertEqual(parent.childName, "b")
    }

    func testParentPayloadUpdateReachesActiveChild() async throws {
        let (parent, child) = try await makeActive(name: "a")
        parent.state.destination = .child(.init(name: "c"))
        await drainMainQueue()
        XCTAssertEqual(child.state.name, "c")
        XCTAssertTrue(parent.connections.child.model === child, "same child instance should be reused")
    }

    func testNoSyncLoop() async throws {
        let (parent, child) = try await makeActive(name: "a")
        var parentChanges = 0
        var childChanges = 0
        let p = parent.objectWillChange.sink { _ in parentChanges += 1 }
        let c = child.objectWillChange.sink { _ in childChanges += 1 }
        child.send(.rename("b"))
        await drainMainQueue(20)
        XCTAssertEqual(childChanges, 1, "child should change once (the edit)")
        XCTAssertEqual(parentChanges, 1, "parent should change once (the sync)")
        _ = (p, c)
    }

    func testUnrelatedParentChangeDoesNotOverwritePendingChildEdit() async throws {
        let (parent, child) = try await makeActive(name: "a")
        child.send(.rename("typed"))
        parent.state.title = "unrelated"      // same turn, before the child's edit has synced
        await drainMainQueue()
        XCTAssertEqual(child.state.name, "typed")
        XCTAssertEqual(parent.childName, "typed")
    }

    func testDismissDeactivates() async throws {
        let (parent, _) = try await makeActive(name: "a")
        parent.state.destination = nil
        await drainMainQueue()
        XCTAssertNil(parent.connections.child.model)
    }
}

extension Child: ComponentTypes {}
extension Parent: ComponentTypes {}
