import XCTest
import CasePaths
@testable import RWLabsArchitecture

private final class StubErrorService: ErrorService {
    func handleError(_ error: Error) {}
}

// MARK: - A small app tree: tabs → list → detail → reviews

private final class ReviewsModel: ComponentModel<ReviewsModel.State, EmptyAction, EmptyOutput> {
    struct State: ViewModelState {
        var isLoading = false
        var error: Error?
        var destination: EmptyDestination?
    }
    override func send(_ action: EmptyAction) {}
}

private final class DetailModel: ComponentModel<DetailModel.State, EmptyAction, EmptyOutput>, HasConnections {
    struct State: ViewModelState {
        var itemId = ""
        var isLoading = false
        var error: Error?
        var destination: Destination?
    }
    @CasePathable
    enum Destination: ViewModelDestination {
        case reviews(ReviewsModel.State)
    }
    lazy var connections = Connections(parent: self)
    final class Connections: ViewModelConnections<DetailModel> {
        lazy var reviews = Connection<ReviewsModel>()
            .connect(state: \.destination, case: \.reviews, parent: parent)
        override func setupConnections() { _ = reviews }
    }
    override func send(_ action: EmptyAction) {}
}

extension DetailModel.Destination: DeepLinkable {
    init?(_ step: DeepLinkStep) {
        switch step.name {
        case "reviews": self = .reviews(.init())
        default: return nil
        }
    }
}

private final class ListModel: ComponentModel<ListModel.State, EmptyAction, EmptyOutput>, HasConnections {
    struct State: ViewModelState {
        var isLoading = false
        var error: Error?
        var destination: Destination?
    }
    @CasePathable
    enum Destination: ViewModelDestination {
        case detail(DetailModel.State)
    }
    lazy var connections = Connections(parent: self)
    final class Connections: ViewModelConnections<ListModel> {
        lazy var detail = Connection<DetailModel>()
            .connect(state: \.destination, case: \.detail, parent: parent)
        override func setupConnections() { _ = detail }
    }
    override func send(_ action: EmptyAction) {}
}

extension ListModel.Destination: DeepLinkable {
    init?(_ step: DeepLinkStep) {
        switch step.name {
        case "item":
            guard let id = step["id"] else { return nil }
            self = .detail(.init(itemId: id))
        default:
            return nil
        }
    }
}

private final class TabsModel: ComponentModel<TabsModel.State, EmptyAction, EmptyOutput> {
    enum Tab { case list, other }
    struct State: ViewModelState {
        var selectedTab: Tab = .other
        var list = ListModel.State()
        var isLoading = false
        var error: Error?
        var destination: EmptyDestination?
    }
    lazy var connections = Connections(parent: self)
    final class Connections: ViewModelConnections<TabsModel> {
        lazy var list: ListModel = Connection<ListModel>().connect(from: parent!, to: \.list)
    }
    override func send(_ action: EmptyAction) {}
}

extension TabsModel: DeepLinkStepHandler {
    func openDeepLinkStep(_ step: DeepLinkStep) -> (any ViewModel)? {
        switch step.name {
        case "list": state.selectedTab = .list; return connections.list
        default: return nil
        }
    }
}

// MARK: - Tests

@MainActor
final class DeepLinkTests: XCTestCase {
    override func setUp() async throws {
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
    }

    private func drainMainQueue(_ turns: Int = 5) async {
        for _ in 0..<turns {
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        }
    }

    private func detailState(_ list: ListModel) -> DetailModel.State? {
        guard case .detail(let state)? = list.state.destination else { return nil }
        return state
    }

    func testOpensEveryLevelOfACustomSchemeLink() async {
        let tabs = TabsModel(initialState: .init())
        XCTAssertTrue(tabs.openDeepLink(Route(url: URL(string: "myapp://list/item/reviews?id=42")!)))

        XCTAssertEqual(tabs.state.selectedTab, .list)
        let list = tabs.connections.list
        XCTAssertEqual(detailState(list)?.itemId, "42")
        let detail = list.connections.detail.model
        XCTAssertEqual(detail?.state.itemId, "42")
        guard case .reviews? = detail?.state.destination else { return XCTFail("reviews not opened") }
        XCTAssertNotNil(detail?.connections.reviews.model)

        // After the async syncs run, the parent's payload still agrees with the child
        await drainMainQueue()
        guard case .reviews? = detailState(list)?.destination else { return XCTFail("parent payload lost the child's destination") }
        XCTAssertEqual(list.connections.detail.model?.state.itemId, "42")
    }

    func testUniversalLinkOpensTheSameWay() {
        let tabs = TabsModel(initialState: .init())
        XCTAssertTrue(tabs.openDeepLink(Route(url: URL(string: "https://example.com/list/item?id=7")!)))
        XCTAssertEqual(tabs.connections.list.connections.detail.model?.state.itemId, "7")
    }

    func testStopsAtTheFirstUnknownSegmentAndKeepsEarlierSteps() {
        let tabs = TabsModel(initialState: .init())
        XCTAssertFalse(tabs.openDeepLink(Route(path: "/list/item/nope", queryItems: ["id": "1"])))
        XCTAssertEqual(tabs.state.selectedTab, .list)
        XCTAssertEqual(tabs.connections.list.connections.detail.model?.state.itemId, "1")
        XCTAssertNil(tabs.connections.list.connections.detail.model?.state.destination)
    }

    func testMissingParameterStops() {
        let tabs = TabsModel(initialState: .init())
        XCTAssertFalse(tabs.openDeepLink(Route(path: "/list/item")))
        XCTAssertNil(tabs.connections.list.state.destination)
    }

    func testLeafScreenRejectsExtraSegments() {
        let tabs = TabsModel(initialState: .init())
        XCTAssertFalse(tabs.openDeepLink(Route(path: "/list/item/reviews/more", queryItems: ["id": "1"])))
    }

    func testRelinkingTheSameCaseUpdatesTheOpenScreen() async {
        let tabs = TabsModel(initialState: .init())
        tabs.openDeepLink(Route(path: "/list/item", queryItems: ["id": "1"]))
        await drainMainQueue()
        XCTAssertTrue(tabs.openDeepLink(Route(path: "/list/item/reviews", queryItems: ["id": "2"])))
        await drainMainQueue()

        let list = tabs.connections.list
        XCTAssertEqual(list.connections.detail.model?.state.itemId, "2")
        XCTAssertEqual(detailState(list)?.itemId, "2")
        guard case .reviews? = detailState(list)?.destination else { return XCTFail("reviews not opened") }
    }

    func testEmptyPathOpensNothingAndSucceeds() {
        let tabs = TabsModel(initialState: .init())
        XCTAssertTrue(tabs.openDeepLink(Route(path: "/")))
        XCTAssertEqual(tabs.state.selectedTab, .other)
    }
}
