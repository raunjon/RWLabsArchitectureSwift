//
//  Library.swift
//  RWLabsDemo
//
//  A list that pushes a detail screen and presents an editor sheet. Its destinations are
//  deep-linkable: rwlabsdemo://library/book?id=2
//

import SwiftUI
import RWLabsArchitecture

@Component
final class LibraryModel: ComponentModel<LibraryModel> {
    struct State {
        var books: [Book] = []
    }

    @DeepLinkable
    enum Destination {
        @DeepLink("book", params: ["id": "bookID"])
        case detail(BookDetailModel.State)

        @DeepLink(skip: true)
        case add(BookEditorModel.State)
    }

    enum Action { case load, bookTapped(Book), addTapped }

    @Injected var store: BookStore

    final class Connections: ConnectionsBase {
        lazy var detail = Connection<BookDetailModel> { [weak parent] output in
            switch output {
            case .changed: parent?.send(.load)
            }
        }
        .connect(state: \.destination, case: \.detail, parent: parent)

        lazy var add = Connection<BookEditorModel> { [weak parent] output in
            switch output {
            case .saved: parent?.send(.load)
            }
        }
        .connect(state: \.destination, case: \.add, parent: parent)
    }

    override func onAppear() {
        if state.books.isEmpty { send(.load) }
    }

    override func send(_ action: Action) {
        switch action {
        case .load:
            perform { [store] in try await store.books() }
            then: { [weak self] books in self?.state.books = books }

        case .bookTapped(let book):
            destination = .detail(.init(book: book))          // the payload is the child's starting state

        case .addTapped:
            destination = .add(.init(book: Book()))
        }
    }
}

struct LibraryView: @MainActor ComponentView {
    @ObservedObject var model: LibraryModel

    var content: some View {
        List(model.books) { book in
            button(.bookTapped(book)) {
                BookRow(book: book)
            }
            .foregroundStyle(.primary)
        }
        .overlay {
            if model.isLoading && model.books.isEmpty { ProgressView() }
        }
        .navigationTitle("Library")
        .toolbar {
            button(.addTapped) { Label("Add Book", systemImage: "plus") }
        }
        .push(model.connections.detail) { BookDetailView(model: $0) }
        .present(model.connections.add) { editor in
            NavigationStack { BookEditorView(model: editor) }
        }
    }
}

private struct BookRow: View {
    let book: Book

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(book.title).font(.headline)
                Text(book.author).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if book.isFinished {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }
}
