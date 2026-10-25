import XCTest
import CasePaths
@testable import RWLabsArchitecture

// MARK: - Payload states (every property has a default, so `State()` works)

struct MacroItemState: ViewModelState {
    var itemId = ""
    var isLoading = false
    var error: Error?
    var destination: EmptyDestination?
}

struct MacroOrderState: ViewModelState {
    var orderId = 0
    var note: String?
    var isLoading = false
    var error: Error?
    var destination: EmptyDestination?
}

struct MacroSessionState: ViewModelState {
    var sessionId = UUID()
    var isLoading = false
    var error: Error?
    var destination: EmptyDestination?
}

struct MacroEmptyState: ViewModelState {
    var isLoading = false
    var error: Error?
    var destination: EmptyDestination?
}

// MARK: - The enum under test

@DeepLinkable
@CasePathable
enum MacroDestination: ViewModelDestination {
    @DeepLink("item", params: ["id": "itemId"])
    case detail(MacroItemState)

    @DeepLink(params: ["orderId": "orderId", "note": "note"])
    case order(MacroOrderState)

    @DeepLink(params: ["session": "sessionId"])
    case session(MacroSessionState)

    case settings(MacroEmptyState)

    case labeled(state: MacroEmptyState)

    case about

    @DeepLink(skip: true)
    case confirmDelete(MacroEmptyState)
}

// MARK: - A screen that uses it

final class MacroScreenModel: ComponentModel<MacroScreenModel>, HasConnections {
    typealias Action = EmptyAction
    typealias Output = EmptyOutput
    struct State: ViewModelState {
        var isLoading = false
        var error: Error?
        var destination: Destination?
    }

    @DeepLinkable
    @CasePathable
    enum Destination: ViewModelDestination {
        @DeepLink("item", params: ["id": "itemId"])
        case detail(MacroItemModel.State)
    }

    lazy var connections = Connections(parent: self)
    final class Connections: ViewModelConnections<MacroScreenModel> {
        lazy var detail = Connection<MacroItemModel>()
            .connect(state: \.destination, case: \.detail, parent: parent)
        override func setupConnections() { _ = detail }
    }
    override func send(_ action: EmptyAction) {}
}

final class MacroItemModel: ComponentModel<MacroItemModel> {
    typealias State = MacroItemState
    typealias Action = EmptyAction
    typealias Output = EmptyOutput
    override func send(_ action: EmptyAction) {}
}

private final class StubErrorService: ErrorService {
    func handleError(_ error: Error) {}
}

// MARK: - Tests

final class DeepLinkMacroTests: XCTestCase {
    private func step(_ name: String, _ query: [String: String] = [:]) -> DeepLinkStep {
        DeepLinkStep(name: name, queryItems: query)
    }

    func testRenamedCaseWithStringParam() {
        guard case .detail(let state)? = MacroDestination(step("item", ["id": "42"])) else { return XCTFail() }
        XCTAssertEqual(state.itemId, "42")
        XCTAssertNil(MacroDestination(step("detail", ["id": "42"])), "the case name isn't linkable once renamed")
    }

    func testMissingRequiredParamFails() {
        XCTAssertNil(MacroDestination(step("item")))
    }

    func testIntParamIsConvertedAndOptionalParamMayBeMissing() {
        guard case .order(let state)? = MacroDestination(step("order", ["orderId": "7"])) else { return XCTFail() }
        XCTAssertEqual(state.orderId, 7)
        XCTAssertNil(state.note)

        guard case .order(let withNote)? = MacroDestination(step("order", ["orderId": "7", "note": "hi"])) else { return XCTFail() }
        XCTAssertEqual(withNote.note, "hi")

        XCTAssertNil(MacroDestination(step("order", ["orderId": "seven"])), "doesn't convert to Int")
    }

    func testUUIDParam() {
        let id = UUID()
        guard case .session(let state)? = MacroDestination(step("session", ["session": id.uuidString])) else { return XCTFail() }
        XCTAssertEqual(state.sessionId, id)
        XCTAssertNil(MacroDestination(step("session", ["session": "not-a-uuid"])))
    }

    func testCaseNameIsTheDefaultURLName() {
        guard case .settings? = MacroDestination(step("settings")) else { return XCTFail() }
    }

    func testLabeledPayload() {
        guard case .labeled? = MacroDestination(step("labeled")) else { return XCTFail() }
    }

    func testCaseWithoutPayload() {
        guard case .about? = MacroDestination(step("about")) else { return XCTFail() }
    }

    func testSkippedAndUnknownNames() {
        XCTAssertNil(MacroDestination(step("confirmDelete")))
        XCTAssertNil(MacroDestination(step("nope")))
    }

    @MainActor
    func testMacroDestinationOpensThroughTheWalker() {
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
        let screen = MacroScreenModel(initialState: .init())
        XCTAssertTrue(screen.openDeepLink(Route(url: URL(string: "myapp://item?id=9")!)))
        XCTAssertEqual(screen.connections.detail.model?.state.itemId, "9")
    }
}

extension MacroScreenModel: ComponentTypes {}
extension MacroItemModel: ComponentTypes {}
