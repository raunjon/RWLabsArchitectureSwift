//
//  AppCoordinator.swift
//  RWLabsArchitecture
//
//  Application coordinator for centralized app lifecycle management
//  Handles dependency injection setup, navigation initialization, and service startup
//

import Foundation

// MARK: - AppCoordinator

/// Central coordinator for application-wide concerns
///
/// `AppCoordinator` is the single source of truth for app initialization,
/// managing the lifecycle of dependencies, services, and navigation coordination.
/// It follows the singleton pattern and ensures proper setup order.
///
/// # Architecture Role
///
/// The AppCoordinator sits at the highest level of the application architecture:
/// ```
/// AppCoordinator (Singleton)
///     ├── DependencyContainer (Services registration)
///     ├── FlowCoordinator (Navigation management)
///     └── Services (Lifecycle management)
/// ```
///
/// # Usage
///
/// ## Basic Setup
/// ```swift
/// @main
/// struct MyApp: App {
///     init() {
///         AppCoordinator.shared.configure()
///     }
///
///     var body: some Scene {
///         WindowGroup {
///             if AppCoordinator.shared.isConfigured {
///                 ContentView()
///             }
///         }
///     }
/// }
/// ```
///
/// ## Custom Configuration
/// ```swift
/// @main
/// struct MyApp: App {
///     init() {
///         // Provide custom configuration logic
///         AppCoordinator.shared.onConfigure = {
///             // Setup theme, design system, etc.
///             ThemeManager.shared.configureDefaultTheme()
///         }
///
///         // Setup initial navigation flow
///         AppCoordinator.shared.onSetupInitialFlow = { flowCoordinator in
///             let onboardingFlow = OnboardingFlow()
///             flowCoordinator.setRootFlow(onboardingFlow)
///         }
///
///         AppCoordinator.shared.configure()
///     }
///
///     var body: some Scene {
///         WindowGroup {
///             if AppCoordinator.shared.isConfigured {
///                 AppFlowView(coordinator: AppCoordinator.shared.flowCoordinator!)
///             }
///         }
///     }
/// }
/// ```
///
/// ## Testing Setup
/// ```swift
/// class AppCoordinatorTests: XCTestCase {
///     override func setUp() {
///         super.setUp()
///
///         // Configure with test dependencies
///         AppCoordinator.shared.onConfigure = {
///             // Setup mock services for testing
///         }
///
///         AppCoordinator.shared.configure()
///     }
///
///     override func tearDown() {
///         AppCoordinator.shared.teardown()
///         super.tearDown()
///     }
///
///     func testServiceRegistration() {
///         let logger = DependencyContainer.shared.resolve(LoggerService.self)
///         XCTAssertNotNil(logger)
///     }
/// }
/// ```
///
/// ## Conditional Re-Configuration
/// ```swift
/// class AppDelegate: NSObject, UIApplicationDelegate {
///     func applicationDidBecomeActive(_ application: UIApplication) {
///         // Only configures if not already configured
///         AppCoordinator.shared.configureIfNeeded()
///     }
/// }
/// ```
///
/// # Configuration Flow
///
/// The `configure()` method executes in this order:
/// 1. Calls `onConfigure()` closure (optional app-specific setup)
/// 2. Registers core services in DependencyContainer
/// 3. Initializes FlowCoordinator for navigation
/// 4. Calls `onSetupInitialFlow()` to establish root flow
/// 5. Starts all registered services
/// 6. Sets `isConfigured = true`
///
/// # Service Registration
///
/// Default services registered:
/// - `ValidationService` → `DefaultValidationService`
/// - `AnalyticsService` → `MockAnalyticsService`
/// - `LoggerService` → `ConsoleLogger`
///
/// To add custom services:
/// ```swift
/// // In your app setup, before calling configure()
/// let container = DependencyContainer.shared
///
/// container.registerSingleton(
///     NetworkService.self,
///     instance: ProductionNetworkService()
/// )
///
/// container.register(APIClient.self) {
///     DefaultAPIClient(baseURL: "https://api.example.com")
/// }
/// ```
///
/// # Key Features
/// - **Singleton Pattern**: Single shared instance across app
/// - **Lazy Configuration**: Only configures once
/// - **Extensible Setup**: Custom closures for app-specific initialization
/// - **Service Lifecycle**: Starts services in correct order
/// - **Testable**: Teardown support for unit tests
/// - **Observable**: Published `isConfigured` for UI synchronization
///
/// # When to Use
/// - Application initialization (in `@main` or AppDelegate)
/// - Setting up dependency injection
/// - Coordinating service startups
/// - Establishing root navigation flow
/// - Test environment setup
@MainActor
public final class AppCoordinator: ObservableObject {

