//
//  Injected.swift
//  RWLabsArchitecture
//
//  Property wrappers for dependency injection
//  Provides convenient syntactic sugar for resolving dependencies
//

import Foundation

// MARK: - @Injected Property Wrapper

/// Automatically injects dependencies from the DependencyContainer
///
/// `@Injected` provides a convenient way to resolve dependencies without
/// explicitly calling the container. Dependencies are resolved immediately
/// when the property is initialized.
///
/// # Usage
///
/// ## Basic Injection
/// ```swift
/// class ProductViewModel {
///     @Injected var apiService: APIService
///     @Injected var userSession: UserSession
///
///     func loadProducts() {
///         apiService.fetchProducts { products in
///             // Handle products
///         }
///     }
/// }
/// ```
///
/// ## Custom Container
/// ```swift
/// class TestViewModel {
///     @Injected(container: testContainer) var apiService: APIService
/// }
/// ```
///
/// # Important Notes
/// - Dependencies must be registered before use (will crash if not registered)
/// - Resolution happens immediately on initialization
/// - Use `@LazyInjected` for lazy resolution
/// - Use `@OptionalInjected` for optional dependencies
///
/// # Registration Example
/// ```swift
/// // In App setup
/// DependencyContainer.shared.register(APIService.self) {
///     ProductionAPIService()
/// }
///
/// // Now @Injected var apiService: APIService will work
/// ```
@propertyWrapper
public struct Injected<T> {

    // MARK: - Properties

    /// The resolved dependency instance
    private var dependency: T

    /// Default container accessor
    private static var defaultContainer: DependencyContainer { DependencyContainer.shared }

    // MARK: - Initialization

    /// Initializes the property wrapper and resolves the dependency
    ///
    /// - Parameter container: Optional custom container (default: shared container)
    ///
    /// # Example
    /// ```swift
    /// @Injected var apiService: APIService
    /// @Injected(container: customContainer) var testService: TestService
    /// ```
    public init(container: DependencyContainer? = nil) {
        if let container {
            self.dependency = container.resolve(T.self)
        } else {
            self.dependency = Self.defaultContainer.resolve(T.self)
        }
    }

    // MARK: - Property Wrapper

    /// The resolved dependency value
    public var wrappedValue: T {
        get { dependency }
        mutating set { dependency = newValue }
    }

    /// Projected value for accessing the wrapper itself
    public var projectedValue: Injected<T> {
        get { self }
        set { self = newValue }
    }
}

// MARK: - @LazyInjected Property Wrapper

/// Lazily injects dependencies when first accessed
///
/// Unlike `@Injected`, this wrapper delays dependency resolution until
/// the first time the property is accessed. Useful for:
/// - Breaking initialization cycles
/// - Improving startup performance
/// - Optional initialization paths
///
/// # Usage
///
/// ```swift
/// class ViewController {
///     @LazyInjected var analyticsService: AnalyticsService
///     @LazyInjected var imageCache: ImageCache
///
///     func viewDidAppear() {
///         // AnalyticsService resolved here on first access
///         analyticsService.trackScreen("product_list")
///     }
/// }
/// ```
///
/// # Performance Benefits
/// ```swift
/// class AppCoordinator {
///     @LazyInjected var notificationService: NotificationService  // Not needed immediately
///     @LazyInjected var locationService: LocationService          // Only used in specific flows
///
///     func start() {
///         // These services won't be created until actually used
///     }
/// }
/// ```
///
/// # Comparison
/// - `@Injected`: Resolves immediately on init (eager)
/// - `@LazyInjected`: Resolves on first access (lazy)
@propertyWrapper
public struct LazyInjected<T> {

    // MARK: - Properties

    /// The lazily-resolved dependency (nil until first access)
    private var dependency: T?

    /// Container to use for resolution
    private let container: DependencyContainer

    /// Default container accessor
    private static var defaultContainer: DependencyContainer { DependencyContainer.shared }

    // MARK: - Initialization

    /// Initializes the property wrapper without resolving the dependency
    ///
    /// - Parameter container: Optional custom container (default: shared container)
    public init(container: DependencyContainer? = nil) {
        if let container {
            self.container = container
        } else {
            self.container = Self.defaultContainer
        }
    }

    // MARK: - Property Wrapper

    /// Lazily resolves and returns the dependency
    ///
    /// On first access, resolves the dependency from the container.
    /// Subsequent accesses return the cached instance.
    public var wrappedValue: T {
        mutating get {
            if dependency == nil {
                dependency = container.resolve(T.self)
            }
            return dependency!
        }
        mutating set {
            dependency = newValue
        }
    }
}

