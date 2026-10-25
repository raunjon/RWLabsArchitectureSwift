//
//  Route.swift
//  RWLabsArchitecture
//
//  A parsed deep-link URL with path-pattern matching and URL building
//

import Foundation

// MARK: - Route

/// A deep link reduced to a path and query items, the same for custom-scheme
/// links and universal links:
///
/// | URL | `path` |
/// |---|---|
/// | `myapp://product/123?ref=mail` | `/product/123` |
/// | `https://example.com/product/123?ref=mail` | `/product/123` |
///
/// ```swift
/// let route = Route(url: url)
/// if let params = route.matches(pattern: "/product/:id") {
///     open(productId: params["id"]!, referrer: route.queryItems["ref"])
/// }
/// ```
public struct Route: Hashable {
    /// The path, always starting with `/`
    public let path: String

    /// Query items by name (the last value wins if a name repeats)
    public let queryItems: [String: String]

    public init(path: String, queryItems: [String: String] = [:]) {
        self.path = path.hasPrefix("/") ? path : "/" + path
        self.queryItems = queryItems
    }

    /// Parses `url`. For a custom scheme, the host is the first path segment
    /// (`myapp://product/123` has host `product`), so it's put back in front of the path.
    public init(url: URL) {
        let urlPath = url.path
        if !Self.isWebScheme(url.scheme), let host = url.host, !host.isEmpty {
            self.path = "/" + host + (urlPath == "/" ? "" : urlPath)
        } else {
            self.path = urlPath.isEmpty ? "/" : urlPath
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        self.queryItems = components?.queryItems?.reduce(into: [:]) {
            $0[$1.name] = $1.value ?? ""
        } ?? [:]
    }

    static func isWebScheme(_ scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

// MARK: - Pattern Matching

extension Route {
    /// Matches `path` against `pattern` and returns the `:name` placeholders' values,
    /// or `nil` if it doesn't match. Literal segments must match exactly; trailing
    /// slashes are ignored.
    ///
    /// ```swift
    /// Route(path: "/product/123").matches(pattern: "/product/:id")   // ["id": "123"]
    /// ```
    public func matches(pattern: String) -> [String: String]? {
        let patternComponents = pattern.split(separator: "/").map(String.init)
        let pathComponents = path.split(separator: "/").map(String.init)
        guard patternComponents.count == pathComponents.count else { return nil }

        var params: [String: String] = [:]
        for (patternPart, pathPart) in zip(patternComponents, pathComponents) {
            if patternPart.hasPrefix(":") {
                params[String(patternPart.dropFirst())] = pathPart
            } else if patternPart != pathPart {
                return nil
            }
        }
        return params
    }

    /// Whether `path` matches `pattern`
    public func isMatch(_ pattern: String) -> Bool {
        matches(pattern: pattern) != nil
    }
}

// MARK: - URL Building

extension Route {
    /// Builds a URL for this route.
    ///
    /// - With `host`: `scheme://host/path` (e.g. a universal link, `https://example.com/product/123`).
    /// - Without `host`, for a custom scheme: the first path segment becomes the host,
    ///   giving the standard form `myapp://product/123`. Web schemes need a host.
    ///
    /// Query items are sorted by name, so the same route always builds the same URL.
    public func url(scheme: String, host: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = scheme

        if let host {
            components.host = host
            components.path = path
        } else if !Self.isWebScheme(scheme) {
            let segments = path.split(separator: "/").map(String.init)
            components.host = segments.first ?? ""
            let rest = segments.dropFirst()
            components.path = rest.isEmpty ? "" : "/" + rest.joined(separator: "/")
        } else {
            return nil
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url
    }
}
