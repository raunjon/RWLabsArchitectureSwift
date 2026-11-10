//
//  ViewModelConnections.swift
//  RWLabsArchitecture
//
//  The base class for a ViewModel's connections, and its protocols
//

import Foundation

// MARK: - ViewModelConnections

/// The base class for a ViewModel's `Connections`: one `lazy var` per child.
///
/// ```swift
/// lazy var connections = Connections(parent: self)
///
/// final class Connections: ViewModelConnections<ProfileModel> {
///     lazy var editor = Connection<EditorModel> { [weak parent] output in … }
///         .connect(state: \.destination, case: \.editor, parent: parent)
///
///     lazy var stats: StatsModel = Connection<StatsModel>()
///         .connect(from: parent!, to: \.stats)
///
///     override func setupConnections() {
///         _ = editor
///     }
/// }
/// ```
///
/// `init(parent:)` calls `setupConnections()`, then gives every evaluated connection its parent.
/// Touch each case connection in `setupConnections()`: a `lazy var` is invisible until it's
/// first read, and touching it makes the connection observe the parent from the start
/// (deep links also rely on this to find the child).
@MainActor
open class ViewModelConnections<ParentViewModel: ViewModel>: @MainActor Connectable {
    /// The ViewModel these connections belong to (weak, to avoid a retain cycle)
    public weak var parent: ParentViewModel?

    required public init(parent: ParentViewModel) {
        self.parent = parent
        setupConnections()
        wireConnections()
    }

    /// Override to touch each `lazy var` case connection (`_ = editor`) so it's created now
    open func setupConnections() {}

    /// Hands the parent to every connection property that has been evaluated
    private func wireConnections() {
        guard let parent else { return }
        for child in Mirror(reflecting: self).children {
            (child.value as? AnyConnection)?._setupParent(parent)
        }
    }
}

// MARK: - Connectable

/// An object that holds a ViewModel's connections and a weak reference back to it
public protocol Connectable: AnyObject {
    associatedtype ParentViewModel: AnyObject

    var parent: ParentViewModel? { get set }

    init(parent: ParentViewModel)
}

// MARK: - HasConnections

/// A ViewModel that exposes its connections, so deep links can continue into its children.
///
/// `@Component` adopts it for models with a nested `Connections` class; otherwise write `final class HomeModel: ComponentModel<HomeModel>, HasConnections`.
@MainActor
public protocol HasConnections: AnyObject {
    /// The type of connections this ViewModel uses (usually a `ViewModelConnections` subclass)
    associatedtype ConnectionsType: AnyObject

    /// The connections instance managing child ViewModels
    var connections: ConnectionsType { get }
}

extension HasConnections where Self: ViewModel {
    /// Typed access to the children: `model.children.editor` reads `model.connections.editor.model`.
    public var children: ConnectedChildren<ConnectionsType> {
        get { ConnectedChildren(connections: connections) }
        // Writing goes through the child's own setter; this one only makes `$model.children.x` a binding
        set {}
    }
}

// MARK: - ConnectedChildren

/// The children a model's connections hold, looked up by connection name.
///
/// ```swift
/// model.children.editor   // EditorModel?, while the destination is .editor
/// model.children.home     // HomeModel, a direct child
/// ```
///
/// Reading a case or optional connection's child syncs it with the parent first, like `model`.
/// Those children can also be set, so a view can bind to them: `$model.children.editor` is a
/// `Binding<EditorModel?>`, the same as `model.connections.editor.bindingModel`, and setting it to
/// `nil` (dismissing a sheet) clears the parent's destination or optional state.
/// For `present` and `push`, use the connection itself (`model.connections.editor`).
@MainActor
@dynamicMemberLookup
public struct ConnectedChildren<Connections: AnyObject> {
    let connections: Connections

    /// The child of a case or optional connection while the parent holds its state, otherwise `nil`
    public subscript<From: ViewModel, To: ViewModel, Case>(
        dynamicMember keyPath: KeyPath<Connections, CaseConnection<From, To, Case>>
    ) -> To? {
        get { connections[keyPath: keyPath].model }
        // Goes through `bindingModel`, so setting `nil` clears the parent's state, as dismissing does
        nonmutating set { connections[keyPath: keyPath].bindingModel.wrappedValue = newValue }
    }

    /// A directly connected child
    public subscript<To: ViewModel>(dynamicMember keyPath: KeyPath<Connections, To>) -> To {
        connections[keyPath: keyPath]
    }
}
