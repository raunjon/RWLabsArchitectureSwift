//
//  Services.swift
//  RWLabsDemo
//
//  The app's dependencies, registered in `DemoApp` and injected into models
//

import Foundation
import RWLabsArchitecture

// MARK: - Books

protocol BookStore: Sendable {
    func books() async throws -> [Book]
    func book(id: Int) async throws -> Book
    /// Saves `book`, giving a new book an id, and returns what was stored
    func save(_ book: Book) async throws -> Book
    func delete(id: Int) async throws
}

enum BookStoreError: LocalizedError {
    case notFound(Int)

    var errorDescription: String? {
        switch self {
        case .notFound(let id): "There's no book with id \(id)."
        }
    }
}

/// Keeps books in memory, with a short delay so loading states are visible
actor InMemoryBookStore: BookStore {
    private var storage: [Int: Book] = [
        1: Book(id: 1, title: "The Left Hand of Darkness", author: "Ursula K. Le Guin", isFinished: true),
        2: Book(id: 2, title: "Piranesi", author: "Susanna Clarke", notes: "Recommended by Sam."),
        3: Book(id: 3, title: "Project Hail Mary", author: "Andy Weir"),
    ]
    private var nextID = 4

    func books() async throws -> [Book] {
        try await Task.sleep(for: .milliseconds(400))
        return storage.values.sorted { $0.title < $1.title }
    }

    func book(id: Int) async throws -> Book {
        try await Task.sleep(for: .milliseconds(200))
        guard let book = storage[id] else { throw BookStoreError.notFound(id) }
        return book
    }

    func save(_ book: Book) async throws -> Book {
        try await Task.sleep(for: .milliseconds(300))
        var saved = book
        if saved.isNew {
            saved.id = nextID
            nextID += 1
        }
        storage[saved.id] = saved
        return saved
    }

    func delete(id: Int) async throws {
        try await Task.sleep(for: .milliseconds(200))
        storage[id] = nil
    }
}

// MARK: - Session

protocol SessionService: Sendable {
    func signIn(email: String, password: String) async throws -> User
}

struct SignInError: LocalizedError {
    var errorDescription: String? { "Wrong email or password. (Any password except \"wrong\" works.)" }
}

/// Accepts any password except "wrong", so the error path can be tried too
struct DemoSessionService: SessionService {
    func signIn(email: String, password: String) async throws -> User {
        try await Task.sleep(for: .milliseconds(600))
        guard password != "wrong" else { throw SignInError() }
        return User(email: email)
    }
}

// MARK: - Errors

/// Every app provides one; models forward errors here as well as storing them in state
struct DemoErrorService: ErrorService {
    func handleError(_ error: Error) {
        Log.e("Unhandled error", error: error)
    }
}
