import XCTest
@testable import RWLabsArchitecture

private final class StubErrorService: ErrorService {
    func handleError(_ error: Error) {}
}

// MARK: - One model per way a link can stop

@Component
final class WarnLeafModel: ComponentModel<WarnLeafModel> {
    struct State {}
}

/// Handles steps itself, but not this one
@Component
final class WarnHandlerModel: ComponentModel<WarnHandlerModel>, DeepLinkStepHandler {
    struct State {}
    func openDeepLinkStep(_ step: DeepLinkStep) -> (any ViewModel)? { nil }
}

/// Has a destination enum that isn't DeepLinkable
@Component
final class WarnPlainModel: ComponentModel<WarnPlainModel> {
    struct State {}
    enum Destination { case leaf(WarnLeafModel.State) }
}

/// DeepLinkable, but written without @Component and without HasConnections
final class WarnNoConnectionsModel: ComponentModel<WarnNoConnectionsModel> {
    typealias Action = EmptyAction
    typealias Output = EmptyOutput
    struct State: ViewModelState {
        var isLoading = false
        var error: (any Error)?
        var destination: Destination?
    }
    @CasePathable @DeepLinkable
    enum Destination: ViewModelDestination { case leaf(WarnLeafModel.State) }
}
extension WarnNoConnectionsModel: ComponentTypes {}

/// HasConnections, but its case connection is never touched, so the walker can't see it
final class WarnUntouchedModel: ComponentModel<WarnUntouchedModel>, HasConnections {
    typealias Action = EmptyAction
    typealias Output = EmptyOutput
    struct State: ViewModelState {
        var isLoading = false
        var error: (any Error)?
        var destination: Destination?
    }
    @CasePathable @DeepLinkable
    enum Destination: ViewModelDestination { case leaf(WarnLeafModel.State) }

    lazy var connections = Connections(parent: self)
    final class Connections: ViewModelConnections<WarnUntouchedModel> {
        lazy var leaf = Connection<WarnLeafModel>().connect(state: \.destination, case: \.leaf, parent: nil as WarnUntouchedModel?)
    }
}
extension WarnUntouchedModel: ComponentTypes {}

/// The working shape, for comparison
@Component
final class WarnGoodModel: ComponentModel<WarnGoodModel> {
    struct State {}
    @DeepLinkable
    enum Destination { case leaf(WarnLeafModel.State) }
    final class Connections: ConnectionsBase {
        lazy var leaf = Connection<WarnLeafModel>().connect(state: \.destination, case: \.leaf, parent: parent)
    }
}

@MainActor
final class DeepLinkWarningTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
    }

    private func reason(_ name: String, on model: any ViewModel, file: StaticString = #filePath, line: UInt = #line) -> String {
        switch DeepLinkWalker.open(DeepLinkStep(name: name, queryItems: [:]), on: model) {
        case .opened:
            XCTFail("expected the link to stop", file: file, line: line)
            return ""
        case .stopped(let reason):
            return reason
        }
    }

    func testHandlerThatReturnsNil() {
        let text = reason("leaf", on: WarnHandlerModel(initialState: .init()))
        XCTAssertTrue(text.contains("WarnHandlerModel.openDeepLinkStep(_:) returned nil"), text)
    }

    func testDestinationThatIsntDeepLinkable() {
        let text = reason("leaf", on: WarnPlainModel(initialState: .init()))
        XCTAssertTrue(text.contains("WarnPlainModel.Destination isn't DeepLinkable"), text)
    }

    func testUnknownCase() {
        let text = reason("nope", on: WarnGoodModel(initialState: .init()))
        XCTAssertTrue(text.contains("WarnGoodModel.Destination has no case for it"), text)
    }

    func testModelWithoutHasConnections() {
        let model = WarnNoConnectionsModel(initialState: .init())
        let text = reason("leaf", on: model)
        XCTAssertTrue(text.contains("WarnNoConnectionsModel doesn't adopt HasConnections"), text)
        XCTAssertNotNil(model.destination)   // the step before the failure stays open
    }

    func testConnectionTheWalkerCantSee() {
        let text = reason("leaf", on: WarnUntouchedModel(initialState: .init()))
        XCTAssertTrue(text.contains("no case connection in WarnUntouchedModel.Connections created its child"), text)
    }

    func testWorkingModelOpens() {
        let model = WarnGoodModel(initialState: .init())
        guard case .opened(let child) = DeepLinkWalker.open(DeepLinkStep(name: "leaf", queryItems: [:]), on: model) else {
            return XCTFail("expected the link to open")
        }
        XCTAssertTrue(child is WarnLeafModel)
    }
}
