import XCTest
import SwiftUI
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

    // A view that holds `ComponentModel<MacroParentModel>` reaches the same connections

    func testBaseTypeReachesTheSameConnections() {
        let parent = MacroParentModel(initialState: .init())
        let base: ComponentModel<MacroParentModel> = parent
        XCTAssertIdentical(base.connections, parent.connections)
        XCTAssertIdentical(base.children.leaf, parent.connections.leaf)
    }

    func testBaseTypeCaseChildFollowsTheDestination() {
        let parent = MacroParentModel(initialState: .init())
        let base: ComponentModel<MacroParentModel> = parent
        XCTAssertNil(base.children.detail)

        base.send(.open)
        XCTAssertEqual(base.children.detail?.count, 7)
        XCTAssertIdentical(base.children.detail, parent.connections.detail.model)

        base.dismiss()
        XCTAssertNil(base.children.detail)
    }

    // `$model.children.x` is a binding, as a view's `@ObservedObject` projects it

    func testChildBindingThroughObservedObject() {
        let parent = MacroParentModel(initialState: .init())
        let observed = ObservedObject(wrappedValue: parent as ComponentModel<MacroParentModel>)
        let detail: Binding<MacroLeafModel?> = observed.projectedValue.children.detail
        XCTAssertNil(detail.wrappedValue)

        parent.send(.open)
        XCTAssertIdentical(detail.wrappedValue, parent.connections.detail.model)

        detail.wrappedValue = nil                               // a sheet being dismissed
        XCTAssertNil(parent.state.destination)
    }

    func testSettingAnOptionalChildToNilClearsItsState() {
        let parent = MacroParentModel(initialState: .init())
        parent.send(.add)
        XCTAssertNotNil(parent.state.optionalLeaf)

        parent.children.optionalLeaf = nil
        XCTAssertNil(parent.state.optionalLeaf)
    }

    // `push` and `present` take a child binding next to the connection overloads, unambiguously

    func testPushAndPresentAcceptChildBindings() {
        let view = ChildBindingView(model: MacroParentModel(initialState: .init()))
        XCTAssertNotNil(view)
    }
}

private struct ChildBindingView: View {
    @ObservedObject var model: ComponentModel<MacroParentModel>

    var body: some View {
        NavigationStack {
            Text("Parent")
                .push($model.children.detail) { _ in Text("Detail") }
                .present($model.children.optionalLeaf) { _ in Text("Sheet") }
                .push(model.connections.detail) { _ in Text("Connection") }
                .present(model.connections.optionalLeaf) { _ in Text("Connection sheet") }
        }
    }
}