// MARK: - @OptionalInjected Property Wrapper

/// Injects optional dependencies that may not be registered
///
/// Unlike `@Injected` which crashes if a dependency isn't registered,
/// `@OptionalInjected` safely returns `nil` for unregistered dependencies.
///
/// # Usage
///
/// ## Optional Services
/// ```swift
/// class ViewModel {
///     @OptionalInjected var analyticsService: AnalyticsService?
///     @OptionalInjected var featureFlagService: FeatureFlagService?
///
///     func trackEvent(_ event: String) {
///         // Gracefully handles missing analytics
///         analyticsService?.track(event)
///     }
/// }
/// ```
///
/// ## Feature Flags
/// ```swift
/// class ProductListView {
///     @OptionalInjected var experimentalFeatures: ExperimentalFeatures?
///
///     var showNewDesign: Bool {
///         experimentalFeatures?.isEnabled("new_design") ?? false
///     }
/// }
/// ```
///
/// # When to Use
/// - **Optional analytics/monitoring** - App works without them
/// - **Beta features** - Only registered in certain builds
/// - **A/B testing services** - May not be available
/// - **Development tools** - Only in debug builds
///
/// # When NOT to Use
/// - **Core services** - Use `@Injected` to catch configuration errors early
/// - **Required dependencies** - Crashing is better than silent failure
@propertyWrapper
public struct OptionalInjected<T> {

    // MARK: - Properties

    /// The optionally-resolved dependency
    private var dependency: T?

    /// Default container accessor
    private static var defaultContainer: DependencyContainer { DependencyContainer.shared }

    // MARK: - Initialization

    /// Initializes the property wrapper and attempts to resolve the dependency
    ///
    /// - Parameter container: Optional custom container (default: shared container)
    public init(container: DependencyContainer? = nil) {
        if let container {
            self.dependency = container.resolveOptional(T.self)
        } else {
            self.dependency = Self.defaultContainer.resolveOptional(T.self)
        }
    }

    // MARK: - Property Wrapper

    /// The optionally-resolved dependency value
    public var wrappedValue: T? {
        get { dependency }
        mutating set { dependency = newValue }
    }
}

// MARK: - @Dependency Property Wrapper

/// Alternative dependency injection using DependencyKey protocol
///
/// This wrapper uses the `DependencyKey` protocol pattern (similar to SwiftUI's
/// EnvironmentKey) for type-safe dependency access with default values.
///
/// # Setup
///
/// ## 1. Define a Key
/// ```swift
/// struct APIServiceKey: DependencyKey {
///     static var defaultValue: APIService {
///         MockAPIService() // Fallback for tests/previews
///     }
/// }
/// ```
///
/// ## 2. Extend DependencyValues
/// ```swift
/// extension DependencyValues {
///     var apiService: APIService {
///         get { self[APIServiceKey.self] }
///         set { self[APIServiceKey.self] = newValue }
///     }
/// }
/// ```
///
/// ## 3. Use in ViewModels
/// ```swift
/// @MainActor
/// class ViewModel {
///     @Dependency(\.apiService) var apiService
///
///     func loadData() {
///         apiService.fetch()
///     }
/// }
/// ```
///
/// # Comparison with @Injected
///
/// | Feature | @Injected | @Dependency |
/// |---------|-----------|-------------|
/// | Registration | Explicit container | DependencyValues |
/// | Default value | Crashes if missing | Returns key's default |
/// | Type safety | Generic | KeyPath-based |
/// | SwiftUI-like | No | Yes |
///
/// # When to Use Each
/// - **@Injected**: Traditional DI, explicit registration, crashes on missing dependencies
/// - **@Dependency**: SwiftUI-style, default values, more flexible for testing
@propertyWrapper @MainActor
public struct Dependency<Key: DependencyKey> {

    // MARK: - Properties

    /// Key path to the dependency in DependencyValues
    private let keyPath: WritableKeyPath<DependencyValues, Key.Value>

    // MARK: - Initialization

    /// Initializes the property wrapper with a key path
    ///
    /// - Parameter keyPath: Key path to the dependency in DependencyValues
    ///
    /// # Example
    /// ```swift
    /// @Dependency(\.apiService) var apiService
    /// @Dependency(\.userSession) var userSession
    /// ```
    public init(_ keyPath: WritableKeyPath<DependencyValues, Key.Value>) {
        self.keyPath = keyPath
    }

    // MARK: - Property Wrapper

    /// The dependency value from DependencyValues
    public var wrappedValue: Key.Value {
        DependencyValues.current[keyPath: keyPath]
    }
}
