//
//  Presentation.swift
//  RWLabsArchitecture
//
//  Present or push a connection's child, driven by the parent's destination
//

import SwiftUI
import CasePaths

// MARK: - Connections

public extension View {
    /// Presents `connection`'s child as a sheet while its case is the parent's destination.
    /// Dismissing the sheet clears the parent's destination.
    ///
    /// ```swift
    /// content.present(model.connections.editor) { EditorView(model: $0) }
    /// ```
    func present<From: ViewModel, To: ViewModel, Case, Content: View>(
        _ connection: CaseConnection<From, To, Case>,
        @ViewBuilder content: @escaping (To) -> Content
    ) -> some View {
        sheet(item: connection.bindingModel, content: content)
    }

    /// `present(_:content:)` for a binding to the connection, e.g. `$model.connections.editor`
    func present<From: ViewModel, To: ViewModel, Case, Content: View>(
        _ connection: Binding<CaseConnection<From, To, Case>>,
        @ViewBuilder content: @escaping (To) -> Content
    ) -> some View {
        present(connection.wrappedValue, content: content)
    }

    /// Pushes `connection`'s child onto the enclosing `NavigationStack` while its case is
    /// the parent's destination. Popping back clears the parent's destination.
    ///
    /// ```swift
    /// content
    ///     .navigationTitle("More")
    ///     .push(model.connections.entries) { EntriesView(model: $0) }
    /// ```
    func push<From: ViewModel, To: ViewModel, Case, Destination: View>(
        _ connection: CaseConnection<From, To, Case>,
        enableBackButton: Bool = true,
        @ViewBuilder _ destination: @escaping (To) -> Destination
    ) -> some View {
        navigationDestination(item: connection.bindingModel) {
            destination($0).customBackButton(enable: enableBackButton)
        }
    }

    /// `push(_:enableBackButton:_:)` for a binding to the connection, e.g. `$model.connections.entries`
    func push<From: ViewModel, To: ViewModel, Case, Destination: View>(
        _ connection: Binding<CaseConnection<From, To, Case>>,
        enableBackButton: Bool = true,
        @ViewBuilder _ destination: @escaping (To) -> Destination
    ) -> some View {
        push(connection.wrappedValue, enableBackButton: enableBackButton, destination)
    }
}

// MARK: - Optional Models

public extension View {
    /// Presents a sheet while `binding` holds a model; dismissing sets it to `nil`
    func presentAsBinding<T: ViewModel, Destination: View>(
        item binding: Binding<T?>,
        @ViewBuilder _ destination: @escaping (T) -> Destination
    ) -> some View {
        sheet(item: binding, content: destination)
    }
}

// MARK: - Back Button

public extension View {
    /// Placeholder for a custom back button on pushed screens; currently returns the view unchanged
    func customBackButton(enable: Bool = true) -> some View {
        self
    }
}
