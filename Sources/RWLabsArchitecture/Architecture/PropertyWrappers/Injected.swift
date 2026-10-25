//
//  Injected.swift
//  RWLabsArchitecture
//
//  Property wrappers that read dependencies from DependencyContainer.shared
//

import Foundation

// MARK: - @Injected

/// A dependency resolved from `DependencyContainer.shared` when the owner is created.
///
/// ```swift
/// final class ProfileModel: ComponentModel<…> {
///     @Injected var api: APIClient
/// }
/// ```
///
/// - Important: Resolution happens immediately, and crashes if the type isn't
///   registered. Register dependencies (including the app's `ErrorService`,
///   which every `BaseViewModel` injects) before creating any object that uses them.
/// - Note: The value can be reassigned, e.g. so a test can swap in a fake:
///   `model.api = MockAPIClient()`.
@propertyWrapper
public struct Injected<T> {
    private var dependency: T

    public init() {
        self.dependency = DependencyContainer.shared.resolve(T.self)
    }

    public var wrappedValue: T {
        get { dependency }
        mutating set { dependency = newValue }
    }
}

// MARK: - @LazyInjected

/// A dependency resolved from `DependencyContainer.shared` on first access, then cached.
///
/// Use it when the dependency may be registered after the owner is created, or
/// isn't always needed. It still crashes if the type isn't registered by the
/// time it's first read.
///
/// - Note: This delays *looking up* the dependency. To delay *creating* it, register it
///   with `registerLazySingleton`; the two work together.
/// - Note: The getter caches into the wrapper, so it only works where the owner
///   is mutable: properties of a class (e.g. a ViewModel), not of a SwiftUI
///   `View` struct, whose `body` can't mutate it.
/// - Note: The value can be reassigned, e.g. so a test can swap in a fake.
@propertyWrapper
public struct LazyInjected<T> {
    private var dependency: T?

    public init() {}

    public var wrappedValue: T {
        mutating get {
            if let dependency {
                return dependency
            }
            let resolved = DependencyContainer.shared.resolve(T.self)
            dependency = resolved
            return resolved
        }
        mutating set {
            dependency = newValue
        }
    }
}

// MARK: - @OptionalInjected

/// A dependency resolved from `DependencyContainer.shared` when the owner is
/// created, or `nil` if the type isn't registered.
///
/// For things the app works without, like analytics or debug tools. Use
/// `@Injected` for required services, so a missing registration fails loudly.
///
/// ```swift
/// @OptionalInjected var analytics: AnalyticsService?
/// ```
@propertyWrapper
public struct OptionalInjected<T> {
    private var dependency: T?

    public init() {
        self.dependency = DependencyContainer.shared.resolveOptional(T.self)
    }

    public var wrappedValue: T? {
        get { dependency }
        mutating set { dependency = newValue }
    }
}
