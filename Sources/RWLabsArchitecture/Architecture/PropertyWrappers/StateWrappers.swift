//
//  StateWrappers.swift
//  RWLabsArchitecture
//
//  In-memory property wrappers for state values
//

import Foundation
import Combine

// MARK: - @Clamped

/// Keeps a value inside `range`; values outside it are clamped to the nearest bound.
///
/// ```swift
/// @Clamped(0...10) var rating = 5
/// ```
@propertyWrapper
public struct Clamped<Value: Comparable> {
    private var value: Value
    private let range: ClosedRange<Value>

    public init(wrappedValue: Value, _ range: ClosedRange<Value>) {
        self.range = range
        self.value = min(max(wrappedValue, range.lowerBound), range.upperBound)
    }

    public var wrappedValue: Value {
        get { value }
        set { value = min(max(newValue, range.lowerBound), range.upperBound) }
    }
}

// MARK: - @Trimmed

/// A string that keeps exactly what was typed, with its trimmed form on `$`.
///
/// The stored value isn't changed, so it can be bound to a `TextField` (trimming while the
/// user types would delete the space before their next word). Read `$name` to save or validate.
///
/// ```swift
/// @Trimmed var name = ""
/// // name == "  Ada Lovelace ", $name == "Ada Lovelace"
/// ```
@propertyWrapper
public struct Trimmed {
    public var wrappedValue: String

    public init(wrappedValue: String) {
        self.wrappedValue = wrappedValue
    }

    /// The value without leading and trailing whitespace and newlines
    public var projectedValue: String {
        wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - @Debounced

/// A value whose changes are also published once they settle, on `$`.
///
/// `$query` emits on the main queue after the value has stopped changing for `delay`
/// seconds. It doesn't emit the initial value, and each subscriber gets its own debounced stream.
///
/// ```swift
/// @Debounced(delay: 0.4) var query = ""
///
/// state.$query
///     .sink { [weak self] in self?.search($0) }
///     .store(in: &cancellables)
/// ```
///
/// - Note: Copies of the wrapper share one stream, so a copy of a state struct publishes
///   to the same subscribers.
@propertyWrapper
public struct Debounced<Value> {
    private let subject: CurrentValueSubject<Value, Never>
    private let delay: TimeInterval

    public init(wrappedValue: Value, delay: TimeInterval = 0.3) {
        self.subject = CurrentValueSubject(wrappedValue)
        self.delay = delay
    }

    public var wrappedValue: Value {
        get { subject.value }
        set { subject.send(newValue) }
    }

    /// Changes after they've settled for `delay` seconds
    public var projectedValue: AnyPublisher<Value, Never> {
        subject
            .dropFirst()
            .debounce(for: .seconds(delay), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

// MARK: - @Logged

/// Logs every change with `Log.d` in debug builds; does nothing extra in release builds.
///
/// ```swift
/// @Logged(name: "cartCount") var cartCount = 0
/// // cartCount: 0 → 1
/// ```
@propertyWrapper
public struct Logged<Value> {
    private var value: Value
    private let name: String

    public init(wrappedValue: Value, name: String) {
        self.value = wrappedValue
        self.name = name
    }

    public var wrappedValue: Value {
        get { value }
        set {
            #if DEBUG
            Log.d("\(name): \(value) → \(newValue)")
            #endif
            value = newValue
        }
    }
}

// MARK: - @Copyable

/// Stores a copy of every value assigned, so later changes to the original object don't leak in.
///
/// Uses `copy()`, or `mutableCopy()` for mutable classes like `NSMutableString`, whose
/// `copy()` returns an immutable object.
@propertyWrapper
public struct Copyable<Value: NSCopying> {
    private var value: Value

    public init(wrappedValue: Value) {
        self.value = Self.copy(of: wrappedValue)
    }

    public var wrappedValue: Value {
        get { value }
        set { value = Self.copy(of: newValue) }
    }

    private static func copy(of value: Value) -> Value {
        if let copied = value.copy() as? Value {
            return copied
        }
        if let mutable = value as? NSMutableCopying, let copied = mutable.mutableCopy() as? Value {
            return copied
        }
        preconditionFailure("@Copyable: copying a \(type(of: value)) didn't produce a \(Value.self)")
    }
}
