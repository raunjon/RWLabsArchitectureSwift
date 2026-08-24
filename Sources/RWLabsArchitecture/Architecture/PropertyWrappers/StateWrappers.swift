//
//  StateWrappers.swift
//  RWLabsArchitecture
//
//  Custom property wrappers for state management and validation
//  Provides convenient utilities for common state manipulation patterns
//

import Foundation
import Combine

// MARK: - @Validated Property Wrapper

/// Validates values before allowing state updates
///
/// `@Validated` ensures that only values passing validation are set,
/// rejecting invalid values and optionally notifying when validation fails.
///
/// # Usage
///
/// ## Email Validation
/// ```swift
/// class RegistrationViewModel: ObservableObject {
///     @Validated(
///         wrappedValue: "",
///         validator: { email in
///             email.contains("@") && email.contains(".")
///         },
///         onValidationFailed: { invalidEmail in
///             print("Invalid email: \(invalidEmail)")
///         }
///     )
///     var email: String
///
///     func register() {
///         // Check if current value is valid
///         if $email {  // projected value returns validation state
///             performRegistration(email: email)
///         }
///     }
/// }
/// ```
///
/// ## Age Range Validation
/// ```swift
/// struct UserProfile {
///     @Validated(
///         wrappedValue: 18,
///         validator: { age in (18...120).contains(age) }
///     )
///     var age: Int
///
///     mutating func setAge(_ newAge: Int) {
///         age = newAge  // Only sets if 18-120
///         print("Is valid: \($age)")  // Check validation state
///     }
/// }
/// ```
///
/// ## Form Field Validation
/// ```swift
/// class FormViewModel: ObservableObject {
///     @Validated(
///         wrappedValue: "",
///         validator: { $0.count >= 8 },
///         onValidationFailed: { _ in
///             self.showError = "Password must be at least 8 characters"
///         }
///     )
///     var password: String
///
///     @Published var showError: String = ""
///
///     var isValid: Bool {
///         $password  // Check if current password is valid
///     }
/// }
/// ```
///
/// # Key Features
/// - **Validation Enforcement**: Rejects invalid values, keeping state valid
/// - **Projected Value**: Returns Bool indicating current value's validity
/// - **Failure Callback**: Optional closure called when validation fails
/// - **Type-Safe**: Works with any type
///
/// # When to Use
/// - User input validation (email, phone, password)
/// - Business rule enforcement (age ranges, quantity limits)
/// - Configuration value validation
/// - Form field validation
@propertyWrapper
public struct Validated<Value> {

    // MARK: - Properties

    /// The current validated value
    private var value: Value

    /// Validation predicate that determines if a value is valid
    private let validator: (Value) -> Bool

    /// Optional closure called when validation fails
    private let onValidationFailed: ((Value) -> Void)?

    // MARK: - Initialization

    /// Initializes with a default value and validation rules
    ///
    /// - Parameters:
    ///   - wrappedValue: Initial value (not validated on init)
    ///   - validator: Closure that returns true if value is valid
    ///   - onValidationFailed: Optional closure called when validation fails
    ///
    /// # Example
    /// ```swift
    /// @Validated(
    ///     wrappedValue: "",
    ///     validator: { $0.count >= 3 },
    ///     onValidationFailed: { print("Too short: \($0)") }
    /// )
    /// var username: String
    /// ```
    public init(
        wrappedValue: Value,
        validator: @escaping (Value) -> Bool,
        onValidationFailed: ((Value) -> Void)? = nil
    ) {
        self.value = wrappedValue
        self.validator = validator
        self.onValidationFailed = onValidationFailed
    }

    // MARK: - Property Wrapper

    /// The wrapped value, validated on set
    ///
    /// When setting a new value:
    /// - If validation passes, the value is updated
    /// - If validation fails, the value remains unchanged and `onValidationFailed` is called
    public var wrappedValue: Value {
        get { value }
        set {
            if validator(newValue) {
                value = newValue
            } else {
                onValidationFailed?(newValue)
            }
        }
    }

    /// Returns whether the current value is valid
    ///
    /// # Example
    /// ```swift
    /// @Validated(wrappedValue: "test", validator: { $0.count > 5 })
    /// var text: String
    ///
    /// if $text {  // false, "test" has only 4 characters
    ///     print("Valid!")
    /// }
    /// ```
    public var projectedValue: Bool {
        validator(value)
    }
}

// MARK: - @Clamped Property Wrapper

