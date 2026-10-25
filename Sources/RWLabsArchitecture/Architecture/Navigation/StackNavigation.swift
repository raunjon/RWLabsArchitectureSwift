//
//  StackNavigation.swift
//  RWLabsArchitecture
//
//  popToRoot() and close(): navigating back from inside a child, without outputs
//

// MARK: - Parent Links

/// A model that a case connection can link to its parent
@MainActor
protocol NavigableModel: AnyObject {
    /// How this model was created: its parent, how it's shown, and how to remove it
    var parentLink: ParentLink? { get set }
    /// Links of the children this model's case connections currently hold
    var childLinks: [ParentLink] { get set }
}

/// Created by a `CaseConnection` for each child it activates. The child owns it; the parent and
/// the connection are held weakly.
@MainActor
final class ParentLink {
    weak var parent: (any NavigableModel)?
    /// `.push`, `.modal`, … or `nil` when unknown (an inline child, a hand-written `.sheet`)
    private let style: () -> PresentationStyle?
    /// Clears the parent's value, if it still holds this child
    let clear: () -> Void

    init(parent: (any NavigableModel)?, style: @escaping () -> PresentationStyle?, clear: @escaping () -> Void) {
        self.parent = parent
        self.style = style
        self.clear = clear
    }

    var isPush: Bool { style() == .push }
}

extension BaseViewModel: NavigableModel {}

// MARK: - popToRoot / close

public extension BaseViewModel {
    /// Pops every pushed screen back to the root of the current `NavigationStack`.
    ///
    /// Walks up through the screens that were pushed and clears `destination` on the screen at
    /// the bottom of the stack. Inside a sheet it stops at the sheet's root, so the sheet stays
    /// open. Called on a stack root, it pops what that root pushed.
    ///
    /// A connection knows it's a push when the view shows it with `.push(connection)`, or when
    /// the destination's `presentationStyle` is `.push` (`showDestination`).
    func popToRoot() {
        var lowestPush: ParentLink?
        var link = parentLink
        while let current = link, current.isPush {
            lowestPush = current
            link = current.parent?.parentLink
        }
        if let lowestPush {
            lowestPush.clear()
        } else {
            childLinks.first(where: \.isPush)?.clear()
        }
    }

    /// Pops, dismisses or removes this screen by clearing the parent's value that holds it.
    ///
    /// Works for any child created by a case connection: a push, a sheet, an alert, or an
    /// optional inline child. Does nothing for a directly connected child (a tab) or a root.
    func close() {
        guard let parentLink else {
            Log.w("close(): \(type(of: self)) wasn't created by a case connection, so there's nothing to close")
            return
        }
        parentLink.clear()
    }
}
