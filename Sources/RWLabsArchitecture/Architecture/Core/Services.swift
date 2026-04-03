//
//  Services.swift
//  RWLabsArchitecture
//
//  Core service protocols and implementations
//  Provides foundational service abstractions for dependency injection
//

import Foundation
import Combine

// MARK: - Service Protocol

/// Base protocol for application services with lifecycle management
///
/// `Service` provides a common interface for services that require
/// initialization and cleanup, enabling centralized lifecycle management
/// through the AppCoordinator.
///
/// # Usage
///
/// ## Basic Service Implementation
/// ```swift
/// class LocationService: Service {
///     private let locationManager = CLLocationManager()
///
///     func start() {
///         locationManager.requestWhenInUseAuthorization()
///         locationManager.startUpdatingLocation()
///     }
///
///     func stop() {
///         locationManager.stopUpdatingLocation()
///     }
/// }
/// ```
///
/// ## Stateless Service
/// ```swift
/// class MathService: Service {
///     // No lifecycle needed - default empty implementations used
///     func calculate(_ expression: String) -> Double {
///         // Perform calculation
///     }
/// }
/// ```
///
/// ## Service with Dependencies
/// ```swift
/// class NetworkService: Service {
///     @Injected var logger: LoggerService
///     private var session: URLSession?
///
///     func start() {
///         session = URLSession(configuration: .default)
///         logger.info("Network service started")
///     }
///
///     func stop() {
///         session?.invalidateAndCancel()
///         session = nil
///         logger.info("Network service stopped")
///     }
/// }
/// ```
///
/// # Key Features
/// - **Lifecycle Management**: Standard start/stop methods
/// - **Optional Implementation**: Default empty implementations provided
/// - **Composable**: Services can depend on other services
/// - **Testable**: Easy to mock for unit tests
///
/// # When to Use
/// - Services requiring initialization (networking, location, databases)
/// - Resources needing cleanup (file handles, subscriptions)
/// - Background tasks with explicit lifecycle
/// - Services coordinated by AppCoordinator
public protocol Service {
    /// Called to initialize and start the service
    func start()

    /// Called to cleanup and stop the service
    func stop()
}

/// Default implementations making lifecycle methods optional
public extension Service {
    /// Default empty implementation - override when initialization is needed
    func start() {}

    /// Default empty implementation - override when cleanup is needed
    func stop() {}
}

// MARK: - Repository Protocol

/// Generic data access protocol for CRUD operations
///
/// `Repository` provides a standard interface for data persistence,
/// abstracting the underlying storage mechanism (database, network, file system).
///
/// # Usage
///
/// ## In-Memory Repository
/// ```swift
/// class InMemoryUserRepository: Repository {
///     typealias Entity = User
///     typealias ID = String
///
///     private var storage: [ID: User] = [:]
///
///     func fetch(id: ID) async throws -> User {
///         guard let user = storage[id] else {
///             throw RepositoryError.notFound
///         }
///         return user
///     }
///
///     func fetchAll() async throws -> [User] {
///         Array(storage.values)
///     }
///
///     func save(_ entity: User) async throws {
///         storage[entity.id] = entity
///     }
///
///     func delete(id: ID) async throws {
///         storage.removeValue(forKey: id)
///     }
/// }
/// ```
///
/// ## Network Repository
/// ```swift
/// class APIProductRepository: Repository {
///     typealias Entity = Product
///     typealias ID = Int
///
///     @Injected var apiClient: APIClient
///
///     func fetch(id: ID) async throws -> Product {
///         try await apiClient.get("/products/\(id)")
///     }
///
///     func fetchAll() async throws -> [Product] {
///         try await apiClient.get("/products")
///     }
///
///     func save(_ entity: Product) async throws {
///         if entity.id == 0 {
///             try await apiClient.post("/products", body: entity)
///         } else {
///             try await apiClient.put("/products/\(entity.id)", body: entity)
///         }
///     }
///
///     func delete(id: ID) async throws {
///         try await apiClient.delete("/products/\(id)")
///     }
/// }
/// ```
///
/// ## Core Data Repository
/// ```swift
/// class CoreDataTaskRepository: Repository {
///     typealias Entity = Task
///     typealias ID = UUID
///
///     private let context: NSManagedObjectContext
///
///     init(context: NSManagedObjectContext) {
///         self.context = context
///     }
///
///     func fetch(id: ID) async throws -> Task {
///         let request = TaskEntity.fetchRequest()
///         request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
///         let entities = try context.fetch(request)
///         guard let entity = entities.first else {
///             throw RepositoryError.notFound
///         }
///         return Task(from: entity)
///     }
///
///     func fetchAll() async throws -> [Task] {
///         let request = TaskEntity.fetchRequest()
///         let entities = try context.fetch(request)
///         return entities.map { Task(from: $0) }
///     }
///
///     func save(_ entity: Task) async throws {
///         let taskEntity = TaskEntity(context: context)
///         taskEntity.update(from: entity)
///         try context.save()
///     }
///
///     func delete(id: ID) async throws {
///         let task = try await fetch(id: id)
///         // Delete from Core Data
///         try context.save()
///     }
/// }
/// ```
///
/// # Key Features
/// - **Generic**: Works with any entity type
/// - **Async/Await**: Modern concurrency support
/// - **Testable**: Easy to create mock repositories
/// - **Storage-Agnostic**: Abstract away storage implementation
///
/// # When to Use
/// - Data access layer abstraction
/// - Switching between different storage backends
/// - Testing with mock data
/// - Clean architecture separation
//public protocol Repository {
//    /// The entity type this repository manages
//    associatedtype Entity
//
//    /// The identifier type for entities
//    associatedtype ID: Hashable
//
//    /// Fetches a single entity by ID
//    /// - Parameter id: The entity identifier
//    /// - Returns: The entity if found
//    /// - Throws: Error if entity not found or fetch fails
//    func fetch(id: ID) async throws -> Entity
//
//    /// Fetches all entities
//    /// - Returns: Array of all entities
//    /// - Throws: Error if fetch fails
//    func fetchAll() async throws -> [Entity]
//
//    /// Saves an entity (creates or updates)
//    /// - Parameter entity: The entity to save
//    /// - Throws: Error if save fails
//    func save(_ entity: Entity) async throws
//
//    /// Deletes an entity by ID
//    /// - Parameter id: The entity identifier to delete
//    /// - Throws: Error if delete fails
//    func delete(id: ID) async throws
//}

