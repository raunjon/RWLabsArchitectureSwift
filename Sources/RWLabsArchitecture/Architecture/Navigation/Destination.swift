//
//  Destination.swift
//  RWLabsArchitecture
//
//  Destination protocols and presentation styles
//

import Foundation

// MARK: - ViewModelDestination

/// Where a screen can navigate to: one enum per screen, one case per child,
/// each carrying the child's state.
///
/// ```swift
/// @CasePathable
/// enum Destination: ViewModelDestination {
///     case detail(ItemDetailModel.State)
///     case settings(SettingsModel.State)
/// }
/// ```
///
/// Destinations compare and hash by `id`, which defaults to the case name, so
/// payload states don't need to be `Equatable` or `Hashable`.
public protocol ViewModelDestination: Hashable, Identifiable {}

public extension ViewModelDestination {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// The case name (e.g. `"detail"` for `.detail(state)`), stable across reads and
    /// payload changes. Override it if two values of the same case must be distinguishable.
    var id: String {
        Mirror(reflecting: self).children.first?.label ?? String(describing: self)
    }
}

// MARK: - RouteDestinationPresentable

/// A destination that says how it's presented, for `showDestination(_:destination:)`
public protocol RouteDestinationPresentable: ViewModelDestination {
    var presentationStyle: PresentationStyle { get }
}

// MARK: - PresentationStyle

/// How `showDestination(_:destination:)` presents a destination
public enum PresentationStyle: String, Codable {
    /// Pushed onto the enclosing `NavigationStack` (`.navigationDestination(item:)`)
    case push

    /// A sheet (`.sheet(item:)`)
    case modal

    /// A full-screen cover (`.fullScreenCover(item:)`)
    case fullScreen

    /// A custom alert overlay in its own window (`.customAlert(item:)`)
    case customAlert

    /// Currently shown as a sheet; use SwiftUI's `.alert` yourself for system alert chrome
    case alert
}
