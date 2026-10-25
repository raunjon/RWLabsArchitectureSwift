//
//  DeepLink.swift
//  RWLabsArchitecture
//
//  Opens a deep link by walking its path down the ViewModel tree
//

import Foundation

// MARK: - DeepLinkStep

/// One segment of a deep link's path, with the link's query items.
///
/// `myapp://profile/order?id=7` has the steps `profile` and `order`, and both see `["id": "7"]`.
public struct DeepLinkStep: Sendable {
    /// The path segment
    public let name: String

    /// The link's query items, shared by every step
    public let queryItems: [String: String]

    public init(name: String, queryItems: [String: String] = [:]) {
        self.name = name
        self.queryItems = queryItems
    }

    /// A query item by name: `step["id"]`
    public subscript(_ key: String) -> String? {
        queryItems[key]
    }
}

// MARK: - DeepLinkable

/// A `Destination` enum whose cases can be opened from a deep link.
///
/// Map each URL name to a case; return `nil` for names the screen doesn't know.
/// The names are whatever you write here, not the Swift case names.
///
/// ```swift
/// extension ProfileModel.Destination: DeepLinkable {
///     init?(_ step: DeepLinkStep) {
///         switch step.name {
///         case "settings": self = .settings(.init())
///         case "order":    guard let id = step["id"] else { return nil }
///                          self = .order(.init(orderId: id))
///         default:         return nil
///         }
///     }
/// }
/// ```
///
/// The model that owns the destination must also adopt `HasConnections`, so the
/// link can continue into the child its connection creates.
public protocol DeepLinkable {
    init?(_ step: DeepLinkStep)
}

// MARK: - Macros

/// Generates the `DeepLinkable` conformance for a destination enum.
///
/// Every case is linkable under its case name, with its payload built by `Payload()`
/// (so each payload state needs an `init()` with no arguments, i.e. defaults for every property).
/// Use `@DeepLink` on a case to rename it, copy query items into its state, or leave it out.
///
/// ```swift
/// @DeepLinkable
/// @CasePathable
/// enum Destination: ViewModelDestination {
///     @DeepLink("item", params: ["id": "itemId"])   // …/item?id=42 → .detail(state with itemId = "42")
///     case detail(ItemDetailModel.State)
///
///     @DeepLink(params: ["orderId": "orderId"])    // …/order?orderId=7 (Int property, converted)
///     case order(OrderModel.State)
///
///     case settings(SettingsModel.State)           // …/settings
///
///     @DeepLink(skip: true)                        // not linkable
///     case confirmDelete(ConfirmModel.State)
/// }
/// ```
///
/// A case with a parameter fails (the init returns `nil`) when that query item is missing
/// or doesn't convert to the property's type, unless the property is optional.
@attached(extension, conformances: DeepLinkable, names: named(init))
public macro DeepLinkable() = #externalMacro(module: "RWLabsArchitectureMacros", type: "DeepLinkableMacro")

/// Configures one case of a `@DeepLinkable` enum.
///
/// - Parameters:
///   - name: The URL segment for the case (default: the case name).
///   - params: Query item name → property name on the payload state, e.g. `["id": "itemId"]`.
///     Supported property types: `String`, `Int`, `Double`, `Bool`, `UUID`, any other
///     `LosslessStringConvertible`, and optionals of those.
///   - skip: Leaves the case out of deep linking.
@attached(peer)
public macro DeepLink(_ name: String? = nil, params: [String: String] = [:], skip: Bool = false) = #externalMacro(module: "RWLabsArchitectureMacros", type: "DeepLinkMacro")

// MARK: - Reading Parameters

public extension DeepLinkStep {
    /// Copies query item `name` into `root[keyPath: keyPath]`, converting it to the property's type.
    /// - Returns: `false` if the query item is missing or doesn't convert.
    @discardableResult
    func assign<Root, Value: LosslessStringConvertible>(_ name: String, to keyPath: WritableKeyPath<Root, Value>, in root: inout Root) -> Bool {
        guard let raw = queryItems[name], let value = Value(raw) else { return false }
        root[keyPath: keyPath] = value
        return true
    }