// MARK: - Validation Service

/// Service for validating string inputs against rules
///
/// `ValidationService` provides flexible validation logic for forms,
/// user input, and data integrity checks.
///
/// # Usage
///
/// ## Form Validation
/// ```swift
/// class RegistrationViewModel: ObservableObject {
///     @Injected var validator: ValidationService
///
///     func validateForm(email: String, password: String) -> Bool {
///         let emailResult = validator.validate(email, rules: [
///             .required,
///             .email
///         ])
///
///         let passwordResult = validator.validate(password, rules: [
///             .required,
///             .minLength(8),
///             .custom({ $0.contains(where: { $0.isNumber }) },
///                     errorMessage: "Must contain at least one number")
///         ])
///
///         return emailResult.isValid && passwordResult.isValid
///     }
/// }
/// ```
///
/// ## Real-Time Validation
/// ```swift
/// class LoginView: View {
///     @Injected var validator: ValidationService
///     @State private var username: String = ""
///     @State private var errors: [String] = []
///
///     var body: some View {
///         TextField("Username", text: $username)
///             .onChange(of: username) { newValue in
///                 let result = validator.validate(newValue, rules: [
///                     .required,
///                     .minLength(3)
///                 ])
///                 errors = result.errors
///             }
///
///         ForEach(errors, id: \.self) { error in
///             Text(error).foregroundColor(.red)
///         }
///     }
/// }
/// ```
public protocol ValidationService {
    /// Validates a string against multiple rules
    /// - Parameters:
    ///   - value: The string to validate
    ///   - rules: Array of validation rules to apply
    /// - Returns: ValidationResult with validity status and errors
    func validate(_ value: String, rules: [ValidationRule]) -> ValidationResult
}

/// Predefined and custom validation rules
///
/// # Available Rules
/// - `.required` - Value must not be empty
/// - `.minLength(Int)` - Minimum character length
/// - `.maxLength(Int)` - Maximum character length
/// - `.email` - Valid email format
/// - `.phone` - Valid phone number (10-15 digits)
/// - `.custom((String) -> Bool, errorMessage: String)` - Custom validation logic
public enum ValidationRule {
    /// Value must not be empty (after trimming whitespace)
    case required

    /// Minimum character length
    case minLength(Int)

    /// Maximum character length
    case maxLength(Int)

    /// Valid email format (RFC 5322 simplified)
    case email

    /// Valid phone number (10-15 digits)
    case phone