/// Automatically clamps values to a specified range
///
/// `@Clamped` ensures values never exceed their bounds, automatically
/// adjusting out-of-range values to the nearest valid value.
///
/// # Usage
///
/// ## Volume Control
/// ```swift
/// class AudioPlayer: ObservableObject {
///     @Clamped(wrappedValue: 50, 0...100)
///     var volume: Int
///
///     func increaseVolume(by amount: Int) {
///         volume += amount  // Automatically clamped to 100
///     }
///
///     func decreaseVolume(by amount: Int) {
///         volume -= amount  // Automatically clamped to 0
///     }
/// }
/// ```
///
/// ## Progress Indicator
/// ```swift
/// struct ProgressBar {
///     @Clamped(wrappedValue: 0.0, 0.0...1.0)
///     var progress: Double
///
///     mutating func setProgress(_ value: Double) {
///         progress = value  // Always between 0.0 and 1.0
///     }
/// }
/// ```
///
/// ## Rating System
/// ```swift
/// class ReviewViewModel: ObservableObject {
///     @Clamped(wrappedValue: 3, 1...5)
///     var rating: Int
///
///     func adjustRating(by delta: Int) {
///         rating += delta  // Stays within 1-5
///     }
/// }
/// ```
///
/// # Key Features
/// - **Automatic Clamping**: Values are clamped on both init and set
/// - **No Errors**: Never throws or fails, always provides valid value
/// - **Type-Safe**: Works with any Comparable type (Int, Double, Date, etc.)
/// - **Range Preservation**: Range is immutable after initialization
///
/// # When to Use
/// - Volume/brightness controls
/// - Progress indicators
/// - Rating systems
/// - Game statistics (health, mana, experience)
/// - Slider-backed values
@propertyWrapper
public struct Clamped<Value: Comparable> {

    // MARK: - Properties

    /// The clamped value
    private var value: Value

    /// The allowed range for values
    private let range: ClosedRange<Value>

    // MARK: - Initialization

    /// Initializes with a value and clamping range
    ///
    /// - Parameters:
    ///   - wrappedValue: Initial value (will be clamped to range)
    ///   - range: The allowed range for values
    ///
    /// # Example
    /// ```swift
    /// @Clamped(wrappedValue: 150, 0...100)
    /// var percentage: Int  // Initialized to 100, not 150
    /// ```
    public init(wrappedValue: Value, _ range: ClosedRange<Value>) {
        self.range = range
        // Clamp initial value to range
        self.value = min(max(wrappedValue, range.lowerBound), range.upperBound)
    }

    // MARK: - Property Wrapper

    /// The wrapped value, automatically clamped to range
    ///
    /// When setting a new value:
    /// - If below lower bound, uses lower bound
    /// - If above upper bound, uses upper bound
    /// - Otherwise, uses the provided value
    public var wrappedValue: Value {
        get { value }
        set {
            value = min(max(newValue, range.lowerBound), range.upperBound)
        }
    }
}

// MARK: - @Trimmed Property Wrapper

/// Automatically trims whitespace and newlines from strings
///
/// `@Trimmed` ensures strings never have leading or trailing whitespace,
/// automatically cleaning values on initialization and assignment.
///
/// # Usage
///
/// ## User Input Cleanup
/// ```swift
/// class LoginViewModel: ObservableObject {
///     @Trimmed var username: String = ""
///     @Trimmed var password: String = ""
///
///     func login() {
///         // username and password are guaranteed to have no whitespace
///         authenticate(username: username, password: password)
///     }
/// }
/// ```
///
/// ## Form Field Processing
/// ```swift
/// struct ContactForm {
///     @Trimmed var name: String = ""
///     @Trimmed var email: String = ""
///     @Trimmed var message: String = ""
///
///     mutating func processInput(_ text: String) {
///         name = text  // " John Doe \n" becomes "John Doe"
///     }
/// }
/// ```
///
/// ## Search Query Cleanup
/// ```swift
/// class SearchViewModel: ObservableObject {
///     @Trimmed var query: String = ""
///
///     func search() {
///         guard !query.isEmpty else { return }
///         performSearch(query: query)  // No leading/trailing spaces
///     }
/// }
/// ```
///
/// # Key Features
/// - **Automatic Trimming**: Trims on both init and set
/// - **Whitespace Removal**: Removes spaces, tabs, newlines
/// - **No Manual Cleanup**: Eliminates need for .trimmingCharacters(in:) calls
/// - **String-Specific**: Optimized for String type
///
/// # When to Use
/// - User text input fields
/// - Search queries
/// - Form data processing
/// - API request parameters
/// - Configuration file parsing
@propertyWrapper
public struct Trimmed {