    /// For an optional property: a missing query item leaves it `nil` and succeeds;
    /// one that doesn't convert fails.
    @discardableResult
    func assign<Root, Value: LosslessStringConvertible>(_ name: String, to keyPath: WritableKeyPath<Root, Value?>, in root: inout Root) -> Bool {
        guard let raw = queryItems[name] else { return true }
        guard let value = Value(raw) else { return false }
        root[keyPath: keyPath] = value
        return true
    }

    /// Copies query item `name` into a `UUID` property.
    @discardableResult
    func assign<Root>(_ name: String, to keyPath: WritableKeyPath<Root, UUID>, in root: inout Root) -> Bool {
        guard let raw = queryItems[name], let value = UUID(uuidString: raw) else { return false }
        root[keyPath: keyPath] = value
        return true
    }

    /// For an optional `UUID` property: a missing query item leaves it `nil` and succeeds.
    @discardableResult
    func assign<Root>(_ name: String, to keyPath: WritableKeyPath<Root, UUID?>, in root: inout Root) -> Bool {
        guard let raw = queryItems[name] else { return true }
        guard let value = UUID(uuidString: raw) else { return false }
        root[keyPath: keyPath] = value
        return true
    }
}

// MARK: - DeepLinkStepHandler

/// A model that opens deep-link steps itself instead of through `state.destination`,
/// typically a tab bar.
///
/// ```swift
/// extension MainTabModel: DeepLinkStepHandler {
///     func openDeepLinkStep(_ step: DeepLinkStep) -> (any ViewModel)? {
///         switch step.name {
///         case "home":    state.selectedTab = .home;    return connections.home
///         case "profile": state.selectedTab = .profile; return connections.profile
///         default:        return nil
///         }
///     }
/// }
/// ```
@MainActor
public protocol DeepLinkStepHandler: AnyObject {
    /// Opens `step` and returns the model that opens the following steps,
    /// or `nil` if this model doesn't recognise `step`.
    func openDeepLinkStep(_ step: DeepLinkStep) -> (any ViewModel)?
}

// MARK: - Opening

@MainActor
public extension ViewModel {
    /// Opens `route` starting at this model, one path segment per level.
    ///
    /// For each step, a `DeepLinkStepHandler` handles it itself; otherwise the model's
    /// `Destination` (if `DeepLinkable`) builds a case, `state.destination` is set,
    /// and the link continues into the child that destination's connection creates.
    ///
    /// - Returns: `true` if every step was opened. It stops at the first step no model
    ///   recognises, leaving the steps before it open.
    @discardableResult
    func openDeepLink(_ route: Route) -> Bool {
        let steps = route.path
            .split(separator: "/")
            .map { DeepLinkStep(name: String($0), queryItems: route.queryItems) }

        var current: any ViewModel = self
        for step in steps {
            guard let next = DeepLinkWalker.open(step, on: current) else {
                Log.w("Deep link \(route.path): '\(step.name)' isn't handled by \(type(of: current)). Is it in its Destination's init?(_ step:), and is the connection referenced in setupConnections()?")
                return false
            }
            current = next
        }
        return true
    }
}

/// Lets the walker reach the child of whichever case connection is active
@MainActor
protocol DeepLinkChildProviding {
    /// Syncs from the parent's state now, and returns the child if this connection's case is the parent's destination
    func deepLinkChild() -> (any ViewModel)?
}

@MainActor
enum DeepLinkWalker {
    static func open(_ step: DeepLinkStep, on model: any ViewModel) -> (any ViewModel)? {
        if let handler = model as? DeepLinkStepHandler {
            return handler.openDeepLinkStep(step)
        }
        return openDestination(step, on: model)
    }

    private static func openDestination<M: ViewModel>(_ step: DeepLinkStep, on model: M) -> (any ViewModel)? {
        guard let linkable = M.State.Destination.self as? DeepLinkable.Type,
              let destination = linkable.init(step) as? M.State.Destination else {
            return nil
        }
        model.state.destination = destination
        return activeChild(of: model)
    }

    /// The child created by the model's active case connection
    private static func activeChild(of model: any ViewModel) -> (any ViewModel)? {
        guard let owner = model as? any HasConnections else { return nil }
        let connections = owner.connections
        for child in Mirror(reflecting: connections).children {
            if let connection = child.value as? DeepLinkChildProviding,
               let childModel = connection.deepLinkChild() {
                return childModel
            }
        }
        return nil
    }
}
