//
//  DependencyContainer.swift
//  RWLabsArchitecture
//
//  Dependency injection container and resolver
//  Thread-safe service locator pattern for managing app dependencies
//

import Foundation

// MARK: - Dependency Key Protocol

/// Protocol for defining dependency keys with default values
///
/// Implement this protocol to create type-safe dependency keys for use
/// with the `DependencyValues` system.
///
/// # Example
/// ```swift
/// struct APIServiceKey: DependencyKey {
///     static var defaultValue: APIService {
///         DefaultAPIService()
///     }
/// }
///
/// extension DependencyValues {
///     var apiService: APIService {
///         get { self[APIServiceKey.self] }
///         set { self[APIServiceKey.self] = newValue }
///     }
/// }
/// ```
public protocol DependencyKey {
    /// The type of value this key provides
    associatedtype Value

    /// The default value to use when the dependency is not explicitly set
    static var defaultValue: Value { get }
}

// MARK: - Dependency Container

/// Thread-safe dependency injection container
///
/// `DependencyContainer` is a service locator that manages application dependencies.
/// It supports both factory-based registration (new instance each time) and
/// singleton registration (same instance always).
///
/// # Architecture
/// - **Thread-Safe**: Uses `NSRecursiveLock` for thread safety
/// - **Singleton**: Shared instance accessible globally
/// - **Type-Safe**: Uses Swift generics for compile-time type checking
/// - **Flexible**: Supports both factory and singleton patterns
///
/// # Registration Patterns
///
/// ## Factory Registration (New Instance Each Time)
/// ```swift
/// DependencyContainer.shared.register(APIService.self) {
///     DefaultAPIService()
/// }
///
/// let service1 = DependencyContainer.shared.resolve(APIService.self)
/// let service2 = DependencyContainer.shared.resolve(APIService.self)
/// // service1 !== service2 (different instances)
/// ```
///
/// ## Singleton Registration (Same Instance Always)
/// ```swift
/// let database = Database()
/// DependencyContainer.shared.registerSingleton(Database.self, instance: database)
///
/// let db1 = DependencyContainer.shared.resolve(Database.self)
/// let db2 = DependencyContainer.shared.resolve(Database.self)
/// // db1 === db2 (same instance)
/// ```
///
/// # Common Usage Pattern
/// ```swift
/// // In AppDelegate or App struct
/// func setupDependencies() {
///     let container = DependencyContainer.shared
///
///     // Register services
///     container.registerSingleton(UserSession.self, instance: UserSession())
///     container.register(APIService.self) { DefaultAPIService() }
///     container.register(Repository.self) {
///         DefaultRepository(apiService: container.resolve(APIService.self))
///     }
/// }
///
/// // In ViewModels or other components
/// class ProductViewModel {
///     private let repository: Repository
///
///     init() {
///         self.repository = DependencyContainer.shared.resolve(Repository.self)
///     }
/// }
/// ```
///
/// # Testing
/// ```swift
/// override func setUp() {
///     super.setUp()
///
///     // Clear existing dependencies
///     DependencyContainer.shared.clear()
///
///     // Register test doubles
///     DependencyContainer.shared.registerSingleton(
///         APIService.self,
///         instance: MockAPIService()
///     )
/// }
/// ```
public final class DependencyContainer {

    // MARK: - Shared Instance

    /// Shared singleton instance of the dependency container
    ///
    /// - Note: Uses `nonisolated(unsafe)` to allow access from any isolation context
    public nonisolated(unsafe) static let shared = DependencyContainer()

    // MARK: - Private Properties

    /// Storage for registered dependencies
    /// - Key: String representation of the type
    /// - Value: Either a factory closure `() -> T` or a singleton instance `T`
    private var dependencies: [String: Any] = [:]

    /// Recursive lock for thread-safe access
    private let lock = NSRecursiveLock()

    // MARK: - Initialization

    /// Private initializer to enforce singleton pattern
    private init() {}

    // MARK: - Registration

    /// Registers a factory closure for creating new instances
    ///
    /// Each call to `resolve(_:)` will execute the factory and return a new instance.
    ///
    /// - Parameters:
    ///   - type: The type to register
    ///   - factory: Closure that creates a new instance
    ///
    /// # Example
    /// ```swift
    /// container.register(Logger.self) {
    ///     FileLogger(path: "/logs")
    /// }
    ///
    /// let logger1 = container.resolve(Logger.self) // New instance
    /// let logger2 = container.resolve(Logger.self) // Another new instance
    /// ```
    public func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        lock.lock()
        defer { lock.unlock() }