    /// Custom validation with predicate and error message
    case custom((String) -> Bool, errorMessage: String)
}

/// Result of a validation operation
///
/// # Usage
/// ```swift
/// let result = validator.validate(email, rules: [.required, .email])
/// if result.isValid {
///     // Proceed with valid email
/// } else {
///     // Show errors
///     result.errors.forEach { print($0) }
/// }
/// ```
public struct ValidationResult: Sendable {
    /// Whether validation passed
    public let isValid: Bool

    /// Array of error messages (empty if valid)
    public let errors: [String]

    /// Convenience constant for valid result
    public static let valid = ValidationResult(isValid: true, errors: [])

    /// Creates an invalid result with errors
    /// - Parameter errors: Array of error messages
    /// - Returns: ValidationResult marked as invalid
    public static func invalid(_ errors: [String]) -> ValidationResult {
        ValidationResult(isValid: false, errors: errors)
    }
}

/// Default implementation of ValidationService
///
/// Provides standard validation logic for common use cases.
/// Register as singleton in DependencyContainer:
///
/// ```swift
/// DependencyContainer.shared.registerSingleton(
///     ValidationService.self,
///     instance: DefaultValidationService()
/// )
/// ```
public final class DefaultValidationService: ValidationService {
    public init() {}

    public func validate(_ value: String, rules: [ValidationRule]) -> ValidationResult {
        var errors: [String] = []

        for rule in rules {
            switch rule {
            case .required:
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append("This field is required")
                }

            case .minLength(let length):
                if value.count < length {
                    errors.append("Minimum length is \(length) characters")
                }

            case .maxLength(let length):
                if value.count > length {
                    errors.append("Maximum length is \(length) characters")
                }

            case .email:
                let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
                let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
                if !emailPredicate.evaluate(with: value) {
                    errors.append("Invalid email format")
                }

            case .phone:
                let phoneRegex = "^[0-9]{10,15}$"
                let phonePredicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
                if !phonePredicate.evaluate(with: value) {
                    errors.append("Invalid phone number")
                }

            case .custom(let validator, let errorMessage):
                if !validator(value) {
                    errors.append(errorMessage)
                }
            }
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }
}

// MARK: - Analytics Service

/// Service for tracking user behavior and app events
///
/// `AnalyticsService` provides a unified interface for analytics
/// platforms (Firebase, Mixpanel, Amplitude, etc.).
///
/// # Usage
///
/// ## Event Tracking
/// ```swift
/// class ProductViewModel: ObservableObject {
///     @Injected var analytics: AnalyticsService
///
///     func viewProduct(_ product: Product) {
///         analytics.trackEvent("product_viewed", parameters: [
///             "product_id": product.id,
///             "product_name": product.name,
///             "category": product.category,
///             "price": product.price
///         ])
///     }
///
///     func addToCart(_ product: Product) {
///         analytics.trackEvent("add_to_cart", parameters: [
///             "product_id": product.id,
///             "quantity": 1
///         ])
///     }
/// }
/// ```
///
/// ## Screen Tracking
/// ```swift
/// struct ProductListView: View {
///     @Injected var analytics: AnalyticsService
///
///     var body: some View {
///         List {
///             // Product list content
///         }
///         .onAppear {
///             analytics.trackScreen("product_list")
///         }
///     }
/// }
/// ```
///
/// ## User Properties
/// ```swift
/// class AuthenticationService {
///     @Injected var analytics: AnalyticsService
///
///     func login(user: User) {
///         analytics.setUserProperty("user_id", value: user.id)
///         analytics.setUserProperty("user_type", value: user.accountType)
///         analytics.setUserProperty("sign_up_date", value: user.signUpDate.iso8601)
///     }
/// }
/// ```
public protocol AnalyticsService: Service {
    /// Tracks a custom event with optional parameters
    /// - Parameters:
    ///   - name: Event name (e.g., "button_clicked", "purchase_completed")
    ///   - parameters: Optional dictionary of event properties
    func trackEvent(_ name: String, parameters: [String: Any]?)

    /// Tracks a screen view
    /// - Parameter name: Screen name (e.g., "home", "product_detail")
    func trackScreen(_ name: String)

    /// Sets a user property for analytics
    /// - Parameters:
    ///   - name: Property name (e.g., "user_type", "subscription_level")
    ///   - value: Property value
    func setUserProperty(_ name: String, value: String)
}

