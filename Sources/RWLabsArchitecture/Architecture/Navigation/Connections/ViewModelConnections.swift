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
/// Adopt it on models that have destinations: `final class HomeModel: ComponentModel<…>, HasConnections`.
@MainActor
public protocol HasConnections: AnyObject {
    /// The type of connections this ViewModel uses (usually a `ViewModelConnections` subclass)
    associatedtype ConnectionsType: AnyObject

    /// The connections instance managing child ViewModels
    var connections: ConnectionsType { get }
}
