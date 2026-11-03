//
//  BookDetail.swift
//  RWLabsDemo
//
//  A pushed screen that loads by id (so a deep link can open it), presents an editor,
//  confirms deletion in a custom alert, and closes itself with `close()`
//

import SwiftUI
import RWLabsArchitecture

@Component
final class BookDetailModel: ComponentModel<BookDetailModel> {
    struct State {
        /// Set from a link's `?id=`; the view loads the book whenever it changes
        var bookID = 0
        var book: Book?

        init(book: Book? = nil) {
            self.book = book
            self.bookID = book?.id ?? 0
        }
    }

    enum Destination {
        case edit(BookEditorModel.State)
        case confirmDelete(ConfirmDeleteModel.State)
    }

    enum Action { case load, editTapped, deleteTapped, toggleFinished }
    enum Output { case changed }

    @Injected var store: BookStore

    final class Connections: ConnectionsBase {
        lazy var edit = Connection<BookEditorModel> { [weak parent] output in
            switch output {
            case .saved(let book):
                parent?.state.book = book
                parent?.sendOutput(.changed)
            }
        }
        .connect(state: \.destination, case: \.edit, parent: parent)

        lazy var confirmDelete = Connection<ConfirmDeleteModel> { [weak parent] output in
            switch output {
            case .confirmed: parent?.delete()
            }
        }
        .connect(state: \.destination, case: \.confirmDelete, parent: parent)
    }

    override func send(_ action: Action) {
        switch action {
        case .load:
            guard state.book?.id != state.bookID else { return }
            perform { [store, id = state.bookID] in try await store.book(id: id) }
            then: { [weak self] book in self?.state.book = book }

        case .editTapped:
            guard let book = state.book else { return }
            destination = .edit(.init(book: book))

        case .deleteTapped:
            guard let book = state.book else { return }
            destination = .confirmDelete(.init(title: book.title))

        case .toggleFinished:
            guard var updated = state.book else { return }
            updated.isFinished.toggle()
            state.book = updated
            perform { [store] in try await store.save(updated) }
            then: { [weak self] _ in self?.sendOutput(.changed) }
        }
    }

    private func delete() {
        guard let id = state.book?.id else { return }
        perform { [store] in try await store.delete(id: id) }
        then: { [weak self] in
            self?.sendOutput(.changed)
            self?.close()                                      // pops this screen
        }
    }
}

struct BookDetailView: @MainActor ComponentView {
    @ObservedObject var model: BookDetailModel

    var content: some View {
        Group {
            if let book = model.book {
                Form {
                    Section {
                        LabeledContent("Author", value: book.author)
                        Toggle("Finished", isOn: Binding(
                            get: { book.isFinished },
                            set: { _ in model.send(.toggleFinished) }
                        ))
                    }
                    if !book.notes.isEmpty {
                        Section("Notes") { Text(book.notes) }
                    }
                    Section {
                        button(.deleteTapped) { Text("Delete Book").foregroundStyle(.red) }
                    }
                }
                .navigationTitle(book.title)
            } else if let error = model.error {
                ContentUnavailableView("Couldn't open the book", systemImage: "book.closed", description: Text(error.localizedDescription))
            } else {
                ProgressView()
            }
        }
        // Runs on appear and again when a deep link reuses this screen for another book
        .task(id: model.bookID) { model.send(.load) }
        .toolbar {
            if model.book != nil {
                button(.editTapped) { Text("Edit") }
            }
        }
        .present(model.connections.edit) { editor in
            NavigationStack { BookEditorView(model: editor) }
        }
        .customAlert(item: model.connections.confirmDelete.bindingModel) { ConfirmDeleteView(model: $0) }
    }
}

// MARK: - Confirm Delete

@Component
final class ConfirmDeleteModel: ComponentModel<ConfirmDeleteModel> {
    struct State {
        var title: String

        init(title: String) {
            self.title = title
        }
    }

    enum Action { case confirm, cancel }
    enum Output { case confirmed }

    override func send(_ action: Action) {
        switch action {
        case .confirm:
            sendOutput(.confirmed)
            close()
        case .cancel:
            close()
        }
    }
}

struct ConfirmDeleteView: @MainActor ComponentView {
    @ObservedObject var model: ConfirmDeleteModel

    var content: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)
            Text("Delete \"\(model.title)\"?")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("This can't be undone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                button(.cancel) { Text("Cancel").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                button(.confirm) { Text("Delete").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }
}