    // MARK: - Singleton

    /// Shared singleton instance
    ///
    /// Access the coordinator throughout the app via this property.
    /// ```swift
    /// AppCoordinator.shared.configure()
    /// let flowCoordinator = AppCoordinator.shared.flowCoordinator
    /// ```
    public static let shared = AppCoordinator()
    
    /// Determines the initial flow based on user authentication status
    /// - Returns: `MainAppFlow` if authenticated, `OnboardingFlow` if not
    public var initialFlow: (any Flow)?

    // MARK: - Published State

    /// Whether the coordinator has completed configuration
    ///
    /// Observe this to conditionally show UI:
    /// ```swift
    /// if AppCoordinator.shared.isConfigured {
    ///     ContentView()
    /// } else {
    ///     SplashScreen()
    /// }
    /// ```
    @Published public var isConfigured = false

    // MARK: - Navigation

    /// Flow coordinator instance managing app-wide navigation
    ///
    /// Created during `setupNavigation()`, manages all flows and their navigators.
    /// Each flow gets its own navigator via `FlowContext`.
    ///
    /// # Example
    /// ```swift
    /// if let flowCoordinator = AppCoordinator.shared.flowCoordinator {
    ///     let mainFlow = MainAppFlow()
    ///     flowCoordinator.setRootFlow(mainFlow)
    /// }
    /// ```
    public let flowCoordinator: FlowCoordinator = .init()

    // MARK: - Configuration Closures

    /// Optional configuration closure for app-specific setup
    ///
    /// Called at the beginning of `configure()` before any default setup.
    /// Use this for design system initialization, theme configuration, or
    /// any setup that should happen before service registration.
    ///
    /// # Example
    /// ```swift
    /// AppCoordinator.shared.onConfigure = {
    ///     ThemeManager.shared.loadTheme(.dark)
    ///     FeatureFlags.shared.initialize()
    /// }
    /// ```
    public var onConfigure: (() -> Void)?

    /// Optional initial flow setup closure
    ///
    /// Called after navigation is initialized to set up the root flow.
    /// Receives the FlowCoordinator instance for configuration.
    ///
    /// # Example
    /// ```swift
    /// AppCoordinator.shared.onSetupInitialFlow = { flowCoordinator in
    ///     let isLoggedIn = UserDefaults.app.bool(forKey: "isLoggedIn")
    ///
    ///     if isLoggedIn {
    ///         let mainFlow = MainAppFlow()
    ///         flowCoordinator.setRootFlow(mainFlow)
    ///     } else {
    ///         let onboardingFlow = OnboardingFlow()
    ///         flowCoordinator.setRootFlow(onboardingFlow)
    ///     }
    /// }
    /// ```
    public var onSetupInitialFlow: ((FlowCoordinator) -> Void)?

    // MARK: - Initialization

    /// Private initializer enforcing singleton pattern
    private init() {}

    // MARK: - Public Configuration

    /// Configures the coordinator only if not already configured
    ///
    /// Safe to call multiple times - only configures once.
    ///
    /// # Example
    /// ```swift
    /// // Safe to call in multiple places
    /// AppCoordinator.shared.configureIfNeeded()
    /// AppCoordinator.shared.configureIfNeeded() // No-op
    /// ```
    public func configureIfNeeded() {
        if !isConfigured {
            configure()
        }
    }

