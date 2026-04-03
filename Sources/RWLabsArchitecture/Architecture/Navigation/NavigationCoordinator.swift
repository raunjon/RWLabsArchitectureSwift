//
//  NavigationCoordinator.swift
//  RWLabsArchitecture
//
//  Platform-agnostic navigation coordinator
//  Manages navigation state and emits commands for platform-specific navigators
//

import Foundation
import Combine
import SwiftUI

// MARK: - Navigation Coordinator

/// Coordinates navigation for a specific feature
///
/// `NavigationCoordinator` is the central component for managing navigation state
/// and emitting navigation commands. It maintains the navigation stack, handles
/// presented destinations, and supports deep linking through feature routers.
///
/// # Architecture
/// - **Platform-Agnostic**: Contains no UIKit or SwiftUI dependencies
/// - **Command Pattern**: Emits commands that platform navigators execute
/// - **Deep Linking**: Supports URL-based navigation through registered routers
///
/// # Example
/// ```swift
/// let coordinator = NavigationCoordinator<ProductDestination>()
///
/// // Navigate to a destination
/// coordinator.navigate(to: .detail(productId: "123"))
///
/// // Present a modal
/// coordinator.navigate(to: .checkout, animated: true)
///
/// // Handle deep links
/// coordinator.register(router: ProductRouter())
/// coordinator.handleDeepLink(url)
/// ```
@MainActor
open class NavigationCoordinator: @MainActor StateComponent, DynamicStateLookup {
    @Published public var path: NavigationPath = NavigationPath()

    // MARK: - Published State

    /// Current navigation state containing the stack and presented destinations
    @Published public var state = NavigationState()

    // MARK: - StateComponent Conformance

    /// Updates the navigation state
    /// - Parameter update: Closure to modify the state
    public func updateState(_ update: (inout NavigationState) -> Void) {
        update(&state)
    }

    // MARK: - Command Publisher

    /// Commands emitted for platform-specific navigators to execute
    /// Platform navigators (SwiftUI, UIKit) observe this publisher and execute commands
    public let commands = PassthroughSubject<NavigationCommand, Never>()

    // MARK: - Feature Routers

    /// Registered feature routers for deep linking support
    private var featureRouters: [String: any FeatureRouter] = [:]

    // MARK: - Initialization

    /// Creates a new navigation coordinator
    public init() {}

    // MARK: - Feature Registration

    /// Registers a feature router for deep linking support
    /// - Parameter router: The feature router to register
    ///
    /// # Example
    /// ```swift
    /// coordinator.register(router: ProductRouter())
    /// ```
    public func register(router: any FeatureRouter) {
        let featureId = type(of: router).featureId
        featureRouters[featureId] = router
    }

    // MARK: - Navigation Methods

    /// Navigates to a destination
    ///
    /// The navigation behavior depends on the destination's `presentationStyle`:
    /// - `.push`: Adds to navigation stack
    /// - `.replace`: Replaces current destination in stack
    /// - `.popToRoot`: Clears stack and sets as root
    /// - `.modal`, `.fullScreen`, `.alert`, `.customAlert`: Presents over current context
    ///
    /// - Parameters:
    ///   - destination: The destination to navigate to
    ///   - animated: Whether to animate the transition (default: `true`)
    ///
    /// # Example
    /// ```swift
    /// coordinator.navigate(to: .detail(productId: "123"))
    /// coordinator.navigate(to: .checkout, animated: false)
    /// ```
    public func navigate(to destination: RouteDestination?, animated: Bool = true) {
        guard let destination else {
            self.presentedDestinations = nil
            return
        }
        // Update state based on presentation style
        switch destination.presentationStyle {
        case .push, .replace, .popToRoot:
            // Manage navigation stack
            var path = state.featureStack
            self.path.append(destination)
            if destination.presentationStyle == .popToRoot {
                // Clear stack and set as root
                path = [destination]
            } else {
                // Add to stack
                path.append(destination)
            }
            state.featureStack = path
            objectWillChange.send()

        case .alert, .customAlert, .modal, .fullScreen:
            // Present as overlay
            self.state.presentedDestinations = destination
            self.objectWillChange.send()
        }

        // Emit command for platform navigator
        commands.send(.navigate(destination: AnyDestination(destination), animated: animated))
    }

