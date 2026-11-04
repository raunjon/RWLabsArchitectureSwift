//
//  Book.swift
//  RWLabsDemo
//

import Foundation

struct Book: Identifiable, Equatable, Sendable {
    /// `0` until the store saves it
    var id: Int = 0
    var title = ""
    var author = ""
    var notes = ""
    var isFinished = false

    var isNew: Bool { id == 0 }
}

struct User: Equatable, Sendable {
    var email: String
}
