//
//  NavigationCore.swift
//  RWLabsArchitecture
//
//  Platform-agnostic navigation core types
//  Contains no UIKit or SwiftUI dependencies for maximum portability
//

import Foundation
import Combine

// MARK: - Destination Protocol

/// Protocol that all navigation destinations must conform to
///
/// Each feature module defines an enum conforming to this protocol
/// to represent the screens/destinations within that feature.
///
/// # Example
/// ```swift
/// enum ProductDestination: RouteDestination {
///     case list
///     case detail(productId: String)
///     case checkout
///
///     static var featureId: String { "products" }
///     static var initialDestination: Self { .list }
///
///     var presentationStyle: PresentationStyle {
///         switch self {
///         case .list: return .push
///         case .detail: return .push
///         case .checkout: return .modal
///         }
///     }
/// }
/// ```

public protocol RouteDestinationPresentable: RouteDestination {
    var presentationStyle: PresentationStyle { get }
}
public protocol RouteDestination: Hashable, Identifiable, Equatable {

    // MARK: - Required Properties

    /// Unique identifier for the feature this destination belongs to
//    static var featureId: String { get }

    /// The initial/default destination for this feature
//    static var initialDestination: Self { get }

    /// How this destination should be presented
//    var presentationStyle: PresentationStyle { get }

    /// Optional metadata for platform-specific customization
    var metadata: [String: String] { get }
}

// MARK: - Default Implementations

/// Default implementation for metadata (optional)
public extension RouteDestination {
    var metadata: [String: String] { [:] }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

/// Default implementation for Identifiable conformance
public extension RouteDestination {
    var id: UUID {
        UUID()
    }
}

// MARK: - ViewModel Extensions

extension ViewModel where Self: Hashable & Equatable {
    // Reserved for future ViewModel-specific navigation helpers
}

// MARK: - Presentation Style

/// Defines how a destination should be presented (platform-agnostic)
///
/// This enum provides abstract presentation intents that can be mapped
/// to platform-specific implementations (SwiftUI, UIKit, etc.)
///
/// # Platform Mappings
/// - iOS/SwiftUI: `push` → NavigationLink, `modal` → .sheet(), `alert` → .alert()
/// - UIKit: `push` → pushViewController, `modal` → present with modalPresentationStyle
public enum PresentationStyle: String, Codable {

    /// Navigate forward in the current navigation context
    /// - SwiftUI: NavigationLink or navigationDestination
    /// - UIKit: pushViewController
    case push

    /// Present as a system alert dialog
    /// - SwiftUI: .alert() modifier
    /// - UIKit: UIAlertController
    case alert

    /// Present as a custom alert/dialog with custom UI
    case customAlert

    /// Present as a modal sheet that partially covers the screen
    /// - SwiftUI: .sheet() modifier
    /// - UIKit: present with .pageSheet or .formSheet
    case modal

    /// Present as a full-screen modal covering the entire screen
    /// - SwiftUI: .fullScreenCover() modifier
    /// - UIKit: present with .fullScreen
    case fullScreen

    /// Replace the current screen in the navigation stack
    /// - SwiftUI: Replace last item in navigationPath
    /// - UIKit: popViewController then pushViewController
    case replace

    /// Pop to the root of the navigation stack
    /// - SwiftUI: Clear navigationPath
    /// - UIKit: popToRootViewController
    case popToRoot
}

// MARK: - Type-Erased Destination

/// Type-erased wrapper for `RouteDestination`
///
/// Allows storing and passing destinations without knowing their concrete type.
/// Useful for cross-feature navigation and command patterns.
///
/// # Example
/// ```swift
/// let productDest = ProductDestination.detail(productId: "123")
/// let anyDest = AnyDestination(productDest)
///
/// // Later, cast back if needed
/// if let concrete = anyDest.as(ProductDestination.self) {
///     print("Product ID:", concrete.productId)
/// }
/// ```
public struct AnyDestination: Hashable, Identifiable {

    // MARK: - Properties

    /// Unique identifier for this destination instance
    public let id: String

    /// How this destination should be presented
//    public let presentationStyle: PresentationStyle

