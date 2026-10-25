//
//  ComponentView.swift
//  RWLabsArchitecture
//
//  View protocols built on BaseView, and destination presentation
//

import SwiftUI

// MARK: - ComponentView

/// The view protocol feature screens conform to.
///
/// Same `body` as `BaseView` (renders `content`, calls `model.onAppear()`),
/// plus helpers for sending actions. It doesn't add a `NavigationStack`;
/// the view hosting a navigation root wraps it, e.g.
/// `NavigationStack { HomeView(model: …) }`.
///
/// ```swift
/// struct CounterView: ComponentView {
///     @ObservedObject var model: CounterModel
///
///     var content: some View {
///         button(.increment) { Text("Count: \(model.count)") }
///     }
/// }
/// ```
public protocol ComponentView: BaseView {}

public extension ComponentView {
    /// A `Button` that sends `action` to `model` when tapped
    func button<Label: View>(_ action: @escaping @autoclosure () -> Model.Action, file: StaticString = #filePath, line: UInt = #line, @ViewBuilder label: () -> Label) -> some View {
        Button(action: {
            model.send(action())
        }) {
            label()
        }
    }
}

// MARK: - Outputs

public extension View {
    /// Calls `handler` for each output `model` emits.
    ///
    /// For a view reacting to its own model's outputs (e.g. showing a toast
    /// after a save). Parents normally receive a child's outputs through the
    /// child's connection instead.
    ///
    /// ```swift
    /// content.onOutput(of: model) { output in
    ///     switch output {
    ///     case .saved: showToast = true
    ///     }
    /// }
    /// ```
    func onOutput<Model: ViewModel>(of model: Model, perform handler: @escaping (Model.Output) -> Void) -> some View {
        onReceive(model.outputs, perform: handler)
    }
}

// MARK: - RoutableView

/// A `BaseView` whose `body` wraps `content` in its own `NavigationStack`.
///
/// Not used in the default pattern, where the host wraps navigation roots in
/// `NavigationStack`. Don't conform a view to both `RoutableView` and
/// `ComponentView`: both provide a default `body`.
public protocol RoutableView: ComponentView {}

public extension RoutableView {
    /// `NavigationStack { content }`, calling `model.onAppear()` when it appears
    var body: some View {
        NavigationStack {
            content
                .onAppear {
                    model.onAppear()
                }
        }
    }
}

// MARK: - Destination Presentation

extension View {
    /// Presents `dest` using its `presentationStyle`.
    ///
    /// | Style | Modifier |
    /// |---|---|
    /// | `.push` | `.navigationDestination(item:)` (needs an enclosing `NavigationStack`) |
    /// | `.fullScreen` | `.fullScreenCover(item:)` |
    /// | `.customAlert` | `.customAlert(item:)` |
    /// | everything else | `.sheet(item:)` |
    ///
    /// All four modifiers are always attached, each seeing the value only when
    /// its style matches, so the view's identity is stable as `dest` changes.
    /// Dismissing writes `nil` back to `dest`.
    public func showDestination<D: RouteDestinationPresentable, V: View>(
        _ dest: Binding<D?>,
        @ViewBuilder destination: @escaping (D) -> V
    ) -> some View {
        self
            .navigationDestination(item: dest.matching([.push]), destination: destination)
            .sheet(item: dest.matching([.modal, .alert]), content: destination)
            .fullScreenCover(item: dest.matching([.fullScreen]), content: destination)
            .customAlert(item: dest.matching([.customAlert]), destination: destination)
    }
}

private extension Binding {
    /// The wrapped destination while its style is in `styles`, otherwise `nil`.
    /// Writing `nil` only clears the source if it still has one of `styles`.
    func matching<D: RouteDestinationPresentable>(_ styles: Set<PresentationStyle>) -> Binding<D?> where Value == D? {
        Binding<D?>(
            get: {
                guard let value = wrappedValue, styles.contains(value.presentationStyle) else { return nil }
                return value
            },
            set: { newValue in
                if let newValue {
                    wrappedValue = newValue
                } else if let current = wrappedValue, styles.contains(current.presentationStyle) {
                    wrappedValue = nil
                }
            }
        )
    }
}