    // MARK: - Properties

    /// The trimmed string value
    private var value: String

    // MARK: - Initialization

    /// Initializes with a string, trimming whitespace
    ///
    /// - Parameter wrappedValue: Initial string (will be trimmed)
    ///
    /// # Example
    /// ```swift
    /// @Trimmed var name: String = "  John Doe  \n"
    /// // name is now "John Doe"
    /// ```
    public init(wrappedValue: String) {
        self.value = wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Property Wrapper

    /// The wrapped string, automatically trimmed
    ///
    /// When setting a new value, whitespace and newlines are automatically
    /// removed from both ends of the string.
    public var wrappedValue: String {
        get { value }
        set {
            value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

// MARK: - @Debounced Property Wrapper

/// Debounces rapid value changes, emitting only after a delay
///
/// `@Debounced` delays propagation of value changes until a specified
/// time has passed without new changes. Perfect for search-as-you-type
/// and other scenarios where you want to wait for user input to stabilize.
///
/// # Usage
///
/// ## Search Field
/// ```swift
/// class SearchViewModel: ObservableObject {
///     @Debounced(wrappedValue: "", delay: 0.5)
///     var searchQuery: String
///
///     private var cancellables = Set<AnyCancellable>()
///
///     init() {
///         // Listen to debounced changes
///         $searchQuery.sink { [weak self] query in
///             self?.performSearch(query: query)
///         }
///         .store(in: &cancellables)
///     }
///
///     func performSearch(query: String) {
///         // Only called 0.5s after user stops typing
///     }
/// }
/// ```
///
/// ## Auto-Save
/// ```swift
/// class DocumentEditor: ObservableObject {
///     @Debounced(wrappedValue: "", delay: 2.0)
///     var documentText: String
///
///     private var cancellables = Set<AnyCancellable>()
///
///     init() {
///         $documentText.sink { [weak self] text in
///             self?.autoSave(text: text)
///         }
///         .store(in: &cancellables)
///     }
/// }
/// ```
///
/// ## Real-time Validation
/// ```swift
/// class RegistrationViewModel: ObservableObject {
///     @Debounced(wrappedValue: "", delay: 0.3)
///     var username: String
///
///     init() {
///         $username.sink { [weak self] username in
///             self?.checkUsernameAvailability(username)
///         }
///         .store(in: &cancellables)
///     }
/// }
/// ```
///
/// # Key Features
/// - **Reactive**: Returns Combine publisher via projected value ($)
/// - **Configurable Delay**: Customize debounce time per property
/// - **Main Thread**: Debounced values emitted on main queue
/// - **Immediate Access**: `wrappedValue` provides immediate (non-debounced) access
///
/// # When to Use
/// - Search-as-you-type functionality
/// - Auto-save features
/// - Real-time form validation
/// - API call throttling
/// - Live text filtering
///
/// # When NOT to Use
/// - When you need every value change (use `@Published` instead)
/// - For non-reactive properties
/// - When debouncing should be per-action, not per-property
@propertyWrapper
public struct Debounced<Value> {

    // MARK: - Properties

    /// The current (immediate) value
    private var value: Value

    /// The debounce delay in seconds
    private let delay: TimeInterval

    /// Cancellable for the debounce subscription
    private var cancellable: AnyCancellable?

    /// Subject that receives immediate value changes
    private let valueSubject: CurrentValueSubject<Value, Never>

    /// Subject that emits debounced values
    private let debouncedSubject: PassthroughSubject<Value, Never>

    // MARK: - Initialization

    /// Initializes with a value and debounce delay
    ///
    /// - Parameters:
    ///   - wrappedValue: Initial value
    ///   - delay: Time to wait after last change before emitting (default: 0.3s)
    ///
    /// # Example
    /// ```swift
    /// @Debounced(wrappedValue: "", delay: 0.5)
    /// var searchText: String
    ///
    /// // Changes to searchText are debounced by 0.5 seconds
    /// $searchText.sink { debouncedText in
    ///     print("Search for: \(debouncedText)")
    /// }
    /// ```
    public init(wrappedValue: Value, delay: TimeInterval = 0.3) {
        self.value = wrappedValue
        self.delay = delay
        self.valueSubject = CurrentValueSubject(wrappedValue)
        self.debouncedSubject = PassthroughSubject()

        // Set up debounce pipeline
        self.cancellable = valueSubject
            .debounce(for: .seconds(delay), scheduler: DispatchQueue.main)
            .sink { [debouncedSubject] in
                debouncedSubject.send($0)
            }
    }

    // MARK: - Property Wrapper

    /// The wrapped value (immediate, not debounced)
    ///
    /// Reading returns the current value immediately.
    /// Writing updates the value and triggers debounced emission.
    public var wrappedValue: Value {
        get { value }
        set {
            value = newValue
            valueSubject.send(newValue)
        }
    }

    /// Publisher that emits debounced value changes
    ///
    /// Subscribe to this to receive values only after the debounce delay
    /// has passed without new changes.
    ///
    /// # Example
    /// ```swift
    /// $searchQuery.sink { query in
    ///     // Only called after 0.3s of no changes
    /// }
    /// ```
    public var projectedValue: AnyPublisher<Value, Never> {
        debouncedSubject.eraseToAnyPublisher()
    }
}

// MARK: - @Atomic Property Wrapper

/// Thread-safe property wrapper using locks
///
/// `@Atomic` provides thread-safe access to values, preventing data races
/// when multiple threads read/write the same property concurrently.
///
/// # Usage
///
/// ## Shared Counter
/// ```swift
/// class Analytics {
///     @Atomic var eventCount: Int = 0
///
///     func trackEvent() {
///         // Thread-safe increment
///         $eventCount.mutate { count in
///             count += 1
///         }
///     }
///
///     func getCount() -> Int {
///         eventCount  // Thread-safe read
///     }
/// }
/// ```
///
/// ## Background Task State
/// ```swift
/// class TaskManager {
///     @Atomic var isProcessing: Bool = false
///
///     func startTask() {
///         DispatchQueue.global().async {
///             self.isProcessing = true  // Thread-safe write
///             self.performWork()
///             self.isProcessing = false
///         }
///     }
///
///     var canStartNewTask: Bool {
///         !isProcessing  // Thread-safe read
///     }
/// }
/// ```
///
/// ## Cache Management
/// ```swift
/// class ImageCache {
///     @Atomic var cachedImages: [String: UIImage] = [:]
///
///     func cacheImage(_ image: UIImage, forKey key: String) {
///         // Thread-safe mutation
///         $cachedImages.mutate { cache in
///             cache[key] = image
///         }
///     }
///
///     func getImage(forKey key: String) -> UIImage? {
///         cachedImages[key]  // Thread-safe read
///     }
/// }
/// ```
///
/// # Key Features
/// - **Thread-Safe**: Uses NSRecursiveLock for synchronization
/// - **Recursive**: Same thread can acquire lock multiple times
/// - **Projected Value**: Provides `mutate(_:)` method for atomic mutations
/// - **Zero Config**: Just add the wrapper, thread safety is automatic
///
/// # When to Use
/// - Shared state accessed from multiple threads
/// - Background task coordination
/// - Counters and statistics
/// - Cache implementations
/// - Resource pools
///
/// # When NOT to Use
/// - Single-threaded code (unnecessary overhead)
/// - When you need reader-writer locks (use DispatchQueue instead)
/// - SwiftUI @State properties (already thread-safe)
/// - Actor-isolated properties (actors provide better isolation)
///
/// # Performance Note
/// Locking has overhead. For high-contention scenarios, consider:
/// - Swift Actors (language-level concurrency)
/// - Dispatch queues with barriers
/// - Lock-free algorithms
@propertyWrapper
public struct Atomic<Value> {

    // MARK: - Properties

    /// The underlying value, protected by a lock
    private var value: Value

    /// Recursive lock for thread-safe access
    ///
    /// NSRecursiveLock allows the same thread to acquire the lock multiple times,
    /// preventing deadlocks when accessing the property recursively.
    private let lock = NSRecursiveLock()

    // MARK: - Initialization

    /// Initializes with a value
    ///
    /// - Parameter wrappedValue: Initial value
    ///
    /// # Example
    /// ```swift
    /// @Atomic var counter: Int = 0
    /// ```
    public init(wrappedValue: Value) {
        self.value = wrappedValue
    }

    // MARK: - Property Wrapper

    /// The wrapped value, with thread-safe access
    ///
    /// Both reads and writes are protected by a lock, ensuring
    /// thread-safe access from multiple threads.
    public var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }

    /// Returns the wrapper itself for advanced operations
    ///
    /// Provides access to the `mutate(_:)` method for atomic mutations.
    public var projectedValue: Atomic<Value> {
        self
    }

    // MARK: - Atomic Operations

    /// Performs an atomic mutation on the value
    ///
    /// The lock is held for the entire duration of the mutation closure,
    /// ensuring no other thread can access the value during the operation.
    ///
    /// - Parameter mutation: Closure that mutates the value
    ///
    /// # Example
    /// ```swift
    /// @Atomic var scores: [Int] = []
    ///
    /// // Atomic append
    /// $scores.mutate { scores in
    ///     scores.append(100)
    /// }
    ///
    /// // Atomic complex mutation
    /// $scores.mutate { scores in
    ///     scores.removeAll { $0 < 50 }
    ///     scores.sort()
    /// }
    /// ```
    public mutating func mutate(_ mutation: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        mutation(&value)
    }
}

// MARK: - @UserDefault Property Wrapper

/// Persists values to UserDefaults automatically
///
/// `@UserDefault` provides a property-like interface to UserDefaults,
/// automatically saving changes and loading persisted values.
///
/// # Usage
///
/// ## App Settings
/// ```swift
/// class AppSettings: ObservableObject {
///     @UserDefault(key: "isDarkMode", defaultValue: false)
///     var isDarkMode: Bool
///
///     @UserDefault(key: "fontSize", defaultValue: 16)
///     var fontSize: Int
///
///     @UserDefault(key: "username", defaultValue: "")
///     var username: String
///
///     func toggleDarkMode() {
///         isDarkMode.toggle()  // Automatically persisted
///     }
/// }
/// ```
///
/// ## User Preferences
/// ```swift
/// struct UserPreferences {
///     @UserDefault(key: "notifications.enabled", defaultValue: true)
///     var notificationsEnabled: Bool
///
///     @UserDefault(key: "notifications.sound", defaultValue: "default")
///     var notificationSound: String
///
///     @UserDefault(key: "lastLoginDate", defaultValue: Date())
///     var lastLoginDate: Date
/// }
/// ```
///
/// ## Custom Storage
/// ```swift
/// class GroupSettings {
///     @UserDefault(
///         key: "sharedData",
///         defaultValue: "",
///         storage: UserDefaults(suiteName: "group.com.example.app")!
///     )
///     var sharedData: String
/// }
/// ```
///
/// # Key Features
/// - **Automatic Persistence**: Changes are saved immediately
/// - **Type-Safe**: Leverages Swift's type system
/// - **Default Values**: Provides fallback when no value is stored
/// - **Custom Storage**: Supports custom UserDefaults instances
///
/// # Supported Types
/// UserDefaults supports these types natively:
/// - Bool, Int, Float, Double, String
/// - Data, Date, URL
/// - Array, Dictionary (of supported types)
///
/// # When to Use
/// - App settings and preferences
/// - User configuration
/// - Feature flags
/// - Onboarding state
/// - Last known values
///
/// # When NOT to Use
/// - Sensitive data (use Keychain instead)
/// - Large data sets (use file system or database)
/// - Complex objects (use Codable with Data)
/// - Temporary state (use regular properties)
///
/// # Performance Note
/// UserDefaults writes are asynchronous but frequent writes can impact performance.
/// For high-frequency updates, consider batching changes.

@propertyWrapper
public struct
Preference<Value> {

    private let key: String

    public init(_ key: RawRepresentable<String>) {
        self.key = key.rawValue
    }
    
    public init(_ key: String) {
        self.key = key
    }

    public var wrappedValue: Value? {
        get { UserDefaults.app.object(forKey: key) as? Value }
        set { UserDefaults.app.set(newValue, forKey: key) }
    }
}

@propertyWrapper
public struct
StoredObject<Value:Codable> {

    private let key: String
    
    public init(_ key: String) {
        self.key = key
    }

    public var wrappedValue: Value? {
        get {
            guard let data = UserDefaults.app.object(forKey: key) as? Data else { return nil }
            return try? JSONDecoder().decode(Value.self, from: data)
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.app.setValue(data, forKey: key)
        }
    }
}

@propertyWrapper
public struct UserDefault<Value> {

    // MARK: - Properties

    /// The UserDefaults key for this value
    let key: String

    /// The default value when no stored value exists
    let defaultValue: Value

    /// The UserDefaults instance to use
    let storage: UserDefaults

    // MARK: - Initialization

    /// Initializes with a key, default value, and optional storage
    ///
    /// - Parameters:
    ///   - key: The UserDefaults key to store the value under
    ///   - defaultValue: Value returned when no stored value exists
    ///   - storage: UserDefaults instance to use (default: .standard)
    ///
    /// # Example
    /// ```swift
    /// @UserDefault(key: "user.age", defaultValue: 0)
    /// var age: Int
    ///
    /// // Custom storage for app groups
    /// @UserDefault(
    ///     key: "shared.count",
    ///     defaultValue: 0,
    ///     storage: UserDefaults(suiteName: "group.com.example")!
    /// )
    /// var sharedCount: Int
    /// ```
    public init(
        key: String = #function,
        defaultValue: Value,
        storage: UserDefaults = .standard
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.storage = storage
    }

    // MARK: - Property Wrapper

    /// The wrapped value, persisted to UserDefaults
    ///
    /// Reading retrieves the value from UserDefaults, returning the default
    /// if no value is stored. Writing saves the value to UserDefaults immediately.
    public var wrappedValue: Value {
        get {
            storage.object(forKey: key) as? Value ?? defaultValue
        }
        set {
            storage.set(newValue, forKey: key)
        }
    }
}

// MARK: - @Logged Property Wrapper

/// Logs all value changes for debugging
///
/// `@Logged` automatically prints when values are initialized and changed,
/// useful for debugging state management and tracking property mutations.
///
/// # Usage
///
/// ## Debug State Changes
/// ```swift
/// class GameViewModel: ObservableObject {
///     @Logged(wrappedValue: 0, name: "Score")
///     var score: Int
///
///     @Logged(wrappedValue: 100, name: "Health")
///     var health: Int
///
///     func takeDamage(_ amount: Int) {
///         health -= amount
///         // Console: [Health] Changed from 100 to 80
///     }
/// }
/// ```
///
/// ## Track Configuration
/// ```swift
/// struct APIConfiguration {
///     @Logged(wrappedValue: "https://api.example.com", name: "BaseURL")
///     var baseURL: String
///
///     @Logged(wrappedValue: false, name: "UseCache")
///     var useCache: Bool
///
///     mutating func setBaseURL(_ url: String) {
///         baseURL = url
///         // Console: [BaseURL] Changed from https://api.example.com to https://staging.example.com
///     }
/// }
/// ```
///
/// ## Monitor ViewModel State
/// ```swift
/// class SearchViewModel: ObservableObject {
///     @Logged(wrappedValue: "", name: "SearchQuery")
///     var query: String
///
///     @Logged(wrappedValue: [], name: "Results")
///     var results: [String]
///
///     // Initialization prints:
///     // [SearchQuery] Initialized with:
///     // [Results] Initialized with: []
/// }
/// ```
///
/// # Key Features
/// - **Initialization Logging**: Prints when property is created
/// - **Change Logging**: Prints old and new values on every change
/// - **Named Properties**: Custom names for readable logs
/// - **Debug-Only**: Should be conditionally compiled for debug builds
///
/// # Log Format
/// ```
/// [PropertyName] Initialized with: <value>
/// [PropertyName] Changed from <old> to <new>
/// ```
///
/// # When to Use
/// - Debugging state changes
/// - Tracking property mutations during development
/// - Understanding value flow in complex state management
/// - Temporary debugging (remove in production)
///
/// # When NOT to Use
/// - Production code (performance overhead)
/// - Properties with sensitive data (logs are visible)
/// - High-frequency changes (log spam)
/// - Release builds
///
/// # Best Practices
/// ```swift
/// #if DEBUG
/// @Logged(wrappedValue: 0, name: "DebugCounter")
/// var counter: Int
/// #else
/// var counter: Int = 0
/// #endif
/// ```
@propertyWrapper
public struct Logged<Value> {

    // MARK: - Properties

    /// The current value
    private var value: Value

    /// The name used in log messages
    private let name: String

    // MARK: - Initialization

    /// Initializes with a value and name, logging initialization
    ///
    /// - Parameters:
    ///   - wrappedValue: Initial value
    ///   - name: Name to use in log messages
    ///
    /// # Example
    /// ```swift
    /// @Logged(wrappedValue: 0, name: "UserScore")
    /// var score: Int
    /// // Console: [UserScore] Initialized with: 0
    /// ```
    public init(wrappedValue: Value, name: String) {
        self.value = wrappedValue
        self.name = name
        print("[\(name)] Initialized with: \(wrappedValue)")
    }

    // MARK: - Property Wrapper

    /// The wrapped value, logging changes
    ///
    /// Reading returns the current value without logging.
    /// Writing logs the change from old to new value.
    public var wrappedValue: Value {
        get {
            value
        }
        set {
            print("[\(name)] Changed from \(value) to \(newValue)")
            value = newValue
        }
    }
}

// MARK: - @Copyable Property Wrapper

/// Creates defensive copies of reference types
///
/// `@Copyable` ensures that NSCopying-conforming objects are copied
/// on initialization and assignment, preventing unintended sharing
/// of mutable reference types.
///
/// # Usage
///
/// ## Defensive Array Copying
/// ```swift
/// class DataStore {
///     @Copyable var items: NSMutableArray
///
///     init() {
///         self.items = NSMutableArray(array: ["Item1", "Item2"])
///     }
///
///     func setItems(_ newItems: NSMutableArray) {
///         items = newItems  // Creates a copy, not a reference
///     }
/// }
/// ```
///
/// ## String Protection
/// ```swift
/// class Document {
///     @Copyable var title: NSString
///
///     init(title: NSString) {
///         self.title = title  // Copied, not shared
///     }
///
///     func updateTitle(_ newTitle: NSString) {
///         title = newTitle  // Creates new copy
///     }
/// }
/// ```
///
/// ## Date Isolation
/// ```swift
/// class Event {
///     @Copyable var date: NSDate
///
///     init(date: NSDate) {
///         self.date = date  // Defensive copy
///     }
///
///     func reschedule(to newDate: NSDate) {
///         date = newDate  // New copy created
///     }
/// }
/// ```
///
/// # Key Features
/// - **Defensive Copying**: Creates copies on init and assignment
/// - **Reference Isolation**: Prevents unintended sharing
/// - **NSCopying Protocol**: Works with any NSCopying-conforming type
/// - **Automatic**: No manual copy() calls needed
///
/// # Supported Types
/// Types that conform to NSCopying:
/// - NSString, NSMutableString
/// - NSArray, NSMutableArray
/// - NSDictionary, NSMutableDictionary
/// - NSData, NSMutableData
/// - NSDate
/// - Custom classes implementing NSCopying
///
/// # When to Use
/// - Working with NSCopying Foundation types
/// - Preventing unintended reference sharing
/// - Ensuring value semantics for reference types
/// - Legacy Objective-C interop
/// - Mutable collection protection
///
/// # When NOT to Use
/// - Swift value types (String, Array, etc.) - already have copy semantics
/// - Swift classes not conforming to NSCopying
/// - When reference sharing is intended
/// - Performance-critical code (copying has overhead)
///
/// # Modern Swift Note
/// Consider using Swift value types (struct, enum) instead of NSCopying
/// reference types for safer, more idiomatic code:
///
/// ```swift
/// // Modern Swift (preferred)
/// struct Event {
///     var title: String  // Already has value semantics
///     var date: Date     // Already has value semantics
/// }
///
/// // Legacy NSCopying (when necessary)
/// class LegacyEvent {
///     @Copyable var title: NSString
///     @Copyable var date: NSDate
/// }
/// ```
@propertyWrapper
public struct Copyable<Value: NSCopying> {

    // MARK: - Properties

    /// The copied value
    private var value: Value

    // MARK: - Initialization

    /// Initializes with a value, creating a copy
    ///
    /// - Parameter wrappedValue: Value to copy
    ///
    /// # Example
    /// ```swift
    /// let original = NSMutableArray(array: [1, 2, 3])
    /// @Copyable var array: NSMutableArray = original
    /// // array is a copy, not a reference to original
    /// ```
    public init(wrappedValue: Value) {
        self.value = wrappedValue.copy() as! Value
    }

    // MARK: - Property Wrapper

    /// The wrapped value, copied on assignment
    ///
    /// Reading returns the current copy.
    /// Writing creates a new copy of the assigned value.
    public var wrappedValue: Value {
        get { value }
        set {
            value = newValue.copy() as! Value
        }
    }
}

extension UserDefaults {
    open class var suite: String {""}
    public class var app: UserDefaults { UserDefaults(suiteName: suite) ?? .standard }
}
