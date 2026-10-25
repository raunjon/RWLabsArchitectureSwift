import XCTest
import RWLabsArchitecture   // not @testable: generated members must work through the public API

private final class StubErrorService: ErrorService {
    func handleError(_ error: Error) {}
}

// A leaf model: no Destination, no Connections

@Component
final class MacroLeafModel: ComponentModel<MacroLeafModel.State, MacroLeafModel.Action, MacroLeafModel.Output> {
    struct State { var count = 0 }
    enum Action { case tap }
    enum Output { case tapped }

    override func send(_ action: Action) {
        state.count += 1
        sendOutput(.tapped)
    }
}

// A model with no Action or Output at all

@Component
final class MacroStaticModel: ComponentModel<MacroStaticModel.State, EmptyAction, EmptyOutput> {
    struct State {}
}

// A parent with every kind of child

@Component
final class MacroParentModel: ComponentModel<MacroParentModel.State, MacroParentModel.Action, MacroParentModel.Output> {
    struct State {
        var leaf = MacroLeafModel.State()
        var optionalLeaf: MacroLeafModel.State?
    }
    enum Destination {
        case detail(MacroLeafModel.State)
        case other
    }
    enum Action { case open, add }
    enum Output {}

    var leafTaps = 0

    final class Connections: ViewModelConnections<MacroParentModel> {
        lazy var leaf = Connection<MacroLeafModel> { [weak parent] _ in parent?.leafTaps += 1 }
            .connect(from: parent!, to: \.leaf)
        lazy var detail = Connection<MacroLeafModel>()
            .connect(state: \.destination, case: \.detail, parent: parent)
        lazy var optionalLeaf = Connection<MacroLeafModel>()
            .connect(state: \.optionalLeaf, parent: parent)
    }

    override func send(_ action: Action) {
        switch action {
        case .open: destination = .detail(.init(count: 7))
        case .add:  state.optionalLeaf = .init()
        }
    }
}

// Declaring things yourself overrides the generated versions

@Component
final class MacroCustomModel: ComponentModel<MacroCustomModel.State, MacroCustomModel.Action, MacroCustomModel.Output> {
    struct State: ViewModelState {
        var isLoading = true
        var error: (any Error)?
        var destination: Destination?
    }
    enum Destination: ViewModelDestination { case only }
    enum Action: ViewModelAction { case none }
    enum Output: ViewModelOutput {}

    var setupCalls = 0
    final class Connections: ViewModelConnections<MacroCustomModel> {
        override func setupConnections() { parent?.setupCalls += 1 }
    }

    override func send(_ action: Action) {}
}

@MainActor
final class ComponentMacroTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
    }

    private func drain() async {
        for _ in 0..<5 {
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        }
    }

    func testStateGetsTheRequiredProperties() {
        let model = MacroLeafModel(initialState: .init())
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.error)
        XCTAssertNil(model.destination)
        XCTAssertTrue(MacroLeafModel.Destination.self == EmptyDestination.self)
    }

    func testActionAndOutputConform() {
        let model = MacroLeafModel(initialState: .init())
        var received: [MacroLeafModel.Output] = []
        let cancellable = model.outputs.sink { received.append($0) }
        model.send(.tap)
        XCTAssertEqual(model.count, 1)
        XCTAssertEqual(received.count, 1)
        cancellable.cancel()
    }

    func testMissingTypesDefaultToEmpty() {
        _ = MacroStaticModel(initialState: .init())
        XCTAssertTrue(MacroStaticModel.Destination.self == EmptyDestination.self)
        XCTAssertTrue(MacroStaticModel.Action.self == EmptyAction.self)
        XCTAssertTrue(MacroStaticModel.Output.self == EmptyOutput.self)
    }

    func testDestinationIsCasePathable() {
        let destination = MacroParentModel.Destination.detail(.init(count: 3))
        XCTAssertEqual(destination[case: \.detail]?.count, 3)
        XCTAssertEqual(destination.id, "detail")
    }

    func testConnectionsPropertyAndHasConnections() {
        let model = MacroParentModel(initialState: .init())
        XCTAssertTrue((model as Any) is any HasConnections)
        XCTAssertIdentical(model.connections.parent, model)
    }

    func testDirectChildSyncsAndDeliversOutputs() async {
        let model = MacroParentModel(initialState: .init())
        model.connections.leaf.send(.tap)
        await drain()
        XCTAssertEqual(model.leaf.count, 1)
        XCTAssertEqual(model.leafTaps, 1)
    }

    func testCaseConnectionIsWiredFromInit() async {
        let model = MacroParentModel(initialState: .init())
        model.send(.open)
        await drain()
        XCTAssertEqual(model.connections.detail.model?.count, 7)
    }

    func testOptionalConnectionComesAndGoes() {
        let model = MacroParentModel(initialState: .init())
        model.send(.add)
        XCTAssertNotNil(model.connections.optionalLeaf.model)
        model.optionalLeaf = nil
        XCTAssertNil(model.connections.optionalLeaf.model)
    }

    func testDeepLinkWalkerFindsTheChild() {
        let model = MacroParentModel(initialState: .init())
        XCTAssertNotNil(model.connections)   // connections exist before any view reads them
        model.destination = .detail(.init())
        XCTAssertNotNil(model.connections.detail.model)
    }

    func testYourOwnDeclarationsWin() {
        let model = MacroCustomModel(initialState: .init())
        XCTAssertTrue(model.isLoading)
        _ = model.connections
        XCTAssertEqual(model.setupCalls, 1)
    }
}

// The header names Output, which @Component generates

@Component
final class MacroNoOutputModel: ComponentModel<MacroNoOutputModel.State, MacroNoOutputModel.Action, MacroNoOutputModel.Output> {
    struct State {}
    enum Action { case go }
    override func send(_ action: Action) {}
}

@MainActor
final class ComponentMacroHeaderTests: XCTestCase {
    func testGeneratedOutputCanBeNamedInTheHeader() {
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
        _ = MacroNoOutputModel(initialState: .init())
        XCTAssertTrue(MacroNoOutputModel.Output.self == EmptyOutput.self)
    }
}
