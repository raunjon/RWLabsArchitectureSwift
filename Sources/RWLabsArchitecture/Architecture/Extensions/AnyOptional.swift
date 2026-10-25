//
//  AnyOptional.swift
//  RWLabsArchitecture
//
//  Created by Raunak Joneja on 11/01/26.
//

/// Lets generic code ask whether a value of unknown type is a `nil` optional:
/// `(value as? AnyOptional)?.isNil == true`
public protocol AnyOptional {
    var isNil: Bool { get }
}