/// Mock analytics service for development and testing
///
/// Prints analytics calls to console instead of sending to external service.
/// Useful for:
/// - Local development
/// - Unit tests
/// - Debugging analytics implementation
///
/// # Registration
/// ```swift
/// #if DEBUG
/// DependencyContainer.shared.registerSingleton(
///     AnalyticsService.self,
///     instance: MockAnalyticsService()
/// )
/// #else
/// DependencyContainer.shared.registerSingleton(
///     AnalyticsService.self,
///     instance: FirebaseAnalyticsService()
/// )
/// #endif
/// ```
public final class MockAnalyticsService: AnalyticsService {
    public init() {}

    public func trackEvent(_ name: String, parameters: [String: Any]?) {
        print("[Analytics] Event: \(name), Parameters: \(parameters ?? [:])")
    }

    public func trackScreen(_ name: String) {
        print("[Analytics] Screen: \(name)")
    }

    public func setUserProperty(_ name: String, value: String) {
        print("[Analytics] User Property: \(name) = \(value)")
    }
}

// MARK: - Logger Service

/// Service for application logging with severity levels
///
/// `LoggerService` provides structured logging for debugging,
/// monitoring, and error tracking.
///
/// # Usage
///
/// ## Basic Logging
/// ```swift
/// class NetworkManager {
///     @Injected var logger: LoggerService
///
///     func fetchData() async {
///         logger.debug("Starting data fetch")
///
///         do {
///             let data = try await URLSession.shared.data(from: url)
///             logger.info("Fetched \(data.count) bytes")
///         } catch {
///             logger.error("Failed to fetch data", error: error)
///         }
///     }
/// }
/// ```
///
/// ## Severity Levels
/// ```swift
/// class PaymentProcessor {
///     @Injected var logger: LoggerService
///
///     func processPayment(_ amount: Double) {
///         logger.debug("Payment processing started: $\(amount)")
///
///         if amount > 1000 {
///             logger.warning("Large payment amount: $\(amount)")
///         }
///
///         // Process payment
///         logger.info("Payment processed successfully: $\(amount)")
///     }
/// }
/// ```
///
/// ## Error Logging
/// ```swift
/// do {
///     try performOperation()
///     logger.info("Operation completed")
/// } catch {
///     logger.error("Operation failed", error: error)
/// }
/// ```
public protocol LoggerService: Service {
    /// Logs a message with a specific severity level
    /// - Parameters:
    ///   - message: The log message
    ///   - level: Severity level
    func log(_ message: String, level: LogLevel)

    /// Logs a debug message (verbose, development only)
    /// - Parameter message: Debug message
    func debug(_ message: String)

    /// Logs an informational message
    /// - Parameter message: Info message
    func info(_ message: String)

    /// Logs a warning message
    /// - Parameter message: Warning message
    func warning(_ message: String)

    /// Logs an error message with optional Error object
    /// - Parameters:
    ///   - message: Error description
    ///   - error: Optional Error object for details
    func error(_ message: String, error: Error?)
}

/// Log severity levels
///
/// Used to categorize log messages by importance:
/// - `debug`: Verbose diagnostic information (development only)
/// - `info`: General informational messages
/// - `warning`: Warning messages for potential issues
/// - `error`: Error messages for failures
public enum LogLevel: String {
    /// Verbose diagnostic information
    case debug = "DEBUG"

    /// General informational messages
    case info = "INFO"

    /// Warning messages for potential issues
    case warning = "WARNING"

    /// Error messages for failures
    case error = "ERROR"
}

/// Console-based logger implementation
///
/// Prints log messages to the console with level prefixes.
/// Suitable for development and debugging.
///
/// # Registration
/// ```swift
/// DependencyContainer.shared.registerSingleton(
///     LoggerService.self,
///     instance: ConsoleLogger()
/// )
/// ```
///
/// # Output Format
/// ```
/// [DEBUG] User tapped login button
/// [INFO] Authentication successful
/// [WARNING] API response took 5.2 seconds
/// [ERROR] Network request failed - Error: No internet connection
/// ```
public final class ConsoleLogger: LoggerService {
    public init() {}

    public func log(_ message: String, level: LogLevel) {
        print("[\(level.rawValue)] \(message)")
    }

    public func debug(_ message: String) {
        log(message, level: .debug)
    }

    public func info(_ message: String) {
        log(message, level: .info)
    }

    public func warning(_ message: String) {
        log(message, level: .warning)
    }

    public func error(_ message: String, error: Error?) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - Error: \(error.localizedDescription)"
        }
        log(fullMessage, level: .error)
    }
}
