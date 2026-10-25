//
//  Optional+Extensions.swift
//  RWLabsArchitecture
//
//  Created by Raunak Joneja on 11/01/26.
//

extension Optional: AnyOptional {
    /// `true` when `nil`
    public var isNil: Bool { self == nil }

    /// `true` when not `nil`
    public var exists: Bool { !isNil }
}

public extension Optional where Wrapped == String {
    /// The string, or `""` when `nil`
    var orEmpty: String { self ?? "" }
}

public extension Optional where Wrapped: Collection {
    /// `true` when `nil` or empty
    var nilOrEmpty: Bool {
        switch self {
        case .some(let collection): collection.isEmpty
        case .none: true
        }
    }

    /// `true` when non-`nil` and non-empty
    var hasContent: Bool {
        !nilOrEmpty
    }

    /// The collection, or `nil` when it's empty
    var content: Wrapped? {
        hasContent ? self : nil
    }
}
