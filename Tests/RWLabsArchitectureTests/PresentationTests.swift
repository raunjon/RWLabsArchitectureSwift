import XCTest
import SwiftUI
import CasePaths
@testable import RWLabsArchitecture

private final class StubErrorService: ErrorService {
    func handleError(_ error: Error) {}
}

final class SheetChildModel: ComponentModel<SheetChildModel.State, EmptyAction, EmptyOutput> {
    struct State: ViewModelState {
        var isLoading = false
        var error: Error?
        var destination: EmptyDestination?
    }
    override func send(_ action: EmptyAction) {}
}

final class PresentingModel: ComponentModel<PresentingModel.State, PresentingModel.Action, EmptyOutput> {
    struct State: ViewModelState {
        var choice: String?
        var isLoading = false
        var error: Error?
        var destination: Destination?
    }
    @CasePathable
    enum Destination: ViewModelDestination {
        case editor(SheetChildModel.State)
        case detail(SheetChildModel.State)
    }
    enum Action: ViewModelAction { case open }
    lazy var connections = Connections(parent: self)
    final class Connections: ViewModelConnections<PresentingModel> {
        lazy var editor = Connection<SheetChildModel>().connect(state: \.destination, case: \.editor, parent: parent)
        lazy var detail = Connection<SheetChildModel>().connect(state: \.destination, case: \.detail, parent: parent)
        override func setupConnections() { _ = editor; _ = detail }
    }
    override func send(_ action: Action) {}
}

/// Compile check: the helpers chain on any view, with or without `$`
@MainActor
private struct PresentingView: View {
    @ObservedObject var model: PresentingModel
    var body: some View {
        NavigationStack {
            Text("x")
                .navigationTitle("Title")
                .present(model.connections.editor) { _ in Text("editor") }
                .push(model.connections.detail) { _ in Text("detail") }
                .present($model.connections.editor) { _ in Text("editor") }
                .push($model.connections.detail, enableBackButton: false) { _ in Text("detail") }
                .presentAsBinding(item: .constant(nil as SheetChildModel?)) { _ in Text("optional") }
        }
    }
}

@MainActor
final class PresentationTests: XCTestCase {
    override func setUp() async throws {
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
    }

    func testDismissingTheSheetClearsTheParentsDestination() {
        let model = PresentingModel(initialState: .init())
        _ = model.connections
        model.state.destination = .editor(.init())
        let binding = model.connections.editor.bindingModel
        XCTAssertNotNil(binding.wrappedValue, "already-set destination is shown")

        binding.wrappedValue = nil                // what SwiftUI does on swipe-down / back
        XCTAssertNil(model.state.destination)
    }

    func testIsEqualSelectionBinding() {
        var choice: String? = nil
        let isA = Binding(get: { choice }, set: { choice = $0 }).isEqual(to: "a")
        XCTAssertFalse(isA.wrappedValue)
        isA.wrappedValue = true
        XCTAssertEqual(choice, "a")
        isA.wrappedValue = false
        XCTAssertNil(choice)
    }

    func testViewBuilds() {
        _ = PresentingView(model: PresentingModel(initialState: .init())).body
    }
}