    /// Performs full application configuration
    ///
    /// Executes the complete setup sequence:
    /// 1. Custom configuration (`onConfigure`)
    /// 2. Dependency registration
    /// 3. Navigation setup
    /// 4. Service startup
    /// 5. Marks as configured
    ///
    /// # Example
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     init() {
    ///         AppCoordinator.shared.configure()
    ///     }
    /// }
    /// ```
    ///
    /// # Important
    /// Should be called once at app launch. Use `configureIfNeeded()`
    /// if you need idempotent configuration.
    public func configure() {
        // 1. Call optional configuration (e.g., design system setup)
        onConfigure?()

        // 2. Register core dependencies
        setupDependencies()

        // 3. Initialize navigation system
//        setupNavigation()

        // 4. Start registered services
        startServices()

        // 5. Mark as configured
        isConfigured = true
    }

    // MARK: - Private Setup Methods

    /// Registers core services in the dependency container
    ///
    /// Default registrations:
    /// - `ValidationService` → `DefaultValidationService` (singleton)
    /// - `AnalyticsService` → `MockAnalyticsService` (singleton)
    /// - `LoggerService` → `ConsoleLogger` (singleton)
    ///
    /// Override or extend by registering services before calling `configure()`:
    /// ```swift
    /// let container = DependencyContainer.shared
    /// container.registerSingleton(
    ///     AnalyticsService.self,
    ///     instance: FirebaseAnalyticsService()
    /// )
    /// AppCoordinator.shared.configure()
    /// ```
    private func setupDependencies() {
        let container = DependencyContainer.shared

        // Register Validation Service
        container.registerSingleton(
            ValidationService.self,
            instance: DefaultValidationService()
        )

        // Register Analytics Service (Mock for development)
        container.registerSingleton(
            AnalyticsService.self,
            instance: MockAnalyticsService()
        )

        // Register Logger Service
        container.registerSingleton(
            LoggerService.self,
            instance: ConsoleLogger()
        )


        // Add more service registrations as needed
        // Example: container.registerSingleton(NetworkService.self, instance: DefaultNetworkService())
    }

    public func configureFlow() {
        self.setupNavigation()
    }
    
    /// Initializes navigation system
    ///
    /// Creates the FlowCoordinator and optionally sets up the initial flow
    /// via the `onSetupInitialFlow` closure.
    ///
    /// Each flow managed by FlowCoordinator gets its own navigator
    /// through the FlowContext system.
    private func setupNavigation() {
        // Create flow coordinator (each flow will have its own navigator via FlowContext)
        // Call optional initial flow setup
        onSetupInitialFlow?(flowCoordinator)
    }

    /// Starts all registered services
    ///
    /// Calls `start()` on services that require initialization.
    /// Services are started in order:
    /// 1. AnalyticsService
    /// 2. LoggerService
    ///
    /// The logger logs a confirmation message when startup completes.
    private func startServices() {
        // Start analytics service
        let analytics = DependencyContainer.shared.resolve(AnalyticsService.self)
        analytics.start()

        // Start logger service
        let logger = DependencyContainer.shared.resolve(LoggerService.self)
        logger.start()
        logger.info("App Coordinator: Services started successfully")
    }

    // MARK: - Teardown

    /// Tears down the coordinator for cleanup or testing
    ///
    /// Stops all services and resets configuration state.
    /// Useful in unit tests to ensure clean state between tests.
    ///
    /// # Example
    /// ```swift
    /// class MyTests: XCTestCase {
    ///     override func tearDown() {
    ///         AppCoordinator.shared.teardown()
    ///         super.tearDown()
    ///     }
    /// }
    /// ```
    ///
    /// # Services Stopped
    /// - AnalyticsService
    /// - LoggerService
    /// - Any other services that override `stop()`
    public func teardown() {
        // Stop analytics service
        let analytics = DependencyContainer.shared.resolveOptional(AnalyticsService.self)
        analytics?.stop()

        // Stop logger service
        let logger = DependencyContainer.shared.resolveOptional(LoggerService.self)
        logger?.stop()

        // Reset configuration state
        isConfigured = false
    }
}

// MARK: - Architecture Notes

/*
 # Navigation Architecture

 AppCoordinator creates the FlowCoordinator, which manages application flows.
 Each flow gets its own SwiftUINavigator via FlowContext.

 Flow hierarchy:
 ```
 AppCoordinator
     └── FlowCoordinator
         ├── RootFlow (e.g., OnboardingFlow)
         │   └── SwiftUINavigator (per flow)
         └── Subflows (e.g., MainAppFlow)
             └── SwiftUINavigator (per flow)
 ```

 # Feature Module Integration

 Features register their routers during app startup:
 ```swift
 // In feature module setup
 AppCoordinator.shared.onConfigure = {
     FeatureRouterRegistry.shared.register(ProductRouter.self)
     FeatureRouterRegistry.shared.register(CheckoutRouter.self)
 }
 ```

 # Service Extension

 Add custom services by registering before `configure()`:
 ```swift
 let container = DependencyContainer.shared

 // Register custom services
 container.registerSingleton(
     AuthenticationService.self,
     instance: FirebaseAuthService()
 )

 container.register(ImageCache.self) {
     NSCacheImageCache()
 }

 // Then configure
 AppCoordinator.shared.configure()
 ```

 # Testing Pattern

 ```swift
 class FeatureTests: XCTestCase {
     override func setUp() {
         // Setup test dependencies
         AppCoordinator.shared.onConfigure = {
             DependencyContainer.shared.registerSingleton(
                 AnalyticsService.self,
                 instance: MockAnalyticsService()
             )
         }
         AppCoordinator.shared.configure()
     }

     override func tearDown() {
         AppCoordinator.shared.teardown()
     }
 }
 ```
 */
