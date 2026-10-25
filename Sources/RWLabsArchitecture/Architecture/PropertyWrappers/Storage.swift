//
//  Storage.swift
//  RWLabsArchitecture
//
//  Property wrappers that persist values in UserDefaults.app
//

import Foundation

// MARK: - UserDefaults.app

public extension UserDefaults {
    /// The suite `UserDefaults.app` uses; `nil` (the default) means `.standard`.
    ///
    /// Set it once at startup, before anything reads a `@Preference` or `@StoredObject`.
    /// For sharing with extensions or other apps, use an App Group id, which must start with `group.`:
    ///
    /// ```swift
    /// UserDefaults.appSuiteName = "group.com.example.shared"
    /// ```
    static var appSuiteName: String? {
        get { AppDefaults.shared.suiteName }
        set { AppDefaults.shared.setSuiteName(newValue) }
    }

    /// The store used by `@Preference` and `@StoredObject`: the `appSuiteName` suite, or `.standard`
    static var app: UserDefaults {
        AppDefaults.shared.defaults
    }

    /// Copies every value stored in the suite `oldSuiteName` into this store, keeping values
    /// already set here, then clears the old suite. Use it once when moving to a new suite.
    ///
    /// - Returns: How many values were copied.
    @discardableResult
    func migrate(fromSuite oldSuiteName: String) -> Int {
        guard let old = UserDefaults(suiteName: oldSuiteName),
              let values = old.persistentDomain(forName: oldSuiteName) else {
            return 0
        }
        var copied = 0
        for (key, value) in values where object(forKey: key) == nil {
            set(value, forKey: key)
            copied += 1
        }
        old.removePersistentDomain(forName: oldSuiteName)
        return copied
    }
}

/// Holds the configured suite and the cached `UserDefaults` for it
private final class AppDefaults: @unchecked Sendable {
    static let shared = AppDefaults()

    private let lock = NSLock()
    private var _suiteName: String?
    private var _defaults: UserDefaults?

    var suiteName: String? {
        lock.withLock { _suiteName }
    }

    var defaults: UserDefaults {
        lock.withLock {
            if let _defaults { return _defaults }
            let made = _suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
            _defaults = made
            return made
        }
    }

    func setSuiteName(_ name: String?) {
        lock.withLock {
            _suiteName = name
            _defaults = nil
        }
    }
}

// MARK: - @Preference

/// A value stored in `UserDefaults.app` under `key`.
///
/// ```swift
/// @Preference("isEventMode") var isEventMode: Bool?              // nil when unset
/// @Preference("launchCount", default: 0) var launchCount: Int     // 0 when unset
/// @Preference(PrefKeys.theme, default: "light") var theme: String
/// ```
///
/// Setting an optional to `nil` removes the key.
///
/// - Important: Only property-list types can be stored: `String`, `Int`, `Double`, `Bool`,
///   `Date`, `Data`, and arrays and dictionaries of those. Anything else crashes when set;
///   use `@StoredObject` for `Codable` values.
@propertyWrapper
public struct Preference<Value> {
    private let key: String
    private let defaultValue: Value
    private let defaults: UserDefaults

    public init(_ key: String, default defaultValue: Value, defaults: UserDefaults = .app) {
        self.key = key
        self.defaultValue = defaultValue
        self.defaults = defaults
    }

    public init(_ key: some RawRepresentable<String>, default defaultValue: Value) {
        self.init(key.rawValue, default: defaultValue)
    }

    /// An optional preference that's `nil` when unset
    public init(_ key: String) where Value: ExpressibleByNilLiteral {
        self.init(key, default: nil)
    }

    /// An optional preference that's `nil` when unset
    public init(_ key: some RawRepresentable<String>) where Value: ExpressibleByNilLiteral {
        self.init(key.rawValue, default: nil)
    }

    public var wrappedValue: Value {
        get {
            guard let stored = defaults.object(forKey: key) else { return defaultValue }
            return stored as? Value ?? defaultValue
        }
        set {
            if let value = unwrappedOptional(newValue) {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

// MARK: - @StoredObject

/// A `Codable` value stored in `UserDefaults.app` as JSON under `key`; `nil` when unset or
/// unreadable. Setting `nil` removes the key.
///
/// ```swift
/// @StoredObject("currentUser") var currentUser: User?
/// ```
@propertyWrapper
public struct StoredObject<Value: Codable> {
    private let key: String
    private let defaults: UserDefaults

    public init(_ key: String, defaults: UserDefaults = .app) {
        self.key = key
        self.defaults = defaults
    }

    public init(_ key: some RawRepresentable<String>) {
        self.init(key.rawValue)
    }

    public var wrappedValue: Value? {
        get {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(Value.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: key)
                return
            }
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - Helpers

/// The value inside `value` if it's an optional (`nil` if that optional is empty), otherwise `value` itself
private func unwrappedOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    return mirror.children.first.map { unwrappedOptional($0.value) } ?? nil
}
