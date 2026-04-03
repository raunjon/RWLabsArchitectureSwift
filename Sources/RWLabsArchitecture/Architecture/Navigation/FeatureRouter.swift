//
//  FeatureRouter.swift
//  RWLabsArchitecture
//
//  Feature-specific routing protocol for deep linking
//

import Foundation

// MARK: - Feature Router Protocol

/// Protocol for feature-specific routing and deep link handling
///
/// Each feature module in your app implements this protocol to:
/// - Define which URL patterns it handles
/// - Convert routes to navigation destinations
/// - Generate URLs from destinations for sharing/universal links
///
/// # Example
/// ```swift
/// struct ProductRouter: FeatureRouter {
///     static var featureId: String { "products" }
///     static var routePatterns: [String] { ["/product/:id", "/products"] }
///
///     func destination(for route: Route) -> ProductDestination? {
///         if let params = route.matches(pattern: "/product/:id"),
///            let id = params["id"] {
///             return .detail(productId: id)
///         }
///         return nil
///     }
///
///     func route(for destination: any RouteDestination) -> Route? {
///         guard let dest = destination as? ProductDestination else { return nil }
///         switch dest {
///         case .detail(let id):
///             return Route(path: "/product/\(id)")
///         }
///     }
/// }
/// ```
public protocol FeatureRouter {

    // MARK: - Required Properties

    /// Unique identifier for the feature this router handles
    static var featureId: String { get }

    /// URL patterns this feature can handle
    /// - Example: `["/product/:id", "/products", "/categories/:categoryId"]`
    static var routePatterns: [String] { get }

    // MARK: - Required Methods

    /// Converts a route to a destination if this feature can handle it
    /// - Parameter route: The route to convert
    /// - Returns: A destination if the route matches this feature, `nil` otherwise
    func destination(for route: Route) -> (any RouteDestination)?

    /// Converts a destination back to a route for URL generation
    /// - Parameter destination: The destination to convert
    /// - Returns: A route if the destination belongs to this feature, `nil` otherwise
    func route(for destination: any RouteDestination) -> Route?
}

// MARK: - Default Implementations

public extension FeatureRouter {

    /// Checks if this router can handle a given route
    /// - Parameter route: The route to check
    /// - Returns: `true` if the router can convert the route to a destination
    func canHandle(route: Route) -> Bool {
        destination(for: route) != nil
    }

    /// Generates a shareable URL for a destination
    /// - Parameters:
    ///   - destination: The destination to generate a URL for
    ///   - scheme: The URL scheme (default: `"myapp"`)
    /// - Returns: The generated URL, or `nil` if the destination doesn't belong to this feature
    func url(for destination: any RouteDestination, scheme: String = "myapp") -> URL? {
        guard let route = route(for: destination) else { return nil }
        return route.url(scheme: scheme)
    }
}