    public func dismssModal() {
        self.navigate(to: nil)
    }
    /// Returns the current destination (top of navigation stack)
    /// - Returns: The current destination, or the initial destination if stack is empty
    public func currentDestination() -> (any RouteDestination)? {
        state.featureStack.last
    }

    /// Pops the last destination from the navigation stack
    /// - Parameters:
    ///   - featureId: The feature identifier (currently unused, reserved for future use)
    ///   - animated: Whether to animate the pop (default: `true`)
    public func pop(from featureId: String, animated: Bool = true) {
        var path = state.featureStack
        guard !path.isEmpty else { return }
        path.removeLast()
        state.featureStack = path
        commands.send(.pop(animated: animated))
    }

    /// Pops to the root destination (clears the navigation stack)
    /// - Parameters:
    ///   - featureId: The feature identifier
    ///   - animated: Whether to animate the pop (default: `true`)
    public func popToRoot(for featureId: String, animated: Bool = true) {
        state.featureStack = []
        commands.send(.popToRoot(featureId: featureId, animated: animated))
    }

    /// Dismisses the currently presented destination (modal, alert, etc.)
    /// - Parameter animated: Whether to animate the dismissal (default: `true`)
    public func dismiss(animated: Bool = true) {
        guard state.presentedDestinations != nil else { return }

        state.presentedDestinations = nil
        commands.send(.dismiss(animated: animated))
    }

    /// Resets all navigation state to initial conditions
    public func reset() {
        state = NavigationState()
        commands.send(.reset)
    }

    // MARK: - Path Access

    /// Returns the current navigation path for a feature
    /// - Parameter type: The destination type
    /// - Returns: Array of destinations in the navigation stack
    public func path1<D: RouteDestination>(for type: D.Type) -> [D] {
        state.featureStack.map { $0 as? D ?? D.initialDestination }
    }

    /// Updates the navigation path for a feature
    ///
    /// Used by platform navigators when the path changes (e.g., user swipes back in SwiftUI)
    ///
    /// - Parameters:
    ///   - type: The destination type
    ///   - path: The new navigation path
    public func updatePath<D:RouteDestination>(for type: D.Type, path:NavigationPath) {
//        state.featureStack = path
        self.path = path
        objectWillChange.send()
    }

    // MARK: - Deep Linking

    /// Handles a deep link URL by routing it to the appropriate destination
    ///
    /// Attempts to match the URL against all registered feature routers.
    /// The first router that successfully converts the URL to a destination wins.
    ///
    /// - Parameters:
    ///   - url: The deep link URL to handle
    ///   - animated: Whether to animate the navigation (default: `true`)
    /// - Returns: `true` if the URL was successfully handled, `false` otherwise
    ///
    /// # Example
    /// ```swift
    /// let url = URL(string: "myapp://product/123")!
    /// if coordinator.handleDeepLink(url) {
    ///     print("Deep link handled successfully")
    /// }
    /// ```
//    @discardableResult
//    public func handleDeepLink(_ url: URL, animated: Bool = true) -> Bool {
//        let route = Route(url: url)
//
//        // Try each feature router until one handles it
//        for router in featureRouters.values {
//            if let destination = router.destination(for: route) {
//                navigate(to: destination as! Destination, animated: animated)
//                return true
//            }
//        }
//
//        return false
//    }

    /// Generates a shareable URL for a destination
    ///
    /// Useful for creating universal links or sharing specific app content.
    ///
    /// - Parameters:
    ///   - destination: The destination to generate a URL for
    ///   - scheme: The URL scheme (default: `"myapp"`)
    /// - Returns: The generated URL, or `nil` if no router handles the destination
    ///
    /// # Example
    /// ```swift
    /// let url = coordinator.url(for: ProductDestination.detail(productId: "123"))
    /// // Result: "myapp://product/123"
    /// ```
    public func url(for destination: any RouteDestination, scheme: String = "myapp") -> URL? {
        let featureId = type(of: destination).featureId
        guard let router = featureRouters[featureId] else { return nil }

        return router.url(for: destination, scheme: scheme)
    }
}
