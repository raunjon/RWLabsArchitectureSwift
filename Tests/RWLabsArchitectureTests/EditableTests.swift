import XCTest
import RWLabsArchitecture

private final class StubErrorService: ErrorService {
    func handleError(_ error: Error) {}
}

struct EditedProfile: Identifiable, Hashable, Codable {
    var id = "p1"
    var name = "Ada"
    var age = 36
}

@Component
final class ProfileEditModel: ComponentModel<ProfileEditModel> {
    struct State: ItemEditingState {
        var item: Editable<EditedProfile>
    }
    enum Action { case revert, saved(EditedProfile), accept }

    override func send(_ action: Action) {
        switch action {
        case .revert:           revert()
        case .saved(let item):  commit(item)
        case .accept:           commit()
        }
    }
}

@MainActor
final class EditableTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
    }

    // MARK: Editable

    func testStartsUnmodified() {
        let editable = Editable(EditedProfile())
        XCTAssertFalse(editable.isModified)
        XCTAssertEqual(editable.id, "p1")
    }

    func testEditingTheDraftMarksItModifiedAndRevertUndoesIt() {
        var editable = Editable(EditedProfile())
        editable.draft.name = "Grace"
        XCTAssertTrue(editable.isModified)
        XCTAssertEqual(editable.original.name, "Ada")

        editable.revert()
        XCTAssertFalse(editable.isModified)
        XCTAssertEqual(editable.draft.name, "Ada")
    }

    func testChangingAValueBackIsNotAModification() {
        var editable = Editable(EditedProfile())
        editable.draft.age = 40
        editable.draft.age = 36
        XCTAssertFalse(editable.isModified)
    }

    func testCommitAcceptsTheDraft() {
        var editable = Editable(EditedProfile())
        editable.draft.name = "Grace"
        editable.commit()
        XCTAssertFalse(editable.isModified)
        XCTAssertEqual(editable.original.name, "Grace")
    }

    func testCommitSavedReplacesBoth() {
        var editable = Editable(EditedProfile())
        editable.draft.name = "Grace"
        editable.commit(EditedProfile(id: "p1", name: "Grace H.", age: 37))
        XCTAssertFalse(editable.isModified)
        XCTAssertEqual(editable.original.name, "Grace H.")
        XCTAssertEqual(editable.draft.age, 37)
    }

    func testCodableRoundTrip() throws {
        var editable = Editable(EditedProfile())
        editable.draft.name = "Grace"
        let decoded = try JSONDecoder().decode(Editable<EditedProfile>.self, from: JSONEncoder().encode(editable))
        XCTAssertEqual(decoded, editable)
        XCTAssertTrue(decoded.isModified)
    }

    // MARK: ItemEditingState

    func testDraftBindingEditsTheDraft() {
        let model = ProfileEditModel(initialState: .init(item: Editable(EditedProfile())))
        let name = model.binding(draft: \.name)

        name.wrappedValue = "Grace"

        XCTAssertEqual(model.item.draft.name, "Grace")
        XCTAssertEqual(model.item.original.name, "Ada")
        XCTAssertTrue(model.isModified)
    }

    func testModelRevert() {
        let model = ProfileEditModel(initialState: .init(item: Editable(EditedProfile())))
        model.binding(draft: \.age).wrappedValue = 50

        model.send(.revert)

        XCTAssertFalse(model.isModified)
        XCTAssertEqual(model.item.draft.age, 36)
    }

    func testModelCommitWithAndWithoutASavedItem() {
        let model = ProfileEditModel(initialState: .init(item: Editable(EditedProfile())))
        model.binding(draft: \.name).wrappedValue = "Grace"

        model.send(.accept)
        XCTAssertFalse(model.isModified)
        XCTAssertEqual(model.item.original.name, "Grace")

        model.send(.saved(EditedProfile(id: "p1", name: "Server", age: 1)))
        XCTAssertEqual(model.item.draft.name, "Server")
        XCTAssertFalse(model.isModified)
    }

    func testStateStillGetsTheGeneratedProperties() {
        let model = ProfileEditModel(initialState: .init(item: Editable(EditedProfile())))
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.destination)
    }
}
