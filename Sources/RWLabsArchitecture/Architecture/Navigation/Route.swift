//
//  Route.swift
//  RWLabsArchitecture
//
//  URL routing system for deep linking and navigation
//

import Foundation

// MARK: - Route

/// Represents a parsed URL route for deep linking and navigation
///
/// `Route` encapsulates the components of a URL (path, parameters, query items)
/// and provides pattern matching capabilities for routing decisions.
///
/// # Example
/// ```swift
/// let url = URL(string: "myapp://product/123?sort=price")!
/// let route = Route(url: url)
/// // route.path = "/product/123"
/// // route.queryItems = ["sort": "price"]
/// ```
public struct Route: Hashable {

    // MARK: - Properties

    /// The path component of the URL
    /// - Example: `"/product/123"`
    public let path: String

    /// Path parameters extracted from pattern matching
    /// - Example: `["id": "123"]` from pattern `"/product/:id"`
    public let parameters: [String: String]

    /// Query string parameters from the URL
    /// - Example: `["sort": "price"]` from `"?sort=price"`
    public let queryItems: [String: String]

    // MARK: - Initialization

    /// Creates a route with explicit components
    /// - Parameters:
    ///   - path: The URL path
    ///   - parameters: Path parameters (default: empty)
    ///   - queryItems: Query string parameters (default: empty)
    public init(
        path: String,
        parameters: [String: String] = [:],
        queryItems: [String: String] = [:]
    ) {
        self.path = path
        self.parameters = parameters
        self.queryItems = queryItems
    }

    /// Creates a route by parsing a URL
    /// - Parameter url: The URL to parse
    /// - Note: Parameters will be extracted during pattern matching
    public init(url: URL) {
        self.path = url.path

        // Extract query items from URL components
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        self.queryItems = components?.queryItems?.reduce(into: [:]) {
            $0[$1.name] = $1.value ?? ""
        } ?? [:]

        // Parameters will be extracted during pattern matching
        self.parameters = [:]
    }
}

// MARK: - Route Pattern Matching

/// Extension providing pattern matching capabilities for routes
extension Route {

    /// Matches this route against a URL pattern and extracts parameters
    ///
    /// Patterns use `:paramName` syntax for dynamic segments:
    /// - Pattern: `"/product/:id"` matches path `"/product/123"` → `["id": "123"]`
    /// - Pattern: `"/user/:userId/post/:postId"` matches `"/user/42/post/99"` → `["userId": "42", "postId": "99"]`
    ///
    /// - Parameter pattern: The URL pattern with optional parameter placeholders
    /// - Returns: Dictionary of extracted parameters, or `nil` if pattern doesn't match
    ///
    /// # Example
    /// ```swift
    /// let route = Route(path: "/product/123")
    /// if let params = route.matches(pattern: "/product/:id") {
    ///     print(params["id"]) // "123"
    /// }
    /// ```
    public func matches(pattern: String) -> [String: String]? {
        let patternComponents = pattern.split(separator: "/").map(String.init)
        let pathComponents = path.split(separator: "/").map(String.init)

        // Pattern and path must have the same number of components
        guard patternComponents.count == pathComponents.count else { return nil }

        var params: [String: String] = [:]

        for (patternPart, pathPart) in zip(patternComponents, pathComponents) {
            if patternPart.starts(with: ":") {
                // Extract parameter from placeholder (e.g., ":id" → "id")
                let key = String(patternPart.dropFirst())
                params[key] = pathPart
            } else if patternPart != pathPart {
                // Literal segments must match exactly
                return nil
            }
        }

        return params
    }

    /// Checks if this route matches a pattern without extracting parameters
    /// - Parameter pattern: The URL pattern to match against
    /// - Returns: `true` if the route matches the pattern, `false` otherwise
    public func matches(pattern: String) -> Bool {
        matches(pattern: pattern) != nil
    }
}

// MARK: - Route Builder

/// Extension providing URL construction capabilities from routes
extension Route {

    /// Constructs a complete URL from the route components
    ///
    /// - Parameters:
    ///   - scheme: The URL scheme (default: `"myapp"`)
    ///   - host: The URL host (default: empty, resulting in no host)
    /// - Returns: The constructed URL, or `nil` if URL components are invalid
    ///
    /// # Example
    /// ```swift
    /// let route = Route(path: "/product/123", queryItems: ["sort": "price"])
    /// let url = route.url(scheme: "myapp", host: "store")
    /// // Result: "myapp://store/product/123?sort=price"
    /// ```
    public func url(scheme: String = "myapp", host: String = "") -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host.isEmpty ? nil : host
        components.path = path

        // Add query items if present
        if !queryItems.isEmpty {
            components.queryItems = queryItems.map {
                URLQueryItem(name: $0.key, value: $0.value)
            }
        }

        return components.url
    }
}