    /// Optional metadata for platform-specific customization
    public let metadata: [String: String]

    /// The underlying destination instance
    private let base: Any

    /// Equality check function
    private let equalityFunction: (Any) -> Bool

    // MARK: - Initialization

    /// Creates a type-erased destination from a concrete destination
    /// - Parameter destination: The concrete destination to wrap
    public init<D: RouteDestination>(_ destination: D) {
        self.id = String(describing: destination)
//        self.presentationStyle = destination.presentationStyle
        self.metadata = destination.metadata
        self.base = destination
        self.equalityFunction = { other in
            guard let otherDest = other as? D else { return false }
            return destination == otherDest
        }
//        self.initialDestination = D.initialDestination
    }

    // MARK: - Hashable Conformance

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: AnyDestination, rhs: AnyDestination) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Type Casting

    /// Attempts to cast the erased destination back to its concrete type
    /// - Parameter type: The concrete type to cast to
    /// - Returns: The destination as the concrete type, or `nil` if casting fails
    public func `as`<D: RouteDestination>(_ type: D.Type) -> D? {
        base as? D
    }
}

// MARK: - Navigation Command

/// Commands emitted by the coordinator for platform-specific navigators to execute
///
/// Navigation coordinators emit these commands, and platform-specific navigators
/// (like SwiftUINavigator or UIKitNavigator) observe and execute them.
///
/// # Usage Pattern
/// ```swift
/// coordinator.commands
///     .sink { command in
///         switch command {
///         case .navigate(let destination, let animated):
///             // Handle navigation to destination
///         case .pop(let animated):
///             // Handle back navigation
///         // ... etc
///         }
///     }
/// ```
public enum NavigationCommand: Equatable {

    /// Navigate to a destination
    case navigate(destination: AnyDestination, animated: Bool)

    /// Pop the last destination from the navigation stack
    case pop(animated: Bool)

    /// Pop to the root destination for a specific feature
    case popToRoot(featureId: String, animated: Bool)

    /// Dismiss the currently presented destination (modal, alert, etc.)
    case dismiss(animated: Bool)

    /// Reset all navigation state
    case reset

    // MARK: - Equatable Conformance

    public static func == (lhs: NavigationCommand, rhs: NavigationCommand) -> Bool {
        switch (lhs, rhs) {
        case (.navigate(let lDest, let lAnim), .navigate(let rDest, let rAnim)):
            return lDest.id == rDest.id && lAnim == rAnim
        case (.pop(let lAnim), .pop(let rAnim)):
            return lAnim == rAnim
        case (.popToRoot(let lFeature, let lAnim), .popToRoot(let rFeature, let rAnim)):
            return lFeature == rFeature && lAnim == rAnim
        case (.dismiss(let lAnim), .dismiss(let rAnim)):
            return lAnim == rAnim
        case (.reset, .reset):
            return true
        default:
            return false
        }
    }
}

// MARK: - Navigation State

/// Represents the current navigation state for a feature (platform-agnostic)
///
/// Maintains the navigation stack and any presented destinations (modals, alerts, etc.)
/// for a specific feature.
///
/// # Example
/// ```swift
/// var state = NavigationState<ProductDestination>()
/// state.featureStack = [.list, .detail(productId: "123")]
/// state.presentedDestinations = .checkout // Modal checkout
/// ```
public struct NavigationState: Equatable {

    // MARK: - Properties

    /// The navigation stack for this feature
    /// Each element represents a pushed destination in the navigation hierarchy
    public var featureStack: [any RouteDestination] = []

    /// Currently presented destinations (modals, sheets, alerts, etc.)
    /// Only one can be presented at a time
    public var presentedDestinations: (any RouteDestination)?
    
    // MARK: - Initialization

    /// Creates an empty navigation state
    public init() {}

    // MARK: - Equatable Conformance

    public static func == (lhs: NavigationState, rhs: NavigationState) -> Bool {
        lhs.featureStack.count == rhs.featureStack.count &&
        lhs.presentedDestinations?.id == rhs.presentedDestinations?.id
    }
}
