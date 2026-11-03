//
//  BookEditor.swift
//  RWLabsDemo
//
//  An edit screen built on `Editable`: it knows whether anything changed, can revert,
//  and commits what the store saved
//

import SwiftUI
import RWLabsArchitecture

@Component
final class BookEditorModel: ComponentModel<BookEditorModel> {
    struct State: ItemEditingState {
        var item: Editable<Book>
        var titleError: String?

        init(book: Book) {
            item = Editable(book)
        }
    }

    enum Action { case save, revert, cancel }
    enum Output { case saved(Book) }

    @Injected var store: BookStore
    @Injected var validator: ValidationService

    override func send(_ action: Action) {
        switch action {
        case .revert:
            revert()

        case .cancel:
            close()                                            // dismisses the sheet

        case .save:
            let title = validator.validate(state.item.draft.title, rules: [.required, .maxLength(80)])
            state.titleError = title.errors.first
            guard title.isValid else { return }
            perform { [store, draft = state.item.draft] in try await store.save(draft) }
            then: { [weak self] saved in
                self?.commit(saved)
                self?.sendOutput(.saved(saved))
                self?.close()
            }
        }
    }
}

struct BookEditorView: @MainActor ComponentView {
    @ObservedObject var model: BookEditorModel

    var content: some View {
        Form {
            Section {
                TextField("Title", text: model.binding(draft: \.title))
                if let error = model.titleError {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
                TextField("Author", text: model.binding(draft: \.author))
                Toggle("Finished", isOn: model.binding(draft: \.isFinished))
            }
            Section("Notes") {
                TextField("Notes", text: model.binding(draft: \.notes), axis: .vertical)
                    .lineLimit(3...8)
            }
            if model.isModified && !model.item.original.isNew {
                Section {
                    button(.revert) { Text("Revert Changes") }
                }
            }
            if let error = model.error {
                Section { Text(error.localizedDescription).foregroundStyle(.red) }
            }
        }
        .navigationTitle(model.item.original.isNew ? "New Book" : "Edit Book")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isLoading)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                button(.cancel) { Text("Cancel") }
            }
            ToolbarItem(placement: .confirmationAction) {
                if model.isLoading {
                    ProgressView()
                } else {
                    button(.save) { Text("Save") }.disabled(!model.isModified)
                }
            }
        }
        .interactiveDismissDisabled(model.isModified)
    }
}