        let key = String(describing: type)
        dependencies[key] = factory
    }

    /// Registers a singleton instance
    ///
    /// All calls to `resolve(_:)` will return the same instance.
    ///
    /// - Parameters:
    ///   - type: The type to register
    ///   - instance: The singleton instance to store
    ///
    /// # Example
    /// ```swift
    /// let session = UserSession()
    /// container.registerSingleton(UserSession.self, instance: session)
    ///
    /// let session1 = container.resolve(UserSession.self) // Same instance
    /// let session2 = container.resolve(UserSession.self) // Same instance
    /// // session1 === session2
    /// ```
    public func registerSingleton<T>(_ type: T.Type, instance: T) {
        lock.lock()
        defer { lock.unlock() }

        let key = String(describing: type)
        dependencies[key] = instance
    }
    // MARK: - Resolution

    /// Resolves a dependency
    ///
    /// Returns the registered dependency or crashes if not found.
    ///
    /// - Parameter type: The type to resolve
    /// - Returns: Instance of the requested type
    /// - Warning: Crashes with `fatalError` if the dependency is not registered
    ///
    /// # Example
    /// ```swift
    /// let apiService = container.resolve(APIService.self)
    /// ```
    ///
    /// # Thread Safety
    /// This method is thread-safe and can be called from multiple threads simultaneously.
    public func resolve<T>(_ type: T.Type) -> T {
        lock.lock()
        defer { lock.unlock() }

        let key = String(describing: type)

        // Check if it's a singleton instance
        if let instance = dependencies[key] as? T {
            return instance
        }

        // Check if it's a factory
        if let factory = dependencies[key] as? () -> T {
            return factory()
        }

        fatalError("Dependency \(key) not registered. Did you forget to register it?")
    }

    /// Resolves an optional dependency
    ///
    /// Returns the registered dependency or `nil` if not found.
    /// Useful when a dependency is optional or for graceful degradation.
    ///
    /// - Parameter type: The type to resolve
    /// - Returns: Instance of the requested type, or `nil` if not registered
    ///
    /// # Example
    /// ```swift
    /// if let analytics = container.resolveOptional(Analytics.self) {
    ///     analytics.track("event")
    /// } else {
    ///     print("Analytics not available")
    /// }
    /// ```
    public func resolveOptional<T>(_ type: T.Type) -> T? {
        lock.lock()
        defer { lock.unlock() }

        let key = String(describing: type)

        // Check if it's a singleton instance
        if let instance = dependencies[key] as? T {
            return instance
        }

        // Check if it's a factory
        if let factory = dependencies[key] as? () -> T {
            return factory()
        }

        return nil
    }

    // MARK: - Utilities

    /// Clears all registered dependencies
    ///
    /// Primarily useful for testing to reset the container state between tests.
    ///
    /// # Example
    /// ```swift
    /// override func setUp() {
    ///     super.setUp()
    ///     DependencyContainer.shared.clear()
    ///     // Register test dependencies
    /// }
    /// ```
    ///
    /// - Warning: Clearing dependencies in production code may cause crashes
    ///   if components attempt to resolve dependencies afterwards
    public func clear() {
        lock.lock()
        defer { lock.unlock() }

        dependencies.removeAll()
    }
}

// MARK: - Dependency Values

/// Type-safe storage for dependency values using keys
///
/// `DependencyValues` provides a SwiftUI-like environment values pattern
/// for dependency injection. Use `DependencyKey` protocol to define typed keys.
///
/// # Example
/// ```swift
/// // Define a key
/// struct LoggerKey: DependencyKey {
///     static var defaultValue: Logger { ConsoleLogger() }
/// }
///
/// // Extend DependencyValues
/// extension DependencyValues {
///     var logger: Logger {
///         get { self[LoggerKey.self] }
///         set { self[LoggerKey.self] = newValue }
///     }
/// }
///
/// // Use it
/// @MainActor
/// func example() {
///     DependencyValues.current.logger = FileLogger()
///     let logger = DependencyValues.current.logger
/// }
/// ```
public struct DependencyValues {

    // MARK: - Storage

    /// Internal storage for dependency values
    private var storage: [String: Any] = [:]

    // MARK: - Subscript

    /// Type-safe subscript for accessing dependencies
    ///
    /// - Parameter key: The dependency key type
    /// - Returns: The dependency value or the key's default value
    public subscript<K: DependencyKey>(key: K.Type) -> K.Value {
        get {
            storage[String(describing: key)] as? K.Value ?? K.defaultValue
        }
        set {
            storage[String(describing: key)] = newValue
        }
    }
}

// MARK: - Dependency Accessor

/// Private storage for the current dependency values
private struct DependencyValuesKey {
    /// Current dependency values (main actor isolated)
    @MainActor static var current = DependencyValues()
}

// MARK: - Current Dependency Values

public extension DependencyValues {
    /// Access the current dependency values
    ///
    /// - Note: Main actor isolated for thread safety
    ///
    /// # Example
    /// ```swift
    /// @MainActor
    /// func setupDependencies() {
    ///     DependencyValues.current.logger = FileLogger()
    ///     DependencyValues.current.apiClient = ProductionAPIClient()
    /// }
    /// ```
    @MainActor static var current: DependencyValues {
        get { DependencyValuesKey.current }
        set { DependencyValuesKey.current = newValue }
    }
}
