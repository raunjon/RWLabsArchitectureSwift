import XCTest
import RWLabsArchitecture

private final class StubErrorService: ErrorService {
    func handleError(_ error: Error) {}
}

/// `model.children.x` reads `model.connections.x`'s child, typed. Uses `MacroParentModel`
/// from ComponentMacroTests, which has a direct, a case and an optional connection.
@MainActor
final class ConnectedChildrenTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
    }

    func testDirectChildIsTheConnectedModel() {
        let parent = MacroParentModel(initialState: .init())
        let leaf: MacroLeafModel = parent.children.leaf
        XCTAssertTrue(leaf === parent.connections.leaf)
    }

    func testCaseChildFollowsTheDestination() {
        let parent = MacroParentModel(initialState: .init())
        XCTAssertNil(parent.children.detail)

        parent.send(.open)
        let detail: MacroLeafModel? = parent.children.detail
        XCTAssertEqual(detail?.count, 7)
        XCTAssertTrue(detail === parent.connections.detail.model)

        parent.dismiss()
        XCTAssertNil(parent.children.detail)
    }

    func testOptionalChildFollowsTheState() {
        let parent = MacroParentModel(initialState: .init())
        XCTAssertNil(parent.children.optionalLeaf)

        parent.send(.add)
        XCTAssertNotNil(parent.children.optionalLeaf)

        parent.state.optionalLeaf = nil
        XCTAssertNil(parent.children.optionalLeaf)
    }
}
