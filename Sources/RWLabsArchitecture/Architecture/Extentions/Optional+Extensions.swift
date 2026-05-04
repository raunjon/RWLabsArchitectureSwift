//
//  Optional+Extensions.swift
//  ThirtyPlusPanel
//
//  Created by Raunak Joneja on 11/01/26.
//

extension Optional: AnyOptional {
    public var isNil: Bool { self == nil }
    public var exists: Bool { !isNil }
}
public extension Optional where Wrapped: Collection {
    public var nilOrEmpty: Bool {
        switch self {
        case .some(let collection): collection.isEmpty
        case .none: true
        }
    }

    public var hasContent: Bool {
        !nilOrEmpty
    }

    public var content: Wrapped? {
        hasContent ? self : nil
    }
}
