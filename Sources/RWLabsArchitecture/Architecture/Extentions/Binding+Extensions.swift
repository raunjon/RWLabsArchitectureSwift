//
//  Binding+Extensions.swift
//  ThirtyPlusPanel
//
//  Created by Raunak Joneja on 09/01/26.
//

import SwiftUI

public extension Binding where Value == String? {
    /// Converts `Binding<String?>` to `Binding<String>`, providing a default value for `nil`.
    func orEmpty() -> Binding<String> {
        Binding<String>(
            get: {
                self.wrappedValue ?? "" // Return an empty string if the optional string is nil
            },
            set: {
                self.wrappedValue = $0 // Update the optional string with the new non-optional value
            }
        )
    }
}


public extension Binding where Value == Bool? {
    func orEmpty() -> Binding<Bool> {
        Binding<Bool>(
            get: {
                self.wrappedValue ?? false // Return an empty string if the optional string is nil
            },
            set: {
                self.wrappedValue = $0 // Update the optional string with the new non-optional value
            }
        )
    }
}

public extension Binding where Value == Date? {
    func orEmpty() -> Binding<Date> {
        Binding<Date>(
            get: {
                self.wrappedValue ?? .init() // Return an empty string if the optional string is nil
            },
            set: {
                self.wrappedValue = $0 // Update the optional string with the new non-optional value
            }
        )
    }
}

public extension Binding {
    /// Creates a non-optional Binding to a property on an optional object.
    /// - If the object is nil, `defaultValue` is returned and `set` is ignored.
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
}

public extension Binding {
    func unwrap<V>(_ keyPath: ReferenceWritableKeyPath<Value, V>, default: V) -> Binding<V> {
        Binding<V>(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { newValue in
                self.wrappedValue[keyPath: keyPath] = newValue
            }
        )
    }
}

public extension Binding {
    /// Bind to a property on an *optional* reference type.
    /// If the object is nil, reads `defaultValue` and ignores writes.
    func unwrap<Object: AnyObject, V>(
        _ keyPath: ReferenceWritableKeyPath<Object, V>,
        default defaultValue: V
    ) -> Binding<V> where Value == Object? {
        Binding<V>(
            get: { self.wrappedValue?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                self.wrappedValue?[keyPath: keyPath] = newValue
            }
        )
    }

    func unwrap<Object: AnyObject>(
        _ keyPath: ReferenceWritableKeyPath<Object, Bool>,
        default defaultValue: Bool = false
    ) -> Binding<Bool> where Value == Object? {
        Binding<Bool>(
            get: { self.wrappedValue?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                self.wrappedValue?[keyPath: keyPath] = newValue
            }
        )
    }

    func unwrap<Object: AnyObject>(
        _ keyPath: ReferenceWritableKeyPath<Object, String>,
        default defaultValue: String = ""
    ) -> Binding<String> where Value == Object? {
        Binding<String>(
            get: { self.wrappedValue?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                self.wrappedValue?[keyPath: keyPath] = newValue
            }
        )
    }
}
