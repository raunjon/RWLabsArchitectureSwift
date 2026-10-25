//
//  Binding+Extensions.swift
//  RWLabsArchitecture
//
//  Created by Raunak Joneja on 09/01/26.
//

import SwiftUI

// MARK: - Optional → Non-Optional

public extension Binding {
    /// A non-optional binding over an optional value: reads `defaultValue`
    /// while it's `nil`; writes always store the new value.
    func orDefault<Wrapped>(_ defaultValue: @autoclosure @escaping () -> Wrapped) -> Binding<Wrapped> where Value == Wrapped? {
        Binding<Wrapped>(
            get: { wrappedValue ?? defaultValue() },
            set: { wrappedValue = $0 }
        )
    }
}

public extension Binding where Value == String? {
    /// Reads `""` while `nil`
    func orEmpty() -> Binding<String> { orDefault("") }
}

public extension Binding where Value == Bool? {
    /// Reads `false` while `nil`
    func orEmpty() -> Binding<Bool> { orDefault(false) }
}

public extension Binding where Value == Date? {
    /// Reads the current date and time while `nil`
    func orEmpty() -> Binding<Date> { orDefault(Date()) }
}

// MARK: - Properties of Reference Types

public extension Binding {
    /// A non-optional binding to a property on an optional object.
    /// Reads `defaultValue` while the object is `nil`; writes are ignored then.
    static func unwrap<Object, V>(
        _ object: Binding<Object?>,
        _ keyPath: ReferenceWritableKeyPath<Object, V>,
        default defaultValue: V
    ) -> Binding<V> {
        Binding<V>(
            get: { object.wrappedValue?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                object.wrappedValue?[keyPath: keyPath] = newValue
            }
        )
    }

    /// A binding to a property on the bound object.
    /// - Note: `default` isn't used; the object is never `nil` here.
    func unwrap<V>(_ keyPath: ReferenceWritableKeyPath<Value, V>, default: V) -> Binding<V> {
        Binding<V>(
            get: { wrappedValue[keyPath: keyPath] },
            set: { newValue in
                wrappedValue[keyPath: keyPath] = newValue
            }
        )
    }

    /// A non-optional binding to a property on an optional object.
    /// Reads `defaultValue` while the object is `nil`; writes are ignored then.
    func unwrap<Object: AnyObject, V>(
        _ keyPath: ReferenceWritableKeyPath<Object, V>,
        default defaultValue: V
    ) -> Binding<V> where Value == Object? {
        Binding<V>(
            get: { wrappedValue?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                wrappedValue?[keyPath: keyPath] = newValue
            }
        )
    }

    /// `unwrap(_:default:)` for a `Bool` property, defaulting to `false`
    func unwrap<Object: AnyObject>(
        _ keyPath: ReferenceWritableKeyPath<Object, Bool>,
        default defaultValue: Bool = false
    ) -> Binding<Bool> where Value == Object? {
        Binding<Bool>(
            get: { wrappedValue?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                wrappedValue?[keyPath: keyPath] = newValue
            }
        )
    }

    /// `unwrap(_:default:)` for a `String` property, defaulting to `""`
    func unwrap<Object: AnyObject>(
        _ keyPath: ReferenceWritableKeyPath<Object, String>,
        default defaultValue: String = ""
    ) -> Binding<String> where Value == Object? {
        Binding<String>(
            get: { wrappedValue?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                wrappedValue?[keyPath: keyPath] = newValue
            }
        )
    }
}

// MARK: - Selection

public extension Binding {
    /// A `Bool` binding that's `true` while the value equals `value`, for pickers and radio buttons.
    /// Setting `true` selects `value`; setting `false` clears the selection to `nil`.
    func isEqual<T: Equatable>(to value: T) -> Binding<Bool> where Value == T? {
        Binding<Bool>(
            get: { wrappedValue == value },
            set: { isSelected in
                wrappedValue = isSelected ? value : nil
            }
        )
    }

    /// `isEqual(to:)` for a non-optional `String`: setting `false` clears it to `""`
    func isEqual(to value: String) -> Binding<Bool> where Value == String {
        Binding<Bool>(
            get: { wrappedValue == value },
            set: { isSelected in
                wrappedValue = isSelected ? value : ""
            }
        )
    }
}

// MARK: - Presentation

public extension Binding {
    /// `true` while the optional value is non-`nil`.
    ///
    /// Writing `false` sets the value to `nil`; writing `true` does nothing.
    func isPresent<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { isPresented in
                if !isPresented { wrappedValue = nil }
            }
        )
    }
}
