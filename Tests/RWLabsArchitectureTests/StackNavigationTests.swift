import XCTest
import SwiftUI
@testable import RWLabsArchitecture

private final class StubErrorService: ErrorService {
    func handleError(_ error: Error) {}
}

// A screen that can push or present another of itself, and show an inline child

@Component
final class StackScreen: ComponentModel<StackScreen> {
    struct State {
        var name = ""
        var banner: StackLeaf.State?
        var tab = StackLeaf.State()
    }

    indirect enum Destination: RouteDestinationPresentable {
        case pushed(StackScreen.State)
        case sheet(StackScreen.State)

        var presentationStyle: PresentationStyle {
            switch self {
            case .pushed: .push
            case .sheet:  .modal
            }
        }
    }

    final class Connections: ConnectionsBase {
        lazy var pushed = Connection<StackScreen>().connect(state: \.destination, case: \.pushed, parent: parent)
        lazy var sheet = Connection<StackScreen>().connect(state: \.destination, case: \.sheet, parent: parent)
        lazy var banner = Connection<StackLeaf>().connect(state: \.banner, parent: parent)
        lazy var tab: StackLeaf = Connection<StackLeaf>().connect(from: parent!, to: \.tab)
    }

    func push(_ name: String) -> StackScreen {
        destination = .pushed(.init(name: name))
        return connections.pushed.model!
    }

    func present(_ name: String) -> StackScreen {
        destination = .sheet(.init(name: name))
        return connections.sheet.model!
    }
}

@Component
final class StackLeaf: ComponentModel<StackLeaf> {
    struct State {}
}

// A destination enum that doesn't declare styles, so the view's .push(…) has to say it

@Component
final class PlainScreen: ComponentModel<PlainScreen> {
    struct State {}
    enum Destination { case next(StackScreen.State) }

    final class Connections: ConnectionsBase {
        lazy var next = Connection<StackScreen>().connect(state: \.destination, case: \.next, parent: parent)
    }
}

@MainActor
final class StackNavigationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
    }

    // MARK: popToRoot

    func testPopToRootFromADeepScreenClearsTheRoot() {
        let root = StackScreen(initialState: .init(name: "root"))
        let c = root.push("a").push("b").push("c")

        c.popToRoot()

        XCTAssertNil(root.destination)
        XCTAssertNil(root.connections.pushed.model)
    }

    func testPopToRootReleasesEveryPoppedScreen() {
        let root = StackScreen(initialState: .init())
        weak var a: StackScreen?
        weak var c: StackScreen?
        autoreleasepool {
            let first = root.push("a")
            let last = first.push("b").push("c")
            a = first
            c = last
            last.popToRoot()
            _ = root.connections.pushed.model   // the view's next read
        }
        XCTAssertNil(a)
        XCTAssertNil(c)
        XCTAssertTrue(root.childLinks.isEmpty)
    }

    func testPopToRootInsideASheetStaysInTheSheet() {
        let root = StackScreen(initialState: .init())
        let sheet = root.present("sheet")
        let deep = sheet.push("a").push("b")

        deep.popToRoot()

        XCTAssertNil(sheet.destination)
        XCTAssertEqual(root.destination?.id, "sheet")
        XCTAssertNotNil(root.connections.sheet.model)
    }

    func testPopToRootOnAStackRootPopsWhatItPushed() {
        let root = StackScreen(initialState: .init())
        _ = root.push("a").push("b")

        root.popToRoot()

        XCTAssertNil(root.destination)
    }

    func testPopToRootOnARootLeavesItsSheetOpen() {
        let root = StackScreen(initialState: .init())
        _ = root.present("sheet")

        root.popToRoot()

        XCTAssertEqual(root.destination?.id, "sheet")
    }

    func testPushHelperMarksAConnectionWhoseDestinationHasNoStyle() {
        let root = PlainScreen(initialState: .init())
        _ = EmptyView().push(root.connections.next) { _ in EmptyView() }   // what the view does
        root.destination = .next(.init())
        let child = root.connections.next.model!
        let deep = child.push("b")

        deep.popToRoot()

        XCTAssertNil(root.destination)
    }

    func testWithoutAKnownPushStylePopToRootStopsAtTheChild() {
        let root = PlainScreen(initialState: .init())   // no .push(…) marking
        root.destination = .next(.init())
        let child = root.connections.next.model!
        let deep = child.push("b")

        deep.popToRoot()

        XCTAssertNil(child.destination)
        XCTAssertNotNil(root.destination)
    }

    // MARK: close

    func testClosePopsOnlyThisScreen() {
        let root = StackScreen(initialState: .init())
        let a = root.push("a")
        let b = a.push("b")

        b.close()

        XCTAssertNil(a.destination)
        XCTAssertNotNil(root.destination)
    }

    func testCloseDismissesASheet() {
        let root = StackScreen(initialState: .init())
        let sheet = root.present("sheet")

        sheet.close()

        XCTAssertNil(root.destination)
    }

    func testCloseRemovesAnInlineOptionalChild() {
        let root = StackScreen(initialState: .init())
        root.state.banner = .init()
        let banner = root.connections.banner.model!

        banner.close()

        XCTAssertNil(root.state.banner)
        XCTAssertNil(root.connections.banner.model)
    }

    func testCloseDoesNothingForADirectChildOrARoot() {
        let root = StackScreen(initialState: .init())
        _ = root.push("a")

        root.connections.tab.close()
        root.close()

        XCTAssertNotNil(root.destination)
    }

    func testCloseFromAStaleChildDoesntClearANewerDestination() {
        let root = StackScreen(initialState: .init())
        let sheet = root.present("sheet")
        _ = root.push("a")                          // the sheet was replaced

        sheet.close()

        XCTAssertEqual(root.destination?.id, "pushed")
    }
}
