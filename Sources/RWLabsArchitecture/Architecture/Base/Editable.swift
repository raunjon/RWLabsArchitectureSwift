//
//  Editable.swift
//  RWLabsArchitecture
//
//  An item being edited: the original, the draft, and whether they differ
//

import SwiftUI

// MARK: - Editable

/// An item being edited on a detail or edit screen. Keeps the item as loaded (or last saved)
/// next to the user's draft, so the screen can tell whether anything changed and undo it.
///
/// ```swift
/// struct State { var profile: Editable<Profile> }
///
/// TextField("Name", text: model.binding(\.profile.draft.name))
/// Button("Save") { model.send(.save) }.disabled(!model.profile.isModified)
/// ```
///
/// It's a plain value, so it syncs through connections and can travel in a destination payload:
/// `destination = .edit(.init(profile: Editable(profile)))`.
public struct Editable<Item> {
    /// The item as loaded or last committed; changes only through `commit`
    public private(set) var original: Item
    /// What the user is editing; bind fields to it
    public var draft: Item

    public init(_ item: Item) {
        original = item
        draft = item
    }

    /// Sets the draft back to the original
    public mutating func revert() {
        draft = original
    }

    /// Accepts the draft as the new original, e.g. after saving it
    public mutating func commit() {
        original = draft
    }

    /// Replaces both with `saved`, e.g. what the server returned
    public mutating func commit(_ saved: Item) {
        original = saved
        draft = saved
    }
}

public extension Editable where Item: Equatable {
    /// `true` when the draft differs from the original
    var isModified: Bool { draft != original }
}

extension Editable: Identifiable where Item: Identifiable {
    /// The original item's id
    public var id: Item.ID { original.id }
}

extension Editable: Equatable where Item: Equatable {}
extension Editable: Hashable where Item: Hashable {}
extension Editable: Codable where Item: Codable {}
extension Editable: Sendable where Item: Sendable {}

// MARK: - ItemEditingState

/// A screen state that edits one item, stored as `item`. Models whose state adopts it get
/// `isModified`, `revert()`, `commit(_:)` and `binding(draft:)`.
///
/// ```swift
/// @Component
/// final class ProfileEditModel: ComponentModel<ProfileEditModel> {
///     struct State: ItemEditingState { var item: Editable<Profile> }
///     …
///     case .revert: revert()
///     case .save:
///         perform { [api, draft = state.item.draft] in try await api.save(draft) }
///         then: { [weak self] saved in self?.commit(saved) }
/// }
///
/// TextField("Name", text: model.binding(draft: \.name))
/// ```
///
/// For a screen that edits more than one item, use `Editable` properties directly instead.
public protocol ItemEditingState: ViewModelState {
    associatedtype Item: Equatable
    var item: Editable<Item> { get set }
}

public extension BaseViewModel where State: ItemEditingState {
    /// `true` when the item's draft differs from its original
    var isModified: Bool { state.item.isModified }

    /// Sets the draft back to the original
    func revert() {
        state.item.revert()
    }

    /// Accepts the draft as the new original, or replaces both with `saved`
    func commit(_ saved: State.Item? = nil) {
        if let saved {
            state.item.commit(saved)
        } else {
            state.item.commit()
        }
    }

    /// A binding to a property of the draft: `model.binding(draft: \.name)`
    func binding<T>(draft keyPath: WritableKeyPath<State.Item, T>) -> Binding<T> {
        let draft: WritableKeyPath<State, State.Item> = \.item.draft
        return binding(draft.appending(path: keyPath))
    }
}
